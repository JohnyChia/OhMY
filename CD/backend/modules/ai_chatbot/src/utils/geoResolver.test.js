const test = require('node:test');
const assert = require('node:assert/strict');

const {
  exactMalaysianCandidate,
  expandKnownPlaceAlias,
  mapGooglePlaceCandidate,
  destinationKind,
  sensibleNearbyCandidate,
} = require('./geoResolver');

test('expands common Malaysian place shorthand without an LLM call', () => {
  assert.equal(expandKnownPlaceAlias('png'), 'Penang');
  assert.equal(expandKnownPlaceAlias('KL'), 'Kuala Lumpur');
  assert.equal(expandKnownPlaceAlias('Setia Alam'), 'Setia Alam');
});

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

test('maps a specific Malaysian venue from the shared map backend', () => {
  const result = mapGooglePlaceCandidate({
    id: 'setapak-central-id',
    displayName: { text: 'Setapak Central' },
    location: { latitude: 3.199, longitude: 101.72 },
    primaryType: 'shopping_mall',
    addressComponents: [
      { longText: 'Kuala Lumpur', shortText: 'Kuala Lumpur', types: ['administrative_area_level_1'] },
      { longText: 'Malaysia', shortText: 'MY', types: ['country'] },
    ],
  }, 'Setapak Central');

  assert.equal(result.name, 'Setapak Central');
  assert.equal(result.country, 'Malaysia');
  assert.equal(result.place_id, 'setapak-central-id');
  assert.equal(destinationKind(result), 'place');
});

test('distinguishes broad areas from specific places', () => {
  assert.equal(destinationKind({ feature_code: 'administrative_area_level_1' }), 'area');
  assert.equal(destinationKind({ feature_code: 'PPLA' }), 'area');
  assert.equal(destinationKind({ feature_code: 'shopping_mall' }), 'place');
});

test('prefers a sensible nearby expanded name over a distant exact name', () => {
  const selected = sensibleNearbyCandidate([
    {
      name: 'Bukit Raja',
      country: 'Malaysia',
      latitude: 5.42,
      longitude: 103.09,
      source: 'nominatim',
    },
    {
      name: 'Bandar Bukit Raja',
      country: 'Malaysia',
      latitude: 3.0874,
      longitude: 101.4333,
      source: 'ohmy-map-backend',
    },
  ], 'Bukit Raja', {
    session_context: {
      device_location: { latitude: 3.1005, longitude: 101.4447 },
    },
  });

  assert.equal(selected.name, 'Bandar Bukit Raja');
});
