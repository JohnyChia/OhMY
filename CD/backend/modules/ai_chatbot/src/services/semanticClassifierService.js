const { createChatCompletionWithFailover } = require('../config/openai');
const { generateGeminiText } = require('./geminiTextService');
const { ATTRACTION_TAGS } = require('../config/attractionTags');

const INTENT_TO_TOOL = Object.freeze({
  weather: 'weather',
  recommendation: 'recommendation',
  navigation: 'show_location',
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

const INTENT_ALIASES = Object.freeze({
  recommend_place: 'recommendation',
  recommend_places: 'recommendation',
  recommendations: 'recommendation',
  create_trip: 'trip_planning',
  update_trip: 'trip_update',
  generate_itinerary: 'itinerary',
  show_location: 'map',
  discover_community: 'community',
  update_profile: 'profile_update',
  save_travel_item: 'save',
  list_saved_travel_items: 'saved_items',
  delete_saved_travel_item: 'delete_saved_item',
  analyze_link: 'link_analysis',
});

const INTENT_PARAMETER_KEYS = Object.freeze({
  weather: ['destination', 'travel_date'],
  recommendation: ['destination', 'open_nearest', 'requirements', 'excluded_requirements'],
  navigation: ['destination'],
  map: ['destination'],
  trip_planning: ['destination', 'duration', 'interest', 'budget', 'travel_date'],
  trip_update: ['destination', 'duration', 'interest', 'interest_remove', 'budget', 'travel_date'],
  itinerary: ['generate'],
  traffic: ['destination'],
  reroute: ['reason', 'avoid_locations'],
  profile_update: ['favorite_categories', 'travel_style', 'budget_preference', 'preferred_language'],
  community: ['query'],
  attachment_location: [],
  save: ['title', 'summary', 'source_name', 'source_type', 'source_url', 'location_hint', 'google_place_id', 'latitude', 'longitude', 'travel_tags'],
  saved_items: ['limit'],
  delete_saved_item: ['item_id'],
  link_analysis: ['url'],
});

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
            kind: { type: 'string', enum: ['geographic', 'place_category', 'unspecified'] },
          },
          required: ['name', 'country'],
        },
        domain: { type: 'string', enum: ['malaysia_travel', 'travel', 'non_travel'] },
        safety: {
          type: 'object',
          description: 'Semantic safety decision for the current message. Reject toxic, abusive, threatening, sexual, discriminatory, or otherwise unsafe content.',
          properties: {
            acceptable: { type: 'boolean' },
            reason: { type: 'string' },
          },
          required: ['acceptable', 'reason'],
        },
        confidence: { type: 'number' },
        parameters: {
          type: 'object',
          properties: {
            destination: { type: 'string' },
            travel_date: { type: 'string' },
            open_nearest: { type: 'boolean' },
            requirements: { type: 'array', items: { type: 'string', enum: ATTRACTION_TAGS } },
            excluded_requirements: { type: 'array', items: { type: 'string' } },
          },
          additionalProperties: true,
        },
        draft_response: { type: 'string' },
      },
      required: ['intent', 'language', 'location', 'domain', 'confidence', 'parameters', 'draft_response'],
    },
  },
};

