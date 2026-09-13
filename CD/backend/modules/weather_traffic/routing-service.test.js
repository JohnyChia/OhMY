const test = require("node:test");
const assert = require("node:assert/strict");

const {
    computeDrivingRoutes,
    routeIsContinuousDriving,
    stepRequiresNonDrivingTravel
} = require("./routing-service");

test("accepts an entirely local driving route", () => {
    const route = {
        legs: [{
            steps: [
                { travelMode: "DRIVE", navigationInstruction: { maneuver: "TURN_LEFT" } },
                { travelMode: "DRIVE", navigationInstruction: { maneuver: "STRAIGHT" } }
            ]
        }]
    };

    assert.equal(routeIsContinuousDriving(route), true);
});

test("rejects a route containing a ferry or non-driving step", () => {
    const ferry = {
        travelMode: "DRIVE",
        navigationInstruction: {
            maneuver: "FERRY",
            instructions: "Take the vehicle ferry"
        }
    };
    const transit = {
        travelMode: "TRANSIT",
        navigationInstruction: { maneuver: "STRAIGHT" }
    };

    assert.equal(stepRequiresNonDrivingTravel(ferry), true);
    assert.equal(stepRequiresNonDrivingTravel(transit), true);
    assert.equal(routeIsContinuousDriving({ legs: [{ steps: [ferry] }] }), false);
});

test("rejects an empty route instead of assuming continuous road access", () => {
    assert.equal(routeIsContinuousDriving({ legs: [] }), false);
});

test("requests ferry avoidance and returns only continuous driving routes", async () => {
    const originalFetch = global.fetch;
    const originalKey = process.env.GOOGLE_ROUTES_API_KEY;
    let requestBody;
    process.env.GOOGLE_ROUTES_API_KEY = "test-key";
    global.fetch = async (_url, options) => {
        requestBody = JSON.parse(options.body);
        return {
            ok: true,
            json: async () => ({
                routes: [{
                    duration: "600s",
                    staticDuration: "540s",
                    distanceMeters: 5000,
                    routeToken: "local-route",
                    polyline: { encodedPolyline: "abc" },
                    legs: [{
                        steps: [{
                            travelMode: "DRIVE",
                            distanceMeters: 5000,
                            startLocation: { latLng: { latitude: 3.1, longitude: 101.7 } },
                            endLocation: { latLng: { latitude: 3.2, longitude: 101.8 } }
                        }]
                    }]
                }]
            })
        };
    };

    try {
        const result = await computeDrivingRoutes({
            startLat: 3.1,
            startLon: 101.7,
            endLat: 3.2,
            endLon: 101.8
        });
        assert.equal(requestBody.routeModifiers.avoidFerries, true);
        assert.equal(result.routes.length, 1);
        assert.equal(result.routes[0].steps[0].travelMode, "DRIVE");
    } finally {
        global.fetch = originalFetch;
        if (originalKey === undefined) delete process.env.GOOGLE_ROUTES_API_KEY;
        else process.env.GOOGLE_ROUTES_API_KEY = originalKey;
    }
});
