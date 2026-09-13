const test = require('node:test');
const assert = require('node:assert/strict');
const { buildContext } = require('./contextBuilder');

test('passes a valid device location into Nova session context', () => {
  const context = buildContext({
    userMessage: 'Bukit Raja',
    currentLocation: {
      latitude: 3.1005,
      longitude: 101.4447,
      accuracy: 8,
      captured_at: '2026-09-13T15:00:00.000Z',
    },
  });

  assert.deepEqual(context.session_context.device_location, {
    latitude: 3.1005,
    longitude: 101.4447,
    accuracy: 8,
    captured_at: '2026-09-13T15:00:00.000Z',
  });
});

test('drops invalid device coordinates', () => {
  const context = buildContext({
    userMessage: 'Bukit Raja',
    currentLocation: { latitude: 'unknown', longitude: 101.4447 },
  });
  assert.equal(context.session_context.device_location, null);
});
