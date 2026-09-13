const { AsyncLocalStorage } = require('async_hooks');

const storage = new AsyncLocalStorage();

function usageMiddleware(req, res, next) {
  const state = {
    requestType: req.path.includes('transcribe') ? 'voice' : req.path.includes('attachment') ? 'attachment' : 'chat',
    geminiCalls: 0,
    classifierCalls: 0,
    generationCalls: 0,
    audioCalls: 0,
    attachmentCalls: 0,
    cacheHits: 0,
  };
  storage.run(state, () => {
    res.once('finish', () => {
      console.info(
        `[NOVA_REQUEST_USAGE] request_type=${state.requestType} gemini_calls=${state.geminiCalls} ` +
        `classifier_calls=${state.classifierCalls} generation_calls=${state.generationCalls} ` +
        `audio_calls=${state.audioCalls} attachment_calls=${state.attachmentCalls} ` +
        `cache_hits=${state.cacheHits} bypassed=${state.geminiCalls === 0}`,
      );
    });
    next();
  });
}

function recordGeminiCall(type) {
  const state = storage.getStore();
  if (!state) return;
  state.geminiCalls += 1;
  if (type === 'semantic_classifier') state.classifierCalls += 1;
  else if (type === 'audio_transcription') state.audioCalls += 1;
  else if (type === 'image_analysis' || type === 'document_analysis') state.attachmentCalls += 1;
  else state.generationCalls += 1;
}

function recordCacheHit() {
  const state = storage.getStore();
  if (state) state.cacheHits += 1;
}

module.exports = { usageMiddleware, recordGeminiCall, recordCacheHit };
