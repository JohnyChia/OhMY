const test = require('node:test');
const assert = require('node:assert/strict');

const { exactMalaysianCandidate } = require('./geoResolver');

test('uses a unique exact Malaysian provider match without phonetic inference', () => {
  const result = exactMalaysianCandidate([
    { name: 'Dynamic Place', admin1: 'Region', country: 'Malaysia' },
    { name: 'Different Place', admin1: 'Region', country: 'Malaysia' },
  ], 'dynamic place');

  assert.equal(result.name, 'Dynamic Place');
});

test('does not fast-path ambiguous or foreign provider matches', () => {
  assert.equal(exactMalaysianCandidate([
    { name: 'Shared Name', admin1: 'One', country: 'Malaysia' },
    { name: 'Shared Name', admin1: 'Two', country: 'Malaysia' },
  ], 'Shared Name'), null);
  assert.equal(exactMalaysianCandidate([
    { name: 'Foreign Place', admin1: 'Region', country: 'Elsewhere' },
  ], 'Foreign Place'), null);
});
