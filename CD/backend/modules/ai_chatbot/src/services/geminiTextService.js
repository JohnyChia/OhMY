function parseGeminiText(payload) {
  return payload?.candidates?.[0]?.content?.parts
    ?.map((part) => part?.text || '')
    .join('')
    .trim() || '';
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
  signal,
  timeoutMs = 4500,
}) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error('GEMINI_UNAVAILABLE');
  // 2.0 Flash has been shut down. Flash-Lite is the default because Nova's
  // work is short classification and grounded summarisation, not long-form
  // reasoning. The model remains configurable without a code change.
  const model = process.env.GEMINI_TEXT_MODEL || 'gemini-3.5-flash-lite';
  const prompt = (messages || [])
    .filter((message) => message?.content)
    .map((message) => `${message.role}: ${String(message.content)}`)
    .join('\n\n');
  const contents = [{ role: 'user', parts: [{ text: prompt }] }];
  const generationConfig = { temperature, maxOutputTokens };
  if (responseMimeType) generationConfig.responseMimeType = responseMimeType;
  if (responseSchema) generationConfig.responseSchema = responseSchema;

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
    throw error;
  }
  const text = parseGeminiText(payload);
  if (!text) throw new Error('GEMINI_EMPTY_RESPONSE');
  const usage = payload.usageMetadata || {};
  console.info(
    `[GEMINI_USAGE] model=${model} input=${usage.promptTokenCount || 0} ` +
    `output=${usage.candidatesTokenCount || 0} total=${usage.totalTokenCount || 0}`,
  );
  return text;
}

module.exports = { generateGeminiText, parseGeminiText };
