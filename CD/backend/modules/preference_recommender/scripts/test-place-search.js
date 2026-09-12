const assert = require('node:assert/strict');
const { searchPlacesAndAttractions } = require('../googlePlacesService');

const originalFetch = global.fetch;
const originalKey = process.env.GOOGLE_PLACES_API_KEY;
process.env.GOOGLE_PLACES_API_KEY = 'test-key';
global.fetch = async (_url, options) => {
    const body = JSON.parse(options.body);
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
    console.log('Area and destination search contract checks passed.');
})().catch(error => {
    console.error(error.message);
    process.exitCode = 1;
}).finally(() => {
    global.fetch = originalFetch;
    if (originalKey === undefined) delete process.env.GOOGLE_PLACES_API_KEY;
    else process.env.GOOGLE_PLACES_API_KEY = originalKey;
});
