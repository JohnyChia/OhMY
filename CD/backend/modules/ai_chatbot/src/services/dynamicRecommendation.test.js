const test = require('node:test');
const assert = require('node:assert/strict');
const { getRecommendations } = require('./recommendationService');
const { validateClassification } = require('./semanticClassifierService');

for (const [requirement, query, name, types] of [
  ['Arabian cuisine', 'Arabian restaurant', 'Arabian Kitchen', ['restaurant']],
  ['pottery classes', 'pottery classes', 'Pottery Classes Studio', ['point_of_interest']],
]) {
  test(`unknown request searches dynamically: ${requirement}`, async () => {
    const calls = [];
    const result = await getRecommendations({
      destination: 'your current location', latitude: 3.2, longitude: 101.72,
      requirements: [requirement], searchQuery: query,
      profile: { favorite_categories: ['Heritage'] },
    }, { fetch: async (url, options) => {
      calls.push(url);
      assert.match(url, /\/api\/places\/search$/);
      assert.equal(JSON.parse(options.body).query, query);
      return { ok: true, json: async () => ({ places: [
        { id: 'match', displayName: { text: name }, types,
          location: { latitude: 3.201, longitude: 101.721 } },
        { id: 'museum', displayName: { text: 'Heritage Museum' }, types: ['museum'],
          location: { latitude: 3.201, longitude: 101.721 } },
      ] }) };
    } });
    assert.deepEqual(result.recommendations.map(place => place.id), ['match']);
    assert.equal(calls.length, 1);
    assert.deepEqual(result.applied_preferences, []);
  });
}

test('no explicit matches never substitutes cultural preferences', async () => {
  const result = await getRecommendations({ destination: 'Setapak', latitude: 3.2,
    longitude: 101.72, requirements: ['Arabian cuisine'],
    profile: { favorite_categories: ['Heritage'] },
  }, { fetch: async url => {
    assert.match(url, /\/api\/places\/search$/);
    return { ok: true, json: async () => ({ places: [] }) };
  } });
  assert.deepEqual(result.recommendations, []);
});

test('semantic extraction keeps an unfamiliar provider query and exclusions', () => {
  const result = validateClassification({ intent: 'recommendation',
    language: { primary: 'ms', mixed: true, style: 'rojak' },
    location: { name: '', country: '' }, domain: 'malaysia_travel', confidence: 0.9,
    parameters: { requirements: ['Arabian cuisine'], search_query: 'Arabian restaurant',
      excluded_requirements: ['buffet'] }, draft_response: '',
  });
  assert.equal(result.parameters.search_query, 'Arabian restaurant');
  assert.deepEqual(result.parameters.excluded_requirements, ['buffet']);
});
