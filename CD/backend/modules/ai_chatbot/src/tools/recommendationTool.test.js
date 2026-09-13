const test = require('node:test');
const assert = require('node:assert/strict');
const recommendationTool = require('./recommendationTool');

test('uses the device location for a recommendation without an area name', async () => {
  let received;
  const result = await recommendationTool.get(
    { category: 'Western cuisine', destination: 'Pahang' },
    { favorite_categories: ['Local Cuisine'] },
    {
      current_message: 'Western cuisine near me',
      session_context: {
        location: { destination: 'Pahang' },
        device_location: { latitude: 3.1005, longitude: 101.4447 },
      },
    },
    {
      recommendationService: {
        async getRecommendations(options) {
          received = options;
          return { success: true, recommendations: [] };
        },
      },
    },
  );

  assert.equal(result.success, true);
  assert.equal(received.destination, 'your current location');
  assert.equal(received.latitude, 3.1005);
  assert.equal(received.longitude, 101.4447);
  assert.deepEqual(received.requirements, ['Western restaurant', 'Western cuisine']);
});

test('extracts fast food from the current message even when the model omits it', async () => {
  let received;
  await recommendationTool.get({}, { favorite_categories: ['Heritage'] }, {
    current_message: 'fast food near me',
    session_context: { device_location: { latitude: 3.2, longitude: 101.72 } },
  }, { recommendationService: { async getRecommendations(options) {
    received = options;
    return { success: true, recommendations: [] };
  } } });
  assert.deepEqual(received.requirements, ['fast food restaurant']);
  assert.equal(received.destination, 'your current location');
});
