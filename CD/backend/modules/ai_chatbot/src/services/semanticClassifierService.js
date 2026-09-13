const { createChatCompletionWithFailover } = require('../config/openai');
const { generateGeminiText } = require('./geminiTextService');
const tokenConfig = require('../config/tokenConfig');
const { explicitNavigationRequest } = require('./explicitNavigationService');
const { planSoloRequest, applySoloPolicy } = require('./soloRequestPlanner');

const INTENT_TO_TOOL = Object.freeze({
  weather: 'weather',
  recommendation: 'recommendation',
  navigation: 'create_trip',
  map: 'show_location',
  trip_planning: 'create_trip',
  trip_update: 'update_trip',
  itinerary: 'generate_itinerary',
  traffic: 'traffic',
  reroute: 'reroute',
  profile_update: 'update_profile',
  community: 'discover_community',
  attachment_location: 'show_attachment_location',
  save: 'save_travel_item',
  saved_items: 'list_saved_travel_items',
  delete_saved_item: 'delete_saved_travel_item',
  link_analysis: 'analyze_link',
});

const SEMANTIC_INTENTS = Object.freeze([
  ...Object.keys(INTENT_TO_TOOL),
  'general_travel',
  'out_of_scope',
  'clarification',
  'unintelligible',
  'abusive',
]);

const classificationTool = {
  type: 'function',
  function: {
    name: 'classify_nova_request',
    description: 'Semantically classify the current Nova request and extract its entities. This function describes intent only and never performs an app action.',
    parameters: {
      type: 'object',
      properties: {
        intent: { type: 'string', enum: SEMANTIC_INTENTS },
        language: {
          type: 'object',
          properties: {
            primary: { type: 'string', enum: ['en', 'ms', 'zh-CN'] },
            mixed: { type: 'boolean' },
            style: { type: 'string', enum: ['english', 'malay', 'chinese', 'rojak'] },
          },
          required: ['primary', 'mixed', 'style'],
        },
        location: {
          type: 'object',
          properties: {
            name: { type: 'string' },
            country: { type: 'string' },
          },
          required: ['name', 'country'],
        },
        domain: { type: 'string', enum: ['malaysia_travel', 'travel', 'non_travel'] },
        confidence: { type: 'number' },
        parameters: { type: 'object', properties: {}, additionalProperties: true },
        draft_response: { type: 'string' },
        corrected_input: { type: 'string' },
      },
      required: ['intent', 'language', 'location', 'domain', 'confidence', 'parameters', 'draft_response'],
    },
  },
};

function validateClassification(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  if (!SEMANTIC_INTENTS.includes(value.intent)) return null;
  const language = value.language;
  if (!language || !['en', 'ms', 'zh-CN'].includes(language.primary) ||
      typeof language.mixed !== 'boolean' ||
      !['english', 'malay', 'chinese', 'rojak'].includes(language.style)) return null;
  if (!value.location || typeof value.location.name !== 'string' ||
      typeof value.location.country !== 'string') return null;
  if (!['malaysia_travel', 'travel', 'non_travel'].includes(value.domain)) return null;
  const confidence = Number(value.confidence);
  if (!Number.isFinite(confidence) || confidence < 0 || confidence > 1) return null;
  if (!value.parameters || typeof value.parameters !== 'object' || Array.isArray(value.parameters)) return null;
  if (typeof value.draft_response !== 'string') return null;

  const configuredMinimum = Number(process.env.NOVA_MIN_ACTION_CONFIDENCE);
  const minimumActionConfidence = Number.isFinite(configuredMinimum)
    ? Math.min(1, Math.max(0, configuredMinimum))
    : 0.55;
  const actionConfidenceSatisfied = confidence >= minimumActionConfidence;
  const actionDomainSatisfied = value.domain !== 'non_travel';
  let parameters = { ...value.parameters };
  if (value.intent === 'recommendation') {
    const asList = (input) => (Array.isArray(input)
      ? input
      : input === undefined || input === null || input === ''
        ? []
        : [input])
      .map((item) => String(item).trim())
      .filter(Boolean);
    parameters = {
      destination: parameters.destination,
      ...(typeof parameters.search_query === 'string' && parameters.search_query.trim()
        ? { search_query: parameters.search_query.trim().slice(0, 240) } : {}),
      requirements: [...new Set([
        ...asList(parameters.requirements),
        ...asList(parameters.preferences),
        ...asList(parameters.preference),
        ...asList(parameters.interests),
        ...asList(parameters.interest),
        ...asList(parameters.category),
      ])],
      excluded_requirements: [...new Set([
        ...asList(parameters.excluded_requirements),
        ...asList(parameters.exclusions),
      ])],
    };
  }
  if (value.location.name.trim() && !parameters.destination) {
    parameters.destination = value.location.name.trim();
  }
  if (parameters.destination === undefined) delete parameters.destination;
  return {
    intent: value.intent,
    language: { ...language },
    location: { ...value.location },
    domain: value.domain,
    confidence,
    parameters,
    draftResponse: value.draft_response.trim(),
    correctedInput: typeof value.corrected_input === 'string'
      ? value.corrected_input.trim()
      : '',
    toolName: actionConfidenceSatisfied && actionDomainSatisfied
      ? INTENT_TO_TOOL[value.intent] || null
      : null,
    allowMap: actionConfidenceSatisfied && actionDomainSatisfied &&
      ['navigation', 'map'].includes(value.intent),
    requiresClarification: !actionConfidenceSatisfied,
  };
}

