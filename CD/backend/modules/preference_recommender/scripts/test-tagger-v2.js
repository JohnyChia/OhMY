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
    types: ["history_museum"],
    reviews: [],
    editorialSummary: null
}, tagger, GENERAL_TAGS);
assert.ok(metadataOnly.generalTags.includes("Museum"));
assert.ok(metadataOnly.culturalTags.includes("Heritage"));
assert.equal(metadataOnly.statistics.Museum.source, "google_place_type");

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
