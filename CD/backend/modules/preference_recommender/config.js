function positiveInteger(value, fallback) {
    const parsed = Number.parseInt(value, 10);
    return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

const TAGGER_VERSION =
    process.env.TAGGER_VERSION || "rule-nlp-v2-2026-09-12";

const RECOMMENDATION_RESULTS_PER_TYPE = positiveInteger(
    process.env.RECOMMENDATION_RESULTS_PER_TYPE,
    10
);
const RECOMMENDATION_CANDIDATE_LIMIT = positiveInteger(
    process.env.RECOMMENDATION_CANDIDATE_LIMIT,
    40
);
const RECOMMENDATION_DETAILS_CONCURRENCY = positiveInteger(
    process.env.RECOMMENDATION_DETAILS_CONCURRENCY,
    4
);
const RECOMMENDATION_MAXIMUM_SEARCH_TYPES = positiveInteger(
    process.env.RECOMMENDATION_MAXIMUM_SEARCH_TYPES,
    6
);

module.exports = {
    TAGGER_VERSION,
    RECOMMENDATION_RESULTS_PER_TYPE,
    RECOMMENDATION_CANDIDATE_LIMIT,
    RECOMMENDATION_DETAILS_CONCURRENCY,
    RECOMMENDATION_MAXIMUM_SEARCH_TYPES
};
