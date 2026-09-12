const test = require('node:test');
const assert = require('node:assert/strict');

const { splitCompletionOptions } = require('./openai');

test('passes AbortSignal as SDK request metadata, never as Groq JSON', () => {
  const controller = new AbortController();
  const result = splitCompletionOptions({
    model: 'configured-model',
    messages: [],
    signal: controller.signal,
  });

  assert.equal(result.body.signal, undefined);
  assert.equal(result.body.preferFallbackClient, undefined);
  assert.equal(result.body.model, 'configured-model');
  assert.equal(result.requestOptions.signal, controller.signal);
});

test('keeps fallback-client selection out of the provider request body', () => {
  const result = splitCompletionOptions({
    model: 'configured-model',
    messages: [],
    preferFallbackClient: true,
  });

  assert.equal(result.body.preferFallbackClient, undefined);
  assert.equal(result.preferFallbackClient, true);
});
