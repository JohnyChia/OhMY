function positiveInteger(value, fallback) {
    const parsed = Number.parseInt(value, 10);
    return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

const TAGGER_VERSION =
    process.env.TAGGER_VERSION || "rule-nlp-v4-adaptive-cultural-evidence-2026-09-13";

const RECOMMENDATION_RESULTS_PER_TYPE = positiveInteger(
    process.env.RECOMMENDATION_RESULTS_PER_TYPE,
    15
);
const RECOMMENDATION_CANDIDATE_LIMIT = positiveInteger(
    process.env.RECOMMENDATION_CANDIDATE_LIMIT,
    80
);
const RECOMMENDATION_DISCOVERY_LIMIT = positiveInteger(
    process.env.RECOMMENDATION_DISCOVERY_LIMIT,
    130
);
const RECOMMENDATION_DETAILS_CONCURRENCY = positiveInteger(
    process.env.RECOMMENDATION_DETAILS_CONCURRENCY,
    4
);
const RECOMMENDATION_MAXIMUM_SEARCH_TYPES = positiveInteger(
    process.env.RECOMMENDATION_MAXIMUM_SEARCH_TYPES,
    10
);
const RECOMMENDATION_DISPLAY_LIMIT = positiveInteger(
    process.env.RECOMMENDATION_DISPLAY_LIMIT,
    30
);

module.exports = {
    TAGGER_VERSION,
    RECOMMENDATION_RESULTS_PER_TYPE,
    RECOMMENDATION_CANDIDATE_LIMIT,
    RECOMMENDATION_DISCOVERY_LIMIT,
    RECOMMENDATION_DETAILS_CONCURRENCY,
    RECOMMENDATION_MAXIMUM_SEARCH_TYPES,
    RECOMMENDATION_DISPLAY_LIMIT
};
