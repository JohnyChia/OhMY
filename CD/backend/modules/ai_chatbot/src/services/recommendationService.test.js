const test = require('node:test');
const assert = require('node:assert/strict');

const {
  getRecommendations,
  selectPreferences,
  packageRecommendationRequest,
} = require('./recommendationService');

test('saved profile tags remain authoritative over free-form request wording', () => {
  assert.deepEqual(selectPreferences({
    requirements: ['makanan'],
    profile: { favorite_categories: ['Heritage'] },
  }), {
    values: ['Heritage'],
    source: 'traveler_profile',
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
  let requestBody;
  const result = await getRecommendations({
    destination: 'Melaka',
    latitude: 2.1896,
    longitude: 102.2501,
    requirements: [],
    profile: { favorite_categories: ['Heritage'] },
  }, {
    fetch: async (_url, options) => {
      requestBody = JSON.parse(options.body);
      return {
        ok: true,
        json: async () => ({
          ranked: true,
          taggerVersion: 'test-tagger',
          radiusMetres: 10000,
          matchedPlaces: [{
            place: {
              id: 'provider-id',
              displayName: { text: 'Provider Canonical Name' },
              formattedAddress: 'Melaka, Malaysia',
              types: ['restaurant'],
              distanceKm: 1.2,
            },
            matchedPreferences: ['makanan'],
            ranking: { score: 3 },
          }],
        }),
      };
    },
  });

  assert.deepEqual(requestBody.preferences, ['Heritage']);
  assert.equal(requestBody.mode, 'preferences');
  assert.equal(requestBody.latitude, 2.1896);
  assert.equal(result.preference_source, 'traveler_profile');
  assert.deepEqual(result.request_requirements, []);
  assert.equal(result.provider, 'preference_recommender');
  assert.equal(result.ranked, true);
  assert.equal(result.recommendations[0].name, 'Provider Canonical Name');
  assert.equal(result.recommendations[0].rating, null);
});

test('packages cuisine intent separately from the Nearby For You preferences', () => {
  assert.deepEqual(packageRecommendationRequest({
    latitude: 3.1,
    longitude: 101.44,
    requirements: ['Chinese cuisine'],
    profile: { favorite_categories: ['Cultural Experience'] },
  }), {
    nearbyForYou: {
      latitude: 3.1,
      longitude: 101.44,
      mode: 'preferences',
      preferences: ['Cultural Experience'],
    },
    explicit: ['Chinese cuisine'],
    explicitQuery: 'Chinese restaurant',
    preferenceSource: 'traveler_profile',
  });
});

test('does not bypass the preference engine when a profile has no tags', async () => {
  const result = await getRecommendations({
    destination: 'Melaka',
    latitude: 2.1896,
    longitude: 102.2501,
    profile: {},
  }, {
    fetch: async () => { throw new Error('must not be called'); },
  });

  assert.equal(result.success, false);
  assert.equal(result.code, 'PREFERENCES_REQUIRED');
});

test('uses nearby search directly for explicit cuisine without changing saved preferences', async () => {
  const requests = [];
  const result = await getRecommendations({
    destination: 'Setia Alam',
    latitude: 3.1005,
    longitude: 101.4447,
    requirements: ['Western cuisine'],
    profile: { favorite_categories: ['Local Cuisine'] },
  }, {
    fetch: async (url, options) => {
      requests.push({ url, body: JSON.parse(options.body) });
      if (url.endsWith('/api/recommendations/nearby-tagged')) {
        return {
          ok: true,
          json: async () => ({ ranked: true, matchedPlaces: [{
            place: {
              id: 'temple-id',
              displayName: { text: 'Chinese Temple' },
              types: ['place_of_worship'],
            },
          }] }),
        };
      }
      return {
        ok: true,
        json: async () => ({
          places: [{
            id: 'western-id',
            displayName: { text: 'Nearby Western Restaurant' },
            formattedAddress: 'Setia Alam, Selangor',
            location: { latitude: 3.101, longitude: 101.445 },
            types: ['restaurant'],
          }, {
            id: 'irrelevant-id',
            displayName: { text: 'Malay Food in Pahang' },
            formattedAddress: 'Kuantan, Pahang',
            location: { latitude: 3.8077, longitude: 103.3260 },
            types: ['restaurant'],
          }],
        }),
      };
    },
  });

  assert.equal(requests.length, 1);
  assert.match(requests[0].url, /\/api\/places\/search$/);
  assert.equal(requests[0].body.query, 'Western restaurant');
  assert.equal(requests[0].body.latitude, 3.1005);
  assert.equal(result.success, true);
  assert.equal(result.provider, 'nearby_place_search');
  assert.deepEqual(result.request_tags, ['western_cuisine']);
  assert.deepEqual(result.applied_preferences, []);
  assert.equal(result.recommendations[0].name, 'Nearby Western Restaurant');
  assert.equal(result.recommendations.length, 1);
});

test('finds nearby fast food by provider type rather than literal venue name', async () => {
  const profile = { favorite_categories: ['Heritage'] };
  const result = await getRecommendations({
    destination: 'your current location', latitude: 3.2, longitude: 101.72,
    requirements: ['fast food'], profile,
  }, { fetch: async (url) => {
    assert.match(url, /\/api\/places\/search$/);
    return { ok: true, json: async () => ({ places: [
      { id: 'far', displayName: { text: 'Distant Fast Food' },
        location: { latitude: 3.8, longitude: 103.3 }, types: ['fast_food_restaurant'] },
      { id: 'near', displayName: { text: 'McDonalds Danau Kota DT' },
        location: { latitude: 3.201, longitude: 101.721 }, types: ['fast_food_restaurant'] },
      { id: 'temple', displayName: { text: 'Chinese Temple' },
        location: { latitude: 3.201, longitude: 101.721 }, types: ['place_of_worship'] },
    ] }) };
  } });
  assert.deepEqual(result.recommendations.map(place => place.name), ['McDonalds Danau Kota DT']);
  assert.deepEqual(profile.favorite_categories, ['Heritage']);
});
