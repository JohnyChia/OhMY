const { createChatCompletionWithFailover } = require('../config/openai');
const { generateGeminiText } = require('./geminiTextService');
const { ATTRACTION_TAGS } = require('../config/attractionTags');
const tokenConfig = require('../config/tokenConfig');
const { generateStructured } = require('./aiProviderRouter');

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
  weather_check: 'weather',
  check_weather: 'weather',
  weather_forecast: 'weather',
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
        intent: {
          type: 'string',
          enum: SEMANTIC_INTENTS,
          description: 'Use clarification only when the requested travel operation or its indispensable subject cannot be understood. A weather request with a geographic destination is complete; its date is optional and defaults to today. Use out_of_scope for understandable harmless non-travel input. Safety is evaluated separately.',
        },
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
        attachment_action: {
          type: 'string',
          enum: ['none', 'explain', 'save', 'map', 'navigate'],
          description: 'The action the current user explicitly requests for the attached evidence. Merely recognizing a place is explain, not map or navigation.',
        },
        confidence: { type: 'number' },
        parameters: {
          type: 'object',
          properties: {
            destination: { type: 'string' },
            travel_date: { type: 'string', description: 'Optional date or period. Omit it when the user asks for weather without specifying a time; the weather service will use today.' },
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
  if (!Number.isFinite(parsedConfidence) || parsedConfidence < 0 || parsedConfidence > 1) {
    return null;
  }
  const confidence = parsedConfidence;
  const rawParameters = value.parameters && typeof value.parameters === 'object' && !Array.isArray(value.parameters)
    ? value.parameters : {};
  const safetyAccepted = value.safety?.acceptable !== false;
  const attachmentAction = ['none', 'explain', 'save', 'map', 'navigate'].includes(value.attachment_action)
    ? value.attachment_action
    : 'none';

  const configuredMinimum = Number(process.env.NOVA_MIN_ACTION_CONFIDENCE);
  const minimumActionConfidence = Number.isFinite(configuredMinimum)
    ? Math.min(1, Math.max(0, configuredMinimum))
    : 0.55;
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
  // Confidence is advisory model metadata. For low-risk read-only requests,
  // an explicit semantic intent plus its required entity is stronger evidence
  // than a generic global score. This prevents fully specified weather/place
  // questions from being downgraded to clarification without matching phrases.
  const hasDestination = typeof parameters.destination === 'string' &&
    parameters.destination.trim().length > 0;
  const hasRecommendationSubject = hasDestination ||
    (Array.isArray(parameters.requirements) && parameters.requirements.length > 0);
  const hasCompleteReadOnlyIntent =
    (intent === 'weather' && hasDestination) ||
    (intent === 'traffic' && hasDestination) ||
    (intent === 'recommendation' && hasRecommendationSubject) ||
    intent === 'community' ||
    intent === 'saved_items' ||
    intent === 'link_analysis';
  const actionConfidenceSatisfied = confidence >= minimumActionConfidence ||
    hasCompleteReadOnlyIntent;
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
    attachmentAction,
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

async function classifyWithGemini(messages, signal, usageContext, cacheScope) {
  const content = await generateGeminiText({
    messages,
    temperature: 0,
    maxOutputTokens: tokenConfig.classifierMaxOutputTokens,
    responseMimeType: 'application/json',
    responseSchema: classificationTool.function.parameters,
    requestType: 'semantic_classifier',
    usageContext,
    cacheScope,
    signal,
    timeoutMs: tokenConfig.classifierProviderTimeoutMs,
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
      ? AbortSignal.any([signal, AbortSignal.timeout(tokenConfig.classifierProviderTimeoutMs)])
      : AbortSignal.timeout(tokenConfig.classifierProviderTimeoutMs);
    const response = await completion({
      model,
      temperature: 0,
      messages,
      tools: [classificationTool],
      tool_choice: { type: 'function', function: { name: 'classify_nova_request' } },
      parallel_tool_calls: false,
      max_tokens: tokenConfig.classifierMaxOutputTokens,
      preferFallbackClient,
      signal: providerSignal,
    });
    const classification = parseClassificationResponse(response);
    if (!classification) {
      throw new Error('Semantic classifier returned unusable output.');
    }
    return { classification, response };
}

async function classifyRequest({
  messages,
  model = process.env.GROQ_MODEL,
  signal,
  preferFallbackClient = false,
  completion = createChatCompletionWithFailover,
  usageContext = {},
  cacheScope = 'public',
}) {
  if (completion === createChatCompletionWithFailover && !preferFallbackClient) {
    try {
      const value = await generateStructured({
        messages,
        name: classificationTool.function.name,
        description: classificationTool.function.description,
        schema: classificationTool.function.parameters,
        maxOutputTokens: tokenConfig.classifierMaxOutputTokens,
        requestType: 'semantic_classifier',
        usageContext,
        cacheScope,
        signal,
        timeoutMs: tokenConfig.classifierProviderTimeoutMs,
      });
      const classification = validateClassification(value);
      if (!classification) throw new Error('Semantic classifier returned unusable output.');
      return { classification, response: { _fallbackUsed: false, _provider: 'router', usage: null } };
    } catch (cause) {
      const unavailable = new Error('Nova semantic classification is temporarily unavailable.');
      unavailable.code = 'NOVA_CLASSIFIER_UNAVAILABLE';
      unavailable.status = cause?.status;
      unavailable.headers = cause?.headers;
      unavailable.novaRetryAfterSeconds = cause?.novaRetryAfterSeconds;
      unavailable.cause = cause;
      throw unavailable;
    }
  }
  const geminiProvider = () => classifyWithGemini(
    messages,
    signal,
    usageContext,
    cacheScope,
  );
  const groqProvider = () => classifyWithGroq({
    messages,
    model,
    signal,
    preferFallbackClient,
    completion,
  });
  const classifierPrimary = String(
    process.env.NOVA_CLASSIFIER_PRIMARY || 'groq',
  ).trim().toLowerCase();
  const providers = classifierPrimary === 'gemini'
    ? [
        ...(process.env.GEMINI_API_KEY ? [geminiProvider] : []),
        groqProvider,
      ]
    : [
        groqProvider,
        ...(process.env.GEMINI_API_KEY ? [geminiProvider] : []),
      ];

  const errors = [];
  for (const request of providers) {
    try {
      return await request();
    } catch (error) {
      errors.push(error);
      console.warn('[Nova classifier] Provider unavailable; trying fallback:', error?.message);
    }
  }

  const capacityError = errors.find((error) =>
    Number(error?.status) === 429 ||
    /rate limit|tokens per minute/i.test(String(error?.message || '')),
  );
  if (capacityError) throw capacityError;
  const unavailable = new Error('Nova semantic classification is temporarily unavailable.');
  unavailable.code = 'NOVA_CLASSIFIER_UNAVAILABLE';
  unavailable.causes = errors.map((error) => error?.message).filter(Boolean);
  throw unavailable;
}

module.exports = {
  classifyRequest,
  validateClassification,
  parseClassificationResponse,
  INTENT_TO_TOOL,
  SEMANTIC_INTENTS,
  unavailableClassification,
};
