const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { TaggingService } = require("../tagging-service");

const service = new TaggingService();

const fastFoodReviews = [
    "Friendly community and a nice experience. The burger was good.",
    "Quick service, hot fries, clean tables and helpful staff.",
    "Good McDonald food and an affordable family meal.",
    "The restaurant was busy but our order arrived quickly.",
    "Convenient place for burgers, coffee and takeaway food."
];

const museumReviews = [
    "A wonderful museum where visitors learn about Malaysian culture and history.",
    "The exhibits explain local traditions and provide excellent cultural education.",
    "Historical artefacts and preserved displays make this an educational visit.",
    "The traditional architecture and heritage collection are worth exploring.",
    "A meaningful cultural experience with lots of knowledge about Malaysia's past."
];

const duplicateReviews = [
    "Learn about Malaysian culture and history at this museum.",
    "Learn about Malaysian culture and history at this museum.",
    "Nice",
    "Historical exhibits explain local traditions clearly."
];

const fastFood = service.aggregatePlace(fastFoodReviews);
const museum = service.aggregatePlace(museumReviews);
const selected = service.selectRelevantReviews(duplicateReviews);

assert.deepEqual(
    fastFood.culturalTags,
    [],
    "Generic restaurant language must not produce cultural tags."
);

assert.equal(
    fastFood.culturallyRelevantPlace,
    false,
    "One-off generic cultural language must not make a restaurant cultural."
);

assert.ok(
    museum.culturalTags.includes("Cultural Learning"),
    "Repeated, specific cultural-learning evidence should remain sensitive."
);

assert.ok(
    museum.culturalTags.includes("Heritage")
    && museum.culturalTags.includes("Traditional Architecture")
    && museum.culturalTags.includes("Cultural Experience"),
    "A culturally established place should retain specific one-review tags."
);

assert.equal(
    selected.length,
    2,
    "Duplicate and low-information reviews should be excluded."
);

console.log("Tagging quality checks passed.");
console.log("Fast-food cultural tags:", fastFood.culturalTags);
console.log("Museum cultural tags:", museum.culturalTags);
console.log("Relevant reviews selected:", selected.length);

const savedAttractions = JSON.parse(
    fs.readFileSync(
        path.join(__dirname, "..", "attractions.json"),
        "utf8"
    )
).attractions || [];

const savedResults = new Map();

for (const attraction of savedAttractions) {
    const result = service.aggregatePlace(
        attraction.reviews.map(review => review.text)
    );

    savedResults.set(
        attraction.place.displayName.text,
        result
    );

    console.log(
        `${attraction.place.displayName.text}: `
        + `${result.reviewCount}/${result.inputReviewCount} relevant reviews; `
        + `cultural tags: ${result.culturalTags.join(", ") || "none"}`
    );
}

const nationalMuseum =
    savedResults.get("The National Museum of Malaysia");
const batuCaves =
    savedResults.get("Batu Caves");

assert.ok(
    nationalMuseum?.culturallyRelevantPlace
    && nationalMuseum.culturalTags.includes("Cultural Learning"),
    "The National Museum must remain culturally relevant."
);

assert.ok(
    batuCaves?.culturallyRelevantPlace
    && batuCaves.culturalTags.includes("Religious Heritage"),
    "Batu Caves must retain Religious Heritage."
);
