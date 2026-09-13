const test = require('node:test');
const assert = require('node:assert/strict');

const {
  compactTaggedPlace,
  getRecommendations,
  selectPreferences,
} = require('./recommendationService');

test('each recommendation carries its own matching chips into the map carousel', () => {
  const first = compactTaggedPlace({
    place: { id: 'one', displayName: { text: 'First' } },
    matchedPreferences: ['Restaurant', 'Cultural Experience'],
    analysis: { generalTags: [], culturalTags: [] },
    ranking: { matchingTags: ['Restaurant'] },
  });
  const second = compactTaggedPlace({
    place: { id: 'two', displayName: { text: 'Second' } },
    matchedPreferences: ['Nature', 'Park'],
    analysis: { generalTags: ['Park'], culturalTags: [] },
    ranking: { matchingTags: ['Nature'] },
  });

  assert.deepEqual(first.analysis.generalTags, ['Restaurant', 'Cultural Experience']);
  assert.deepEqual(second.analysis.generalTags, ['Park', 'Nature']);
  assert.notStrictEqual(first.analysis.generalTags, second.analysis.generalTags);
});

test('current request preferences override saved profile tags', () => {
  assert.deepEqual(selectPreferences({
    requirements: ['makanan'],
    profile: { favorite_categories: ['Heritage'] },
  }), {
    values: ['makanan'],
    source: 'current_request',
  });
});

test('saved Supabase profile tags are used when current request has no requirements', () => {
  assert.deepEqual(selectPreferences({
    requirements: [],
    profile: { favorite_categories: ['Local Cuisine', 'Heritage'] },
  }), {
    values: ['Local Cuisine', 'Heritage'],
    source: 'traveler_profile',
  });
});

test('recommendations preserve provider names and return no fabricated rating', async () => {
  let query;
  const result = await getRecommendations({
    destination: 'Melaka',
    requirements: ['makanan'],
    profile: { favorite_categories: ['Heritage'] },
  }, {
    searchPlaces: async (value) => {
      query = value;
      return {
        places: [{
          id: 'provider-id',
          displayName: { text: 'Provider Canonical Name' },
          formattedAddress: 'Melaka, Malaysia',
          types: ['restaurant'],
        }],
      };
    },
  });

  assert.match(query, /makanan/i);
  assert.match(query, /Melaka/);
  assert.equal(result.preference_source, 'current_request');
  assert.equal(result.recommendations[0].name, 'Provider Canonical Name');
  assert.equal(result.recommendations[0].rating, null);
});