function validateClassification(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const rawIntent = String(value.intent || value.action || value.tool || '')
    .trim().toLowerCase().replace(/[\s-]+/g, '_');
  const intent = INTENT_ALIASES[rawIntent] || rawIntent;
  if (!SEMANTIC_INTENTS.includes(intent)) return null;
  const rawLanguage = value.language && typeof value.language === 'object'
    ? value.language
    : { primary: value.language || value.languageCode || value.language_code };
  const primaryAliases = {
    en: 'en', english: 'en', ms: 'ms', malay: 'ms', 'bahasa malaysia': 'ms',
    zh: 'zh-CN', 'zh-cn': 'zh-CN', chinese: 'zh-CN', mandarin: 'zh-CN',
  };
  const primary = primaryAliases[String(rawLanguage.primary || '').trim().toLowerCase()];
  if (!primary) return null;
  const allowedStyles = ['english', 'malay', 'chinese', 'rojak'];
  const defaultStyle = primary === 'ms' ? 'malay' : primary === 'zh-CN' ? 'chinese' : 'english';
  const language = {
    primary,
    mixed: rawLanguage.mixed === true,
    style: allowedStyles.includes(rawLanguage.style) ? rawLanguage.style : defaultStyle,
  };
  const rawLocation = value.location && typeof value.location === 'object' ? value.location : {};
  const location = {
    name: typeof rawLocation.name === 'string' ? rawLocation.name : '',
    country: typeof rawLocation.country === 'string' ? rawLocation.country : '',
    kind: ['geographic', 'place_category', 'unspecified'].includes(rawLocation.kind)
      ? rawLocation.kind : 'unspecified',
  };
  const domain = ['malaysia_travel', 'travel', 'non_travel'].includes(value.domain)
    ? value.domain : (intent === 'out_of_scope' ? 'non_travel' : 'travel');
  const parsedConfidence = Number(value.confidence);
  const confidence = Number.isFinite(parsedConfidence)
    ? Math.min(1, Math.max(0, parsedConfidence)) : 0.6;
  const rawParameters = value.parameters && typeof value.parameters === 'object' && !Array.isArray(value.parameters)
    ? value.parameters : {};
  const safetyAccepted = value.safety?.acceptable !== false;

  const configuredMinimum = Number(process.env.NOVA_MIN_ACTION_CONFIDENCE);
  const minimumActionConfidence = Number.isFinite(configuredMinimum)
    ? Math.min(1, Math.max(0, configuredMinimum))
    : 0.55;
  const actionConfidenceSatisfied = confidence >= minimumActionConfidence;
  const actionDomainSatisfied = domain !== 'non_travel' && safetyAccepted;
  let parameters = { ...rawParameters };
  const destinationCandidate = [
    parameters.destination,
    parameters.place,
    parameters.location,
    parameters.endpoint,
    parameters.target,
    location.kind !== 'place_category' ? location.name : '',
  ].find((item) => typeof item === 'string' && item.trim());
  if (destinationCandidate) parameters.destination = destinationCandidate.trim();
  delete parameters.place;
  delete parameters.location;
  delete parameters.endpoint;
  delete parameters.target;
  if (intent === 'recommendation') {
    const asList = (input) => (Array.isArray(input)
      ? input
      : input === undefined || input === null || input === ''
        ? []
        : [input])
      .map((item) => String(item).trim())
      .filter(Boolean);
    parameters = {
      destination: parameters.destination,
      open_nearest: parameters.open_nearest === true,
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
    if (location.kind === 'place_category') {
      const category = location.name.trim() || parameters.destination;
      if (category) parameters.requirements = [...new Set([...parameters.requirements, category])];
      delete parameters.destination;
    }
  }
  if (location.name.trim() && location.kind !== 'place_category' && !parameters.destination) {
    parameters.destination = location.name.trim();
  }
  if (parameters.destination === undefined) delete parameters.destination;
  const allowedParameterKeys = INTENT_PARAMETER_KEYS[intent];
  if (allowedParameterKeys) {
    parameters = Object.fromEntries(
      Object.entries(parameters).filter(([key]) => allowedParameterKeys.includes(key)),
    );
  }
  return {
    intent,
    language: { ...language },
    location,
    domain,
    confidence,
    parameters,
    draftResponse: typeof value.draft_response === 'string' ? value.draft_response.trim() : '',
    toolName: actionConfidenceSatisfied && actionDomainSatisfied
      ? INTENT_TO_TOOL[intent] || null
      : null,
    allowMap: actionConfidenceSatisfied && actionDomainSatisfied &&
      ['navigation', 'map'].includes(intent),
    requiresClarification: !actionConfidenceSatisfied,
    safety: {
      acceptable: safetyAccepted,
      reason: String(value.safety?.reason || '').slice(0, 160),
    },
  };
}

function parseClassificationResponse(response) {
  const message = response?.choices?.[0]?.message;
  const content = Array.isArray(message?.content)
    ? message.content.map((part) => part?.text || part?.content || '').join('')
    : message?.content;
  if (content) {
    const parsed = validateClassification(unwrapClassification(parseJsonObject(content)));
    if (parsed) return parsed;
  }
  const call = message?.tool_calls?.find(
    (item) => item?.function?.name === 'classify_nova_request',
  );
  if (!call?.function?.arguments) return null;
  try {
    const args = typeof call.function.arguments === 'string'
      ? JSON.parse(call.function.arguments)
      : call.function.arguments;
    return validateClassification(unwrapClassification(args));
  } catch {
    return null;
  }
}

function parseJsonObject(value) {
  if (value && typeof value === 'object' && !Array.isArray(value)) return value;
  const candidate = String(value || '').match(/\{[\s\S]*\}/)?.[0];
  if (!candidate) return null;
  try {
    return JSON.parse(candidate);
  } catch (_) {
    return null;
  }
}

function unwrapClassification(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return value;
  for (const key of ['classification', 'result', 'data']) {
    const nested = value[key];
    if (nested && typeof nested === 'object' && !Array.isArray(nested)) return nested;
  }
  return value;
}

function unavailableClassification(messages) {
  const current = [...(messages || [])].reverse().find((message) => message?.role === 'user');
  let payload = {};
  try { payload = JSON.parse(String(current?.content || '{}')); } catch (_) {}
  const message = String(payload.message || current?.content || '');
  const hint = String(payload.speech_language_hint || '').toLowerCase();
  const primary = /\p{Script=Han}/u.test(message) || hint.startsWith('zh')
    ? 'zh-CN'
    : hint.startsWith('ms') ? 'ms' : 'en';
  const draftResponse = primary === 'zh-CN'
    ? '我暂时无法确认您的具体旅游需求，请换一种说法再试一次。'
    : primary === 'ms'
      ? 'Saya belum dapat mengesahkan permintaan perjalanan anda. Sila cuba nyatakan semula.'
      : 'I could not confirm the travel request. Please rephrase it and try again.';
  return {
    intent: 'clarification',
    language: { primary, mixed: false, style: primary === 'zh-CN' ? 'chinese' : primary === 'ms' ? 'malay' : 'english' },
    location: { name: '', country: '', kind: 'unspecified' },
    domain: 'travel',
    confidence: 0,
    parameters: {},
    draftResponse,
    toolName: null,
    allowMap: false,
    requiresClarification: true,
    safety: { acceptable: true, reason: 'CLASSIFIER_OUTPUT_UNAVAILABLE' },
  };
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
    maxOutputTokens: 700,
    responseMimeType: 'application/json',
    signal,
    timeoutMs: 2200,
  });
  const classification = validateClassification(parseJsonObject(content));
  if (!classification) throw new Error('Gemini semantic classification was invalid.');
  return {
    classification,
    response: { _fallbackUsed: false, _provider: 'gemini', usage: null },
  };
}

