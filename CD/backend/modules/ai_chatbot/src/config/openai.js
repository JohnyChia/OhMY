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
      capacityBlockedUntil[index] = Date.now() + 60_000;
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
};
