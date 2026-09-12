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
  signal,
  timeoutMs = 4500,
}) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error('GEMINI_UNAVAILABLE');
  const model = process.env.GEMINI_TEXT_MODEL || 'gemini-2.0-flash';
  const prompt = (messages || [])
    .filter((message) => message?.content)
    .map((message) => `${message.role}: ${String(message.content)}`)
    .join('\n\n');
  const contents = [{ role: 'user', parts: [{ text: prompt }] }];
  const generationConfig = { temperature, maxOutputTokens };
  if (responseMimeType) generationConfig.responseMimeType = responseMimeType;

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
  return text;
}

module.exports = { generateGeminiText, parseGeminiText };
