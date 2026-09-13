const OpenAI = require("openai");


const client1 = new OpenAI({
  apiKey: process.env.GROQ_API_KEY_1 || "local-development-key",
  baseURL: "https://api.groq.com/openai/v1"
});

const client2 = new OpenAI({
  apiKey: process.env.GROQ_API_KEY_2 || "local-development-key",
  baseURL: "https://api.groq.com/openai/v1"
});

const capacityBlockedUntil = [0, 0];

function durationSeconds(value) {
  const source = String(value || '').trim().toLowerCase();
  if (!source) return null;
  if (/^\d+(?:\.\d+)?$/.test(source)) return Math.ceil(Number(source));
  let total = 0;
  for (const match of source.matchAll(/(\d+(?:\.\d+)?)\s*(ms|s|m|h)/g)) {
    const amount = Number(match[1]);
    total += match[2] === 'ms' ? amount / 1000
      : match[2] === 'm' ? amount * 60
        : match[2] === 'h' ? amount * 3600
          : amount;
  }
  return total > 0 ? Math.ceil(total) : null;
}

function providerCooldownMs(error) {
  const headers = error?.headers;
  const header = (name) => typeof headers?.get === 'function'
    ? headers.get(name)
    : headers?.[name];
  const seconds = Math.max(
    durationSeconds(header('retry-after')) || 0,
    durationSeconds(header('x-ratelimit-reset-tokens')) || 0,
    durationSeconds(header('x-ratelimit-reset-requests')) || 0,
    Number(process.env.NOVA_PROVIDER_COOLDOWN_SECONDS) || 60,
  );
  return seconds * 1000;
}

function isCapacityFailure(error) {
  return [413, 429].includes(Number(error?.status)) ||
    /tokens per minute|rate limit|request too large/i.test(String(error?.message || ''));
}

async function requestFrom(client, index, body, requestOptions) {
  if (Date.now() < capacityBlockedUntil[index]) {
    const error = new Error('GROQ_CAPACITY_COOLDOWN');
    error.status = 429;
    throw error;
  }
  try {
    return await client.chat.completions.create(body, requestOptions);
  } catch (error) {
    if (isCapacityFailure(error)) {
      const cooldownMs = providerCooldownMs(error);
      capacityBlockedUntil[index] = Date.now() + cooldownMs;
      error.novaRetryAfterSeconds = Math.ceil(cooldownMs / 1000);
    }
    throw error;
  }
}

function splitCompletionOptions(options) {
  const { signal, preferFallbackClient = false, ...body } = options || {};
  return {
    body,
    requestOptions: signal ? { signal } : undefined,
    preferFallbackClient,
  };
}

async function createChatCompletionWithFailover(options) {
  // AbortSignal belongs to the OpenAI SDK request options (second argument),
  // not to the OpenAI-compatible JSON request body. Groq rejects unknown body
  // properties, which previously made every Nova chat request fail with 400.
  const { body, requestOptions, preferFallbackClient } = splitCompletionOptions(options);
  if (preferFallbackClient) {
    const response = await requestFrom(client2, 1, body, requestOptions);
    response._fallbackUsed = true;
    return response;
  }
  try {
    const response = await requestFrom(client1, 0, body, requestOptions);
    response._fallbackUsed = false;
    return response;
  } catch (error) {
    if (isCapacityFailure(error)) {
      console.warn("GROQ CAPACITY LIMIT (Key 1). Automatically failing over to Key 2...");
      const response = await requestFrom(client2, 1, body, requestOptions);
      response._fallbackUsed = true;
      return response;
    }
    throw error;
  }
}

module.exports = {
  isConfigured: !!process.env.GROQ_API_KEY_1,
  audio: client1.audio,
  chat: {
    completions: {
      create: createChatCompletionWithFailover
    }
  },
  createChatCompletionWithFailover,
  splitCompletionOptions,
  durationSeconds,
};
