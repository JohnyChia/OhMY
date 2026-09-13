const crypto = require('crypto');
const { recordGeminiCall, recordCacheHit } = require('./requestUsageService');

const responseCache = new Map();
const inFlightRequests = new Map();
const DEFAULT_CACHE_TTL_MS = 5 * 60 * 1000;
const DEFAULT_CACHE_MAX_ENTRIES = 200;

function parseGeminiText(payload) {
  return payload?.candidates?.[0]?.content?.parts
    ?.map((part) => part?.text || '')
    .join('')
    .trim() || '';
}

function positiveInteger(value, fallback) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

// Gemini accepts an OpenAPI-style schema subset, while Groq/OpenRouter accept
// broader JSON Schema. Normalize recursively at the provider boundary so the
// canonical backend schema and its post-response validation remain unchanged.
function geminiResponseSchema(schema) {
  if (Array.isArray(schema)) return schema.map(geminiResponseSchema);
  if (!schema || typeof schema !== 'object') return schema;
  const normalized = {};
  for (const [key, value] of Object.entries(schema)) {
    if (key === 'additionalProperties' ||
        key === 'patternProperties' ||
        key === '$schema' ||
        key === '$id' ||
        key === '$defs' ||
        key === 'definitions' ||
        key === 'unevaluatedProperties') {
      continue;
    }
    normalized[key] = geminiResponseSchema(value);
  }
  return normalized;
}

function cacheKeyFor({ model, prompt, temperature, maxOutputTokens, responseMimeType, responseSchema, thinkingLevel, cacheScope }) {
  return crypto.createHash('sha256').update(JSON.stringify({
    model,
    prompt,
    temperature,
    maxOutputTokens,
    responseMimeType: responseMimeType || '',
    responseSchema: responseSchema || null,
    thinkingLevel: thinkingLevel || '',
    cacheScope: String(cacheScope || 'public'),
    cacheVersion: String(process.env.NOVA_GEMINI_CACHE_VERSION || 'v2'),
  })).digest('hex');
}

function logGeminiUsage({ type, model, payload, tools = 0, history = 0, memory = false, profile = false, trip = false, attachment = false, recordCall = true }) {
  if (recordCall) recordGeminiCall(type);
  const usage = payload?.usageMetadata || {};
  console.info(
    `[GEMINI_USAGE] type=${type || 'unknown'} model=${model || 'unknown'} ` +
    `input=${Number(usage.promptTokenCount) || 0} output=${Number(usage.candidatesTokenCount) || 0} ` +
    `total=${Number(usage.totalTokenCount) || 0} tools=${Number(tools) || 0} ` +
    `history=${Number(history) || 0} memory=${memory === true} profile=${profile === true} ` +
    `trip=${trip === true} attachment=${attachment === true} bypassed=false cache=false`,
  );
}

function rememberResponse(key, text) {
  const ttlMs = positiveInteger(process.env.NOVA_GEMINI_CACHE_TTL_MS, DEFAULT_CACHE_TTL_MS);
  const maximum = positiveInteger(process.env.NOVA_GEMINI_CACHE_MAX_ENTRIES, DEFAULT_CACHE_MAX_ENTRIES);
  responseCache.delete(key);
  responseCache.set(key, { text, expiresAt: Date.now() + ttlMs });
  while (responseCache.size > maximum) {
    responseCache.delete(responseCache.keys().next().value);
  }
}

function combinedSignal(signal, milliseconds) {
  const timeoutSignal = AbortSignal.timeout(milliseconds);
  return signal && typeof AbortSignal.any === 'function'
    ? AbortSignal.any([signal, timeoutSignal])
    : timeoutSignal;
}

async function generateGeminiText({
  messages,
  temperature = 0,
  maxOutputTokens = 240,
  responseMimeType,
  responseSchema,
  thinkingLevel,
  signal,
  timeoutMs = 4500,
  requestType = 'text',
  usageContext = {},
  cacheScope = 'public',
}) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error('GEMINI_UNAVAILABLE');
  const model = process.env.GEMINI_TEXT_MODEL || 'gemini-3.6-flash';
  const prompt = (messages || [])
    .filter((message) => message?.content)
    .map((message) => `${message.role}: ${String(message.content)}`)
    .join('\n\n');
  const contents = [{ role: 'user', parts: [{ text: prompt }] }];
  const generationConfig = { temperature, maxOutputTokens };
  if (thinkingLevel) generationConfig.thinkingConfig = { thinkingLevel };
  if (responseMimeType) generationConfig.responseMimeType = responseMimeType;
  const normalizedResponseSchema = responseSchema
    ? geminiResponseSchema(responseSchema)
    : null;
  if (normalizedResponseSchema) {
    generationConfig.responseSchema = normalizedResponseSchema;
  }

  const cacheKey = cacheKeyFor({
    model,
    prompt,
    temperature,
    maxOutputTokens,
    responseMimeType,
    responseSchema: normalizedResponseSchema,
    thinkingLevel,
    cacheScope,
  });
  const cached = responseCache.get(cacheKey);
  if (cached?.expiresAt > Date.now()) {
    responseCache.delete(cacheKey);
    responseCache.set(cacheKey, cached);
    recordCacheHit();
    console.info(`[GEMINI_USAGE] type=${requestType} model=${model} input=0 output=0 total=0 tools=${Number(usageContext.tools) || 0} history=${Number(usageContext.history) || 0} memory=${usageContext.memory === true} profile=${usageContext.profile === true} trip=${usageContext.trip === true} attachment=${usageContext.attachment === true} bypassed=true cache=true`);
    return cached.text;
  }
  if (cached) responseCache.delete(cacheKey);
  if (inFlightRequests.has(cacheKey)) return inFlightRequests.get(cacheKey);

  const request = (async () => {
    recordGeminiCall(requestType);
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ generationConfig, contents }),
        signal: combinedSignal(signal, timeoutMs),
      },
    );
    const payload = await response.json();
    if (!response.ok) {
      const error = new Error(payload?.error?.message || `Gemini HTTP ${response.status}`);
      error.status = response.status;
      error.headers = response.headers;
      throw error;
    }
    const text = parseGeminiText(payload);
    if (!text) throw new Error('GEMINI_EMPTY_RESPONSE');
    logGeminiUsage({ type: requestType, model, payload, ...usageContext, recordCall: false });
    rememberResponse(cacheKey, text);
    return text;
  })();
  inFlightRequests.set(cacheKey, request);
  try {
    return await request;
  } finally {
    inFlightRequests.delete(cacheKey);
  }
}

function clearGeminiTextCache() {
  responseCache.clear();
  inFlightRequests.clear();
}

module.exports = {
  generateGeminiText,
  parseGeminiText,
  clearGeminiTextCache,
  cacheKeyFor,
  logGeminiUsage,
  geminiResponseSchema,
};
