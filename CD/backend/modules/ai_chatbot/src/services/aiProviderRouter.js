const OpenAI = require('openai');
const groq = require('../config/openai');
const { generateGeminiText } = require('./geminiTextService');

let openRouterClient;

function openRouter() {
  if (!process.env.OPENROUTER_API_KEY) return null;
  openRouterClient ??= new OpenAI({
    apiKey: process.env.OPENROUTER_API_KEY,
    baseURL: 'https://openrouter.ai/api/v1',
    defaultHeaders: {
      'HTTP-Referer': process.env.OPENROUTER_SITE_URL || 'https://ohmy.app',
      'X-Title': process.env.OPENROUTER_APP_NAME || 'OhMY Nova',
    },
  });
  return openRouterClient;
}

async function completionText(client, model, options) {
  const response = await client.chat.completions.create({
    model,
    messages: options.messages,
    temperature: options.temperature ?? 0,
    max_tokens: options.maxOutputTokens,
    ...(options.responseMimeType === 'application/json'
      ? { response_format: { type: 'json_object' } }
      : {}),
  }, options.signal ? { signal: options.signal } : undefined);
  const text = response.choices?.[0]?.message?.content?.trim();
  if (!text) throw new Error('EMPTY_PROVIDER_RESPONSE');
  return text;
}

function preserveProviderError(provider, cause) {
  cause.provider = provider;
  return cause;
}

async function generateText(options) {
  const providers = [];
  if (groq.isConfigured) {
    providers.push(['groq', () => completionText(
      { chat: { completions: { create: groq.createChatCompletionWithFailover } } },
      process.env.GROQ_MODEL,
      options,
    )]);
  }
  const openRouterClient = openRouter();
  if (openRouterClient) {
    providers.push(['openrouter', () => completionText(
      openRouterClient,
      process.env.OPENROUTER_MODEL || 'openrouter/free',
      options,
    )]);
  }
  if (process.env.GEMINI_API_KEY) {
    providers.push(['gemini', () => generateGeminiText(options)]);
  }

  const errors = [];
  for (const [provider, request] of providers) {
    try {
      const text = await request();
      console.info(`[AI_PROVIDER] selected=${provider} type=${options.requestType || 'text'}`);
      return text;
    } catch (cause) {
      errors.push(preserveProviderError(provider, cause));
      console.warn(`[AI_PROVIDER] failed=${provider} type=${options.requestType || 'text'} status=${cause?.status || 'unknown'}`);
    }
  }
  throw errors.find((error) => Number(error?.status) === 429) ||
    errors.at(-1) || new Error('NO_AI_PROVIDER_CONFIGURED');
}

function parseStructured(response) {
  const message = response.choices?.[0]?.message;
  const source = message?.tool_calls?.[0]?.function?.arguments || message?.content;
  if (!source) return null;
  try { return JSON.parse(source); } catch (_) { return null; }
}

function parseJsonValue(source) {
  if (typeof source !== 'string') return null;
  const trimmed = source.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
  try { return JSON.parse(trimmed); } catch (_) {
    const start = trimmed.indexOf('{');
    const end = trimmed.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try { return JSON.parse(trimmed.slice(start, end + 1)); } catch (_) { return null; }
  }
}

async function generateStructured(options) {
  const providers = [];
  const invoke = async (client, model) => {
    const response = await client.chat.completions.create({
      model,
      messages: options.messages,
      temperature: 0,
      tools: [{ type: 'function', function: {
        name: options.name,
        description: options.description,
        parameters: options.schema,
      }}],
      tool_choice: { type: 'function', function: { name: options.name } },
      parallel_tool_calls: false,
      max_tokens: options.maxOutputTokens,
    }, options.signal ? { signal: options.signal } : undefined);
    const value = parseStructured(response);
    if (!value) throw new Error('INVALID_STRUCTURED_PROVIDER_RESPONSE');
    return value;
  };
  if (groq.isConfigured) providers.push(['groq', () => invoke(
    { chat: { completions: { create: groq.createChatCompletionWithFailover } } },
    process.env.GROQ_CLASSIFIER_MODEL || process.env.GROQ_MODEL,
  )]);
  const openRouterClient = openRouter();
  if (openRouterClient) providers.push(['openrouter', () => invoke(
    openRouterClient,
    process.env.OPENROUTER_CLASSIFIER_MODEL || process.env.OPENROUTER_MODEL || 'openrouter/free',
  )]);
  if (process.env.GEMINI_API_KEY) providers.push(['gemini', async () => {
    const text = await generateGeminiText({
      ...options,
      responseMimeType: 'application/json',
      responseSchema: options.schema,
      thinkingLevel: 'minimal',
    });
    const value = parseJsonValue(text);
    if (!value) throw new Error('INVALID_STRUCTURED_PROVIDER_RESPONSE');
    return value;
  }]);
  const errors = [];
  for (const [provider, request] of providers) {
    try {
      const value = await request();
      console.info(`[AI_PROVIDER] selected=${provider} type=${options.requestType || 'structured'}`);
      return value;
    } catch (error) {
      errors.push(preserveProviderError(provider, error));
      console.warn(`[AI_PROVIDER] failed=${provider} type=${options.requestType || 'structured'} status=${error?.status || 'unknown'}`);
    }
  }
  throw errors.find((error) => Number(error?.status) === 429) || errors.at(-1) || new Error('NO_AI_PROVIDER_CONFIGURED');
}

module.exports = { generateText, generateStructured, parseJsonValue };
