const assert = require('node:assert/strict');
const { searchPlacesAndAttractions } = require('../googlePlacesService');

const originalFetch = global.fetch;
const originalKey = process.env.GOOGLE_PLACES_API_KEY;
process.env.GOOGLE_PLACES_API_KEY = 'test-key';
const requestBodies = [];
global.fetch = async (_url, options) => {
    const body = JSON.parse(options.body);
    requestBodies.push(body);
    assert.ok(
        !options.headers['X-Goog-FieldMask'].split(',').includes('routingSummaries')
            || body.routingParameters?.origin,
        'Text search must not request routing summaries without an origin'
    );
    return {
        ok: true,
        json: async () => ({ places: [{
            id: 'place-my',
            displayName: { text: body.textQuery },
            addressComponents: [{ types: ['country'], shortText: 'MY' }],
            location: { latitude: 3.1, longitude: 101.4 }
        }] })
    };
};

(async () => {
    for (const query of ['Setia Alam', 'Sunsuria Forum']) {
        const result = await searchPlacesAndAttractions(query);
        assert.ok(result.places.length > 0, `${query} must return selectable results`);
    }
    await searchPlacesAndAttractions('museum', {
        latitude: 3.1,
        longitude: 101.5,
        radius: 10_000
    });
    const anchoredRequests = requestBodies.slice(-2);
    assert.ok(
        anchoredRequests.every(request =>
            request.locationBias?.circle?.center?.latitude === 3.1
            && request.locationBias?.circle?.center?.longitude === 101.5
            && request.locationBias?.circle?.radius === 10_000
        ),
        'Custom place search must be biased around the itinerary anchor'
    );
    console.log('Area and destination search contract checks passed.');
})().catch(error => {
    console.error(error.message);
    process.exitCode = 1;
}).finally(() => {
    global.fetch = originalFetch;
    if (originalKey === undefined) delete process.env.GOOGLE_PLACES_API_KEY;
    else process.env.GOOGLE_PLACES_API_KEY = originalKey;
});