function parseClassificationResponse(response) {
  const call = response?.choices?.[0]?.message?.tool_calls?.find(
    (item) => item?.function?.name === 'classify_nova_request',
  );
  const source = call?.function?.arguments || response?.choices?.[0]?.message?.content;
  if (!source) return null;
  try {
    return validateClassification(JSON.parse(source));
  } catch {
    return validateClassification(parseJsonObject(source));
  }
}

function parseJsonObject(value) {
  const candidate = String(value || '').match(/\{[\s\S]*\}/)?.[0];
  if (!candidate) return null;
  try {
    return JSON.parse(candidate);
  } catch (_) {
    return null;
  }
}

function buildClassificationMessages(messages) {
  return [
    ...messages,
    {
      role: 'user',
      content: [
        `Return one JSON object with this contract: ${JSON.stringify(classificationTool.function.parameters)}.`,
        'Set corrected_input to a conservative correction of the latest user message.',
        'For recommendation extract all explicit current-request requirements without relying on a fixed tag vocabulary. Set parameters.search_query to a concise English provider search preserving the requested cuisine, activity or venue, including unfamiliar requests. Example Arabian cuisine becomes Arabian restaurant; pottery classes becomes pottery classes. Do not add saved cultural preferences to this query. Broad personalized requests have no search_query or explicit requirements. Extract destination separately; near me uses GPS, not a historical destination. Category movement requests mean discovery, not navigation to an arbitrary venue. Never drop exclusions or restrictive conditions.',
        'Correct obvious Malaysian place shorthand or spelling such as png to Penang, but preserve meaning, numbers, names and the original language.',
        'For unintelligible input use intent unintelligible and ask the user to try again in the same language.',
        'For harassment or profanity without a useful travel request use intent abusive and respond calmly without repeating the abuse.',
        'Do not include markdown.',
      ].join(' '),
    },
  ];
}

async function classifyWithGemini(messages, signal) {
  const content = await generateGeminiText({
    messages: buildClassificationMessages(messages),
    temperature: 0,
    maxOutputTokens: tokenConfig.classifierMaxOutputTokens,
    responseMimeType: 'application/json',
    signal,
    timeoutMs: 4000,
  });
  const classification = validateClassification(parseJsonObject(content));
  if (!classification) throw new Error('Gemini semantic classification was invalid.');
  return {
    classification,
    response: { _fallbackUsed: false, _provider: 'gemini', usage: null },
  };
}

async function classifyRequest({
  messages,
  currentMessage,
  model = process.env.GROQ_MODEL,
  signal,
  preferFallbackClient = false,
  completion = createChatCompletionWithFailover,
}) {
  const plan = planSoloRequest(currentMessage);
  if (plan.groupAction || plan.discovery || (plan.simpleNearby && plan.requirements.length && !explicitNavigationRequest(currentMessage))) {
    const classification = validateClassification({
      intent: plan.groupAction ? 'out_of_scope' : 'recommendation',
      language: { primary: plan.language, mixed: false,
        style: plan.language === 'ms' ? 'malay' : plan.language === 'zh-CN' ? 'chinese' : 'english' },
      location: { name: '', country: '' }, domain: 'malaysia_travel', confidence: 1,
      parameters: { requirements: plan.requirements }, draft_response: plan.reply,
    });
    return { classification: applySoloPolicy(classification, currentMessage), response: { _fallbackUsed: false, _provider: 'deterministic', usage: null } };
  }
  const explicitNavigation = explicitNavigationRequest(currentMessage);
  if (explicitNavigation) {
    const classification = validateClassification({
      intent: 'navigation',
      language: {
        primary: explicitNavigation.languageCode,
        mixed: false,
        style: explicitNavigation.style,
      },
      location: { name: explicitNavigation.destination, country: '' },
      domain: 'malaysia_travel',
      confidence: 1,
      parameters: { destination: explicitNavigation.destination },
      draft_response: '',
      corrected_input: String(currentMessage || '').trim(),
    });
    return {
      classification: applySoloPolicy(classification, currentMessage),
      response: { _fallbackUsed: false, _provider: 'deterministic', usage: null },
    };
  }

  let geminiError = null;
  if (process.env.GEMINI_API_KEY) {
    try {
      const result = await classifyWithGemini(messages, signal);
      result.classification = applySoloPolicy(result.classification, currentMessage);
      return result;
    } catch (error) {
      geminiError = error;
      console.warn('[Nova classifier] Gemini unavailable:', error.message);
    }
  }
  try {
    const providerSignal = signal && typeof AbortSignal.any === 'function'
      ? AbortSignal.any([signal, AbortSignal.timeout(3200)])
      : signal;
    const response = await completion({
      model,
      temperature: 0,
      messages: buildClassificationMessages(messages),
      response_format: { type: 'json_object' },
      max_tokens: tokenConfig.classifierMaxOutputTokens,
      preferFallbackClient,
      signal: providerSignal,
    });
    const classification = parseClassificationResponse(response);
    if (!classification) throw new Error('Nova semantic classification was invalid.');
    response._provider = 'groq';
    return { classification: applySoloPolicy(classification, currentMessage), response };
  } catch (error) {
    if (geminiError) error.cause = geminiError;
    throw error;
  }
}

module.exports = {
  classifyRequest,
  validateClassification,
  parseClassificationResponse,
  INTENT_TO_TOOL,
  SEMANTIC_INTENTS,
};
