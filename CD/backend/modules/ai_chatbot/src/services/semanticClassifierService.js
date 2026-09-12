const { createChatCompletionWithFailover } = require('../config/openai');
const { generateGeminiText } = require('./geminiTextService');

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
  if (!call?.function?.arguments) return null;
  try {
    return validateClassification(JSON.parse(call.function.arguments));
  } catch {
    return null;
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

async function classifyWithGemini(messages, signal) {
  const content = await generateGeminiText({
    messages: [
      ...messages,
      {
        role: 'user',
        content: `Return one JSON object with this contract: ${JSON.stringify(classificationTool.function.parameters)}. Do not include markdown.`,
      },
    ],
    temperature: 0,
    maxOutputTokens: 420,
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
  model = process.env.GROQ_MODEL,
  signal,
  preferFallbackClient = false,
  completion = createChatCompletionWithFailover,
}) {
  let geminiError = null;
  if (process.env.GEMINI_API_KEY) {
    try {
      return await classifyWithGemini(messages, signal);
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
      messages,
      tools: [classificationTool],
      tool_choice: { type: 'function', function: { name: 'classify_nova_request' } },
      parallel_tool_calls: false,
      max_tokens: 320,
      preferFallbackClient,
      signal: providerSignal,
    });
    const classification = parseClassificationResponse(response);
    if (!classification) throw new Error('Nova semantic classification was invalid.');
    return { classification, response };
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
