const test = require('node:test');
const assert = require('node:assert/strict');

const {
  getRecommendations,
  selectPreferences,
} = require('./recommendationService');

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
