const test = require("node:test");
const assert = require("node:assert/strict");

process.env.GOOGLE_PLACES_API_KEY = "test-key";

const { lookupArea } = require("./weather-service");

test("reverse geocoding selects a general urban area instead of a neighborhood", async () => {
    const originalFetch = global.fetch;
    global.fetch = async () => ({
        ok: true,
        json: async () => ({
            status: "OK",
            results: [{
                formatted_address: "A precise residential address",
                address_components: [
                    { long_name: "Precise Housing Block", types: ["neighborhood"] },
                    { long_name: "Setia Alam", types: ["sublocality_level_1"] },
                    { long_name: "Shah Alam", types: ["locality"] }
                ]
            }]
        })
    });

    try {
        assert.equal(await lookupArea(3.1, 101.5), "Setia Alam");
    } finally {
        global.fetch = originalFetch;
    }
});

test("reverse geocoding does not expose a precise address as an area", async () => {
    const originalFetch = global.fetch;
    global.fetch = async () => ({
        ok: true,
        json: async () => ({
            status: "OK",
            results: [{
                formatted_address: "12 Example Road, Malaysia",
                address_components: [
                    { long_name: "Example Estate", types: ["neighborhood"] }
                ]
            }]
        })
    });

    try {
        assert.equal(await lookupArea(3.1, 101.5), null);
    } finally {
        global.fetch = originalFetch;
    }
});
