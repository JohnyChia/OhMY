const test = require('node:test');
const assert = require('node:assert/strict');
const {
  guardConversationInput,
  isClearlyGibberish,
  isAbuseOnly,
} = require('./conversationGuardService');

test('rejects obvious keyboard mash without spending model tokens', () => {
  assert.equal(isClearlyGibberish('asdfghjkl'), true);
  assert.equal(guardConversationInput('asdfghjkl').intent, 'unintelligible');
});

test('allows the exact navigation requests rejected in the Android app', () => {
  for (const input of [
    'Go to Penang now',
    'go penang now',
    'I want to start a trip to Penang',
  ]) {
    assert.equal(isClearlyGibberish(input), false, input);
    assert.equal(guardConversationInput(input).handled, false, input);
  }
});

test('rejects punctuation-only input', () => {
  assert.equal(isClearlyGibberish('.'), true);
  assert.equal(guardConversationInput('.').intent, 'unintelligible');
});

test('does not treat multilingual travel input as gibberish', () => {
  assert.equal(isClearlyGibberish('我想去 Penang 旅行'), false);
  assert.equal(guardConversationInput('Boleh cari tempat makan di Penang?').handled, false);
});

test('handles abuse-only input but preserves a travel request containing profanity', () => {
  assert.equal(isAbuseOnly('you are stupid'), true);
  assert.equal(isAbuseOnly('find me a fucking hotel in Penang'), false);
});
