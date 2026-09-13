function positiveInteger(name, fallback) {
  const value = Number(process.env[name]);
  return Number.isInteger(value) && value > 0 ? value : fallback;
}

module.exports = Object.freeze({
  maxRecentHistoryMessages: positiveInteger('NOVA_MAX_RECENT_HISTORY_MESSAGES', 6),
  classifierHistoryMessages: positiveInteger('NOVA_CLASSIFIER_HISTORY_MESSAGES', 6),
  normalMaxOutputTokens: positiveInteger('NOVA_NORMAL_MAX_OUTPUT_TOKENS', 256),
  groundedMaxOutputTokens: positiveInteger('NOVA_GROUNDED_MAX_OUTPUT_TOKENS', 180),
  classifierMaxOutputTokens: positiveInteger('NOVA_CLASSIFIER_MAX_OUTPUT_TOKENS', 768),
  imageMaxOutputTokens: positiveInteger('NOVA_IMAGE_MAX_OUTPUT_TOKENS', 512),
  fileMaxOutputTokens: positiveInteger('NOVA_FILE_MAX_OUTPUT_TOKENS', 640),
  fileChunkSize: positiveInteger('NOVA_FILE_CHUNK_SIZE', 1400),
  fileChunkOverlap: positiveInteger('NOVA_FILE_CHUNK_OVERLAP', 180),
  fileTopK: positiveInteger('NOVA_FILE_TOP_K', 4),
  fileMaxContextChars: positiveInteger('NOVA_FILE_MAX_CONTEXT_CHARS', 5000),
  requestTimeoutMs: positiveInteger('NOVA_REQUEST_TIMEOUT_MS', 45000),
  classifierProviderTimeoutMs: positiveInteger('NOVA_CLASSIFIER_PROVIDER_TIMEOUT_MS', 9000),
  classifierStageTimeoutMs: positiveInteger('NOVA_CLASSIFIER_STAGE_TIMEOUT_MS', 24000),
  groundedProviderTimeoutMs: positiveInteger('NOVA_GROUNDED_PROVIDER_TIMEOUT_MS', 12000),
});
