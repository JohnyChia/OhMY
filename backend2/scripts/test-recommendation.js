const assert = require("node:assert/strict");
const {
    buildNearbySearchPlan
} = require("../candidate-query-planner");
const {
    calculateRecommendationScore,
    rankTaggedPlaces
} = require("../ranking-service");

const preferencePlan = buildNearbySearchPlan({
    generalTags: ["Museum"],
    culturalTags: ["Heritage", "Cultural Learning"],
    maximumSearchTypes: 6
});

const preferenceTypes =
    preferencePlan.map(item => item.type);

const expandedPreferencePlan = buildNearbySearchPlan({
    generalTags: ["Museum", "Nature"],
    culturalTags: [
        "Heritage",
        "Cultural Learning",
        "Religious Heritage"
    ],
    maximumSearchTypes: 6
});

const expandedPreferenceTypes =
    expandedPreferencePlan.map(item => item.type);

assert.ok(
    expandedPreferenceTypes.some(
        type => [
            "national_park",
            "park",
            "wildlife_park"
        ].includes(type)
    ),
    "Nature preferences should retrieve natural attractions."
);

assert.ok(
    expandedPreferenceTypes.some(
        type => [
            "hindu_temple",
            "mosque",
            "church",
            "buddhist_temple"
        ].includes(type)
    ),
    "Religious Heritage should retrieve places of worship."
);

assert.ok(
    preferenceTypes.includes("museum"),
    "Museum preferences should retrieve museums."
);
assert.ok(
    preferenceTypes.some(
        type => [
            "historical_place",
            "historical_landmark",
            "cultural_landmark"
        ].includes(type)
    ),
    "Heritage preferences should retrieve heritage candidates."
);
assert.ok(
    preferencePlan.every(
        item => item.reasons.length > 0
    ),
    "Every search type should explain why it was selected."
);

const destinationPlan = buildNearbySearchPlan({
    generalTags: ["Landmark"],
    culturalTags: [
        "Religious Heritage",
        "Cultural Festival"
    ],
    maximumSearchTypes: 6
});

assert.ok(
    destinationPlan.some(
        item => item.type === "hindu_temple"
    ),
    "Religious destination tags should broaden discovery to temples."
);

const fullCulturalMatch =
    calculateRecommendationScore({
        referenceGeneralTags: ["Museum"],
        referenceCulturalTags: [
            "Heritage",
            "Cultural Learning"
        ],
        candidateGeneralTags: ["Museum"],
        candidateCulturalTags: [
            "Heritage",
            "Cultural Learning"
        ],
        statistics: {
            Museum: { supportPercentage: 0.8 },
            Heritage: { supportPercentage: 0.6 },
            "Cultural Learning": {
                supportPercentage: 0.8
            }
        }
    });

const generalOnlyMatch =
    calculateRecommendationScore({
        referenceGeneralTags: ["Museum"],
        referenceCulturalTags: [
            "Heritage",
            "Cultural Learning"
        ],
        candidateGeneralTags: ["Museum"],
        candidateCulturalTags: [],
        statistics: {
            Museum: { supportPercentage: 1 }
        }
    });

assert.ok(
    fullCulturalMatch.finalScore
        > generalOnlyMatch.finalScore,
    "Cultural coverage should meaningfully improve ranking."
);

const ranked = rankTaggedPlaces([
    {
        place: { distanceMetres: 100 },
        ranking: generalOnlyMatch
    },
    {
        place: { distanceMetres: 500 },
        ranking: fullCulturalMatch
    }
]);

assert.equal(
    ranked[0].ranking.finalScore,
    fullCulturalMatch.finalScore,
    "Similarity should rank before distance."
);
assert.deepEqual(
    ranked.map(item => item.rank),
    [1, 2]
);

console.log("Recommendation planner and ranking checks passed.");
console.log(
    "Preference search plan:",
    preferencePlan.map(item => item.type).join(", ")
);
console.log(
    "Destination search plan:",
    destinationPlan.map(item => item.type).join(", ")
);
console.log(
    "Expanded preference search plan:",
    expandedPreferenceTypes.join(", ")
);
console.log(
    "Full match score:",
    fullCulturalMatch.similarityPercentage
);
console.log(
    "General-only score:",
    generalOnlyMatch.similarityPercentage
);
