const test = require('node:test');
const assert = require('node:assert/strict');
const { planSoloRequest } = require('./soloRequestPlanner');
const { classifyRequest } = require('./semanticClassifierService');

test('group actions cannot dispatch a solo tool', async () => {
  const result = await classifyRequest({ currentMessage: 'start a group trip to Penang' });
  assert.equal(result.classification.toolName, null);
  assert.match(result.classification.draftResponse, /solo travel only/);
});

test('simple nearby museum request needs no model or historical destination', async () => {
  const result = await classifyRequest({ currentMessage: 'museums near me' });
  assert.equal(result.classification.toolName, 'recommendation');
  assert.deepEqual(result.classification.parameters.requirements, ['museum']);
  assert.equal(result.classification.parameters.destination, undefined);
});

test('specific navigation takes precedence over nearby category search', () => {
  assert.equal(planSoloRequest('go to the museum near me').requirements[0], 'museum');
});

test('requests with extra constraints retain semantic interpretation', () => {
  assert.equal(planSoloRequest('wheelchair accessible museums near me').simpleNearby, false);
});
