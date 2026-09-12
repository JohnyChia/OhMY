const test = require('node:test');
const assert = require('node:assert/strict');
const { normalizeMalaysiaLocation, requestedLocationLabel } = require('./weatherTool');

test('does not replace destination names in application code', () => {
  assert.equal(normalizeMalaysiaLocation('Subbanjaya'), 'Subbanjaya');
  assert.equal(normalizeMalaysiaLocation('Kuala Lumpur'), 'Kuala Lumpur');
  assert.equal(normalizeMalaysiaLocation('斯拉沃'), '斯拉沃');
});

test('keeps the requested region label instead of replacing it with a provider locality', () => {
  assert.equal(requestedLocationLabel('User requested region', 'Nearby provider city'), 'User requested region');
  assert.equal(requestedLocationLabel('', 'Provider location'), 'Provider location');
});
