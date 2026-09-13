const test = require('node:test');
const assert = require('node:assert/strict');

const { parseResetDurationSeconds } = require('./chatController');

test('parses provider token reset durations instead of guessing one minute', () => {
  assert.equal(parseResetDurationSeconds('7m40.68s'), 461);
  assert.equal(parseResetDurationSeconds('1h2m3s'), 3723);
  assert.equal(parseResetDurationSeconds('850ms'), 1);
  assert.equal(parseResetDurationSeconds('45'), 45);
});