async function classifyWithGroq({ messages, model, signal, preferFallbackClient, completion }) {
    const providerSignal = signal && typeof AbortSignal.any === 'function'
      ? AbortSignal.any([signal, AbortSignal.timeout(4800)])
      : AbortSignal.timeout(4800);
    const request = {
      model,
      temperature: 0,
      messages: [...messages, {
        role: 'user',
        content: `Return exactly one JSON object matching this schema: ${JSON.stringify(classificationTool.function.parameters)}. Do not call a tool and do not include markdown.`,
      }],
      max_tokens: 700,
      preferFallbackClient,
      signal: providerSignal,
    };
    let response;
    try {
      response = await completion({
        ...request,
        response_format: { type: 'json_object' },
      });
    } catch (structuredError) {
      const canRetryPlainJson = Number(structuredError?.status) === 400 &&
        /failed_generation|validate json|json/i.test(String(structuredError?.message || ''));
      if (!canRetryPlainJson) throw structuredError;
      console.warn('[Nova classifier] Structured JSON generation failed; retrying parseable JSON output.');
      response = await completion(request);
    }
    let classification = parseClassificationResponse(response);
    if (!classification) {
      const repairResponse = await completion({
        model,
        temperature: 0,
        messages,
        tools: [classificationTool],
        tool_choice: { type: 'function', function: { name: 'classify_nova_request' } },
        parallel_tool_calls: false,
        max_tokens: 700,
        preferFallbackClient: true,
        signal: providerSignal,
      });
      classification = parseClassificationResponse(repairResponse);
      if (classification) response = repairResponse;
    }
    if (!classification) {
      console.warn('[Nova classifier] Providers returned unusable semantic output; requesting clarification.');
      classification = unavailableClassification(messages);
    }
    return { classification, response };
}

async function classifyRequest({
  messages,
  model = process.env.GROQ_MODEL,
  signal,
  preferFallbackClient = false,
  completion = createChatCompletionWithFailover,
}) {
  const providers = [
    classifyWithGroq({ messages, model, signal, preferFallbackClient, completion }),
  ];
  if (process.env.GEMINI_API_KEY) providers.push(classifyWithGemini(messages, signal));
  try {
    return await Promise.any(providers);
  } catch (aggregateError) {
    const errors = Array.isArray(aggregateError?.errors) ? aggregateError.errors : [aggregateError];
    const capacityError = errors.find((error) =>
      Number(error?.status) === 429 ||
      /rate limit|tokens per minute/i.test(String(error?.message || '')),
    );
    if (capacityError) throw capacityError;
    console.warn(
      '[Nova classifier] All providers failed; requesting clarification:',
      errors.map((error) => error?.message).filter(Boolean).join(' | '),
    );
    return {
      classification: unavailableClassification(messages),
      response: { _fallbackUsed: preferFallbackClient, _provider: 'local_safe_fallback', usage: null },
    };
  }
}

module.exports = {
  classifyRequest,
  validateClassification,
  parseClassificationResponse,
  INTENT_TO_TOOL,
  SEMANTIC_INTENTS,
  unavailableClassification,
};
