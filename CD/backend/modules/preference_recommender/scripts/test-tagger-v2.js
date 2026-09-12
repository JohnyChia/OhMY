const assert = require("node:assert/strict");
const { TaggingService, GENERAL_TAGS } = require("../tagging-service");
const { normalizeGoogleReviews } = require("../review-normalizer");
const { analyzePlace } = require("../place-analysis-service");
const {
    buildTagAssignments,
    tagFingerprint
} = require("../place-cache-service");
const { calculateRecommendationScore } = require("../ranking-service");
const { splitSupportedPreferences } = require("../preference-reference");

const tagger = new TaggingService();

const singleStrongReview = tagger.aggregatePlace([
    { text: "This museum preserves Malaysian cultural heritage and explains important local history.", weight: 1 },
    { text: "Clean place with friendly staff and convenient parking.", weight: 1 },
    { text: "Nice facilities and comfortable seating for visitors.", weight: 1 },
    { text: "The staff were helpful and the building was clean.", weight: 1 },
    { text: "Easy parking and good service throughout the visit.", weight: 1 }
]);
assert.ok(
    singleStrongReview.culturalTags.includes("Heritage"),
    "One review passing the NLP and support thresholds must establish a cultural tag."
);

const malay = normalizeGoogleReviews([{
    text: {
        text: "Muzium ini mempunyai warisan budaya dan seni bina tradisional.",
        languageCode: "ms"
    },
    originalText: {
        text: "Muzium ini mempunyai warisan budaya dan seni bina tradisional.",
        languageCode: "ms"
    },
    rating: 5,
    publishTime: new Date().toISOString()
}]);
assert.equal(malay.reviews.length, 1);
assert.match(malay.reviews[0].text, /traditional architecture/);
const malayAnalysis = tagger.aggregatePlace(malay.reviews);
assert.ok(malayAnalysis.generalTags.includes("Museum"));
assert.ok(malayAnalysis.culturalTags.includes("Heritage"));

const unsupported = normalizeGoogleReviews([{
    text: { text: "历史悠久的地方", languageCode: "zh" },
    originalText: { text: "历史悠久的地方", languageCode: "zh" }
}]);
assert.equal(unsupported.reviews.length, 0);
assert.equal(unsupported.languageSummary.unsupported, 1);

const metadataOnly = analyzePlace({
    displayName: { text: "Reviewless History Museum" },
    types: ["history_museum"],
    reviews: [],
    editorialSummary: null
}, tagger, GENERAL_TAGS);
assert.ok(metadataOnly.generalTags.includes("Museum"));
assert.deepEqual(metadataOnly.culturalTags, []);
assert.equal(metadataOnly.statistics.Museum.source, "google_place_type");

for (const displayName of [
    "Kuala Lumpur-Selangor Boundary Stone 8/21",
    "TYD Signature"
]) {
    const categoryOnly = analyzePlace({
        displayName: { text: displayName },
        types: ["cultural_landmark"],
        reviews: [],
        editorialSummary: null
    }, tagger, GENERAL_TAGS);
    assert.deepEqual(categoryOnly.culturalTags, []);
    assert.ok(categoryOnly.validation.rejectedCulturalTags.includes("Heritage"));
}

const residence = analyzePlace({
    displayName: { text: "Cemara Damai Residence" },
    primaryType: "condominium_complex",
    types: ["condominium_complex", "historical_landmark"],
    reviews: [{
        text: {
            text: "This heritage site has traditional architecture and important cultural history for local visitors.",
            languageCode: "en"
        }
    }]
}, tagger, GENERAL_TAGS);
assert.equal(residence.validation.eligible, false);
assert.ok(residence.validation.reasons.includes("residential_place_type"));
assert.deepEqual(residence.generalTags, []);
assert.deepEqual(residence.culturalTags, []);

const textSupportedLandmark = analyzePlace({
    displayName: { text: "Documented Heritage Site" },
    types: ["cultural_landmark"],
    reviews: [{
        text: {
            text: "This protected heritage site preserves an important historic legacy and traditional local culture.",
            languageCode: "en"
        }
    }]
}, tagger, GENERAL_TAGS);
assert.ok(textSupportedLandmark.culturalTags.includes("Heritage"));
assert.equal(textSupportedLandmark.statistics.Heritage.source, "hybrid");

const assignments = buildTagAssignments(metadataOnly, GENERAL_TAGS);
const reversed = [...assignments].reverse();
assert.equal(tagFingerprint(assignments), tagFingerprint(reversed));
assert.equal(
    tagFingerprint(assignments),
    tagFingerprint(assignments.map((tag, index) => index === 0
        ? { ...tag, confidence: tag.confidence + 0.001 }
        : tag))
);
assert.notEqual(
    tagFingerprint(assignments),
    tagFingerprint(assignments.map((tag, index) => index === 0
        ? { ...tag, confidence: tag.confidence + 0.02 }
        : tag))
);

const weightedAnalysis = tagger.aggregatePlace([
    {
        text: "This museum collection has many exhibits and galleries with useful visitor information.",
        weight: 1.2
    },
    {
        text: "The building has convenient parking, clean facilities, friendly staff and comfortable seating.",
        weight: 0.5
    }
]);
assert.equal(weightedAnalysis.statistics.Museum.supportingWeight, 1.2);
assert.equal(weightedAnalysis.statistics.Museum.supportPercentage, 0.706);

const ranking = calculateRecommendationScore({
    referenceGeneralTags: ["Museum"],
    referenceCulturalTags: ["Heritage"],
    candidateGeneralTags: ["Museum"],
    candidateCulturalTags: ["Heritage"],
    statistics: metadataOnly.statistics
});
assert.equal("proximity" in ranking.scoreBreakdown, false);
assert.ok(ranking.finalScore > 0);

assert.deepEqual(
    splitSupportedPreferences(
        [" museum ", "HERITAGE", "Museum", "unknown"],
        ["Museum", "Cafe"],
        ["Heritage", "Traditional Architecture"]
    ),
    {
        generalTags: ["Museum"],
        culturalTags: ["Heritage"]
    }
);

console.log("Tagger V2 multilingual, metadata, preference and fingerprint checks passed.");
