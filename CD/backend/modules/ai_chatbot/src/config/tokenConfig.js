function positiveInteger(name, fallback) {
  const value = Number(process.env[name]);
  return Number.isInteger(value) && value > 0 ? value : fallback;
}

module.exports = Object.freeze({
  classifierHistoryMessages: positiveInteger('NOVA_CLASSIFIER_HISTORY_MESSAGES', 2),
  classifierMessageChars: positiveInteger('NOVA_CLASSIFIER_MESSAGE_CHARS', 900),
  classifierMaxOutputTokens: positiveInteger('NOVA_CLASSIFIER_MAX_OUTPUT_TOKENS', 420),
  groundedMaxOutputTokens: positiveInteger('NOVA_GROUNDED_MAX_OUTPUT_TOKENS', 180),
  normalMaxOutputTokens: positiveInteger('NOVA_NORMAL_MAX_OUTPUT_TOKENS', 220),
  requestTimeoutMs: positiveInteger('NOVA_REQUEST_TIMEOUT_MS', 26000),
});
