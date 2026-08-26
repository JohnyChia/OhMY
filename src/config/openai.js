const OpenAI = require("openai");


const client1 = new OpenAI({
  apiKey: process.env.GROQ_API_KEY_1 || "local-development-key",
  baseURL: "https://api.groq.com/openai/v1"
});

const client2 = new OpenAI({
  apiKey: process.env.GROQ_API_KEY_2 || "local-development-key",
  baseURL: "https://api.groq.com/openai/v1"
});

async function createChatCompletionWithFailover(options) {
  try {
    const response = await client1.chat.completions.create(options);
    response._fallbackUsed = false;
    return response;
  } catch (error) {
    if (error.status === 429) {
      console.warn("GROQ RATE LIMIT (Key 1). Automatically failing over to Key 2...");
      const response = await client2.chat.completions.create(options);
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
  createChatCompletionWithFailover
};
