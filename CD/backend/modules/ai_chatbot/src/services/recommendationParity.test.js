const test = require('node:test');
const assert = require('node:assert/strict');
const { classifyRequest } = require('./semanticClassifierService');
const recommendationTool = require('../tools/recommendationTool');
const recommendationService = require('./recommendationService');
const { requestTags } = require('./requestTagService');

test('voice and text synonyms produce identical GPS search and verified cards', async () => {
  const bodies = [];
  const outputs = [];
  for (const [message, mode] of [
    ['Recommend me Chinese restaurants near me.', 'driving_voice'],
    ['recommend me Chinese cuisine near me', 'chat_text'],
    ['Recommend me Chinese cuisine near me.', 'driving_voice'],
  ]) {
    const { classification } = await classifyRequest({ currentMessage: message,
      completion: async () => { throw new Error('must not depend on model'); } });
    assert.equal(classification.toolName, 'recommendation');
    const result = await recommendationTool.get(classification.parameters,
      { favorite_categories: ['Heritage'] }, {
        current_message: message, interaction_mode: mode,
        session_context: { location: { destination: 'Pahang' },
          device_location: { latitude: 3.2, longitude: 101.72 } },
      }, { recommendationService: { getRecommendations: options =>
        recommendationService.getRecommendations(options, { fetch: async (url, request) => {
          assert.match(url, /\/api\/places\/search$/);
          bodies.push(JSON.parse(request.body));
          return { ok: true, json: async () => ({ places: [
            { id: 'food', displayName: { text: 'Verified Chinese Restaurant' },
              location: { latitude: 3.201, longitude: 101.721 }, types: ['chinese_restaurant'] },
            { id: 'heritage', displayName: { text: 'Gedung Raja Abdullah' },
              location: { latitude: 3.201, longitude: 101.721 }, types: ['museum'] },
          ] }) };
        } }) } });
    outputs.push(result.recommendations);
    assert.deepEqual(result.recommendations.map(place => place.id), ['food']);
  }
  assert.deepEqual(bodies[0], bodies[1]);
  assert.deepEqual(bodies[1], bodies[2]);
  assert.deepEqual(outputs[0], outputs[1]);
  assert.deepEqual(outputs[1], outputs[2]);
});

for (const phrase of ['Chinese food', 'Chinese restaurants', 'Chinese cuisine',
  'Chinese dining', 'restoran Cina', 'masakan Cina', '中餐']) {
  test(`canonical Chinese search: ${phrase}`, () => {
    assert.equal(requestTags(phrase)[0].query, 'Chinese restaurant');
  });
}
