const test = require("node:test");
const assert = require("node:assert/strict");

const { isGeographicAreaPlace } = require("./googlePlacesService");

test("recognises administrative map labels as geographic areas", () => {
    for (const type of [
        "country",
        "administrative_area_level_1",
        "administrative_area_level_2",
        "locality",
        "sublocality_level_1",
        "neighborhood"
    ]) {
        assert.equal(isGeographicAreaPlace({ types: [type] }), true, type);
    }
});

test("keeps genuine attractions selectable", () => {
    assert.equal(
        isGeographicAreaPlace({
            primaryType: "tourist_attraction",
            types: ["tourist_attraction", "museum", "point_of_interest"]
        }),
        false
    );
});
