function coverage(referenceTags, candidateTags) {
    if (referenceTags.length === 0) {
        return {
            score: 0,
            matches: []
        };
    }

    const candidateSet = new Set(candidateTags);
    const matches = referenceTags.filter(
        tag => candidateSet.has(tag)
    );

    return {
        score: matches.length / referenceTags.length,
        matches
    };
}


function calculateRecommendationScore({
    referenceGeneralTags = [],
    referenceCulturalTags = [],
    candidateGeneralTags = [],
    candidateCulturalTags = [],
    statistics = {}
}) {
    const general = coverage(
        referenceGeneralTags,
        candidateGeneralTags
    );
    const cultural = coverage(
        referenceCulturalTags,
        candidateCulturalTags
    );

    let generalWeight = 0;
    let culturalWeight = 0;

    if (
        referenceGeneralTags.length > 0
        && referenceCulturalTags.length > 0
    ) {
        generalWeight = 0.4;
        culturalWeight = 0.6;
    } else if (referenceGeneralTags.length > 0) {
        generalWeight = 1;
    } else if (referenceCulturalTags.length > 0) {
        culturalWeight = 1;
    }

    const baseSimilarity =
        general.score * generalWeight
        + cultural.score * culturalWeight;

    const matchingTags = [
        ...general.matches,
        ...cultural.matches
    ];

    const confidenceValues = matchingTags
        .map(tag => statistics[tag]?.supportPercentage)
        .filter(Number.isFinite);

    const matchConfidence =
        confidenceValues.length > 0
            ? confidenceValues.reduce(
                (total, value) => total + value,
                0
            ) / confidenceValues.length
            : 0;

    const culturalRelevance = referenceCulturalTags.length > 0
        ? cultural.score
        : 0;

    // Tagger V2 intentionally has no proximity component. Distance remains
    // only a deterministic final tie-breaker in rankTaggedPlaces().
    const scoreBreakdown = {
        tagCoverage: Number((baseSimilarity * 0.80).toFixed(4)),
        evidenceConfidence: Number((matchConfidence * 0.15).toFixed(4)),
        culturalRelevance: Number((culturalRelevance * 0.05).toFixed(4))
    };

    const finalScore = Math.min(
        1,
        scoreBreakdown.tagCoverage
            + scoreBreakdown.evidenceConfidence
            + scoreBreakdown.culturalRelevance
    );

    return {
        finalScore: Number(finalScore.toFixed(4)),
        similarityPercentage:
            Number((finalScore * 100).toFixed(1)),
        baseSimilarity:
            Number(baseSimilarity.toFixed(4)),
        generalSimilarity:
            Number(general.score.toFixed(4)),
        culturalSimilarity:
            Number(cultural.score.toFixed(4)),
        generalMatches: general.matches,
        culturalMatches: cultural.matches,
        matchingTags,
        matchConfidence:
            Number(matchConfidence.toFixed(3)),
        culturalRelevance:
            Number(culturalRelevance.toFixed(3)),
        scoreBreakdown,
        weights: {
            general: generalWeight,
            cultural: culturalWeight
        }
    };
}


function rankTaggedPlaces(places) {
    return [...places]
        .sort((a, b) =>
            b.ranking.finalScore
            - a.ranking.finalScore
            || b.ranking.culturalMatches.length
                - a.ranking.culturalMatches.length
            || b.ranking.matchConfidence
                - a.ranking.matchConfidence
            || a.place.distanceMetres
                - b.place.distanceMetres
        )
        .map((place, index) => ({
            ...place,
            rank: index + 1
        }));
}


module.exports = {
    calculateRecommendationScore,
    rankTaggedPlaces
};
