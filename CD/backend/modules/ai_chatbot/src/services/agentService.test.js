const test = require('node:test');
const assert = require('node:assert/strict');

const {
  validateToolArguments,
  compactDrivingReply,
  groundedToolFallback,
} = require('./agentService');

test('allows supported profile language values', () => {
  assert.equal(
    validateToolArguments('update_profile', { preferred_language: 'zh-CN' }),
    null,
  );
});

test('rejects unsupported tool arguments before execution', () => {
  assert.match(
    validateToolArguments('weather', {
      destination: 'user supplied destination',
      unsupported_field: true,
    }),
    /Unsupported argument/i,
  );
});

test('accepts the model-only attachment location action', () => {
  assert.equal(validateToolArguments('show_attachment_location', {}), null);
});

test('bounds driving replies without changing short replies', () => {
  const short = 'A short model-generated reply.';
  assert.equal(compactDrivingReply(short), short);
  assert.ok(compactDrivingReply('Sentence. '.repeat(100)).length <= 280);
});

test('keeps verified recommendation data when the reply model is unavailable', () => {
  const reply = groundedToolFallback([{
    tool: 'recommendation',
    success: true,
    data: {
      recommendations: [
        { name: 'Provider Place', address: 'Provider Address' },
      ],
    },
  }]);
  assert.equal(reply, 'Provider Place — Provider Address');
});
