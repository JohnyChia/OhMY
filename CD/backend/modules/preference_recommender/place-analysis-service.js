const TYPE_TAGS = {
    restaurant: ["Restaurant"],
    cafe: ["Cafe"],
    coffee_shop: ["Cafe"],
    museum: ["Museum", "Cultural Learning"],
    history_museum: ["Museum", "Cultural Learning", "Heritage"],
    art_museum: ["Museum"],
    market: ["Market"],
    shopping_mall: ["Shopping"],
    park: ["Park"],
    botanical_garden: ["Park", "Nature"],
    national_park: ["Nature"],
    wildlife_park: ["Nature"],
    historical_place: ["Heritage", "Historical Landmark"],
    historical_landmark: ["Heritage", "Historical Landmark"],
    cultural_landmark: ["Heritage", "Cultural Experience"],
    monument: ["Heritage", "Historical Landmark"],
    cultural_center: ["Cultural Experience", "Cultural Learning"],
    hindu_temple: ["Religious Heritage"],
    mosque: ["Religious Heritage"],
    church: ["Religious Heritage"],
    buddhist_temple: ["Religious Heritage"]
};

const { normalizeGoogleReviews } = require("./review-normalizer");

function mergeEvidence(reviewAnalysis, metadataEntries) {
    const generalSet = new Set(reviewAnalysis.generalTags || []);
    const culturalSet = new Set(reviewAnalysis.culturalTags || []);
    const statistics = { ...(reviewAnalysis.statistics || {}) };

    for (const entry of metadataEntries) {
        const existing = statistics[entry.tag];
        if (existing?.assigned) {
            existing.source = existing.source === entry.source
                ? existing.source
                : "hybrid";
            existing.supportPercentage = Number(
                (1 - (1 - existing.supportPercentage) * (1 - entry.confidence))
                    .toFixed(3)
            );
            existing.metadataConfidence = Math.max(
                existing.metadataConfidence || 0,
                entry.confidence
            );
        } else {
            statistics[entry.tag] = {
                assigned: true,
                supportingReviews: 0,
                supportPercentage: entry.confidence,
                averageScore: 0,
                evidenceCount: 1,
                evidenceTypes: { [entry.source]: 1 },
                source: entry.source,
                metadataConfidence: entry.confidence
            };
        }
        if (entry.group === "general") generalSet.add(entry.tag);
        else culturalSet.add(entry.tag);
    }

    return {
        ...reviewAnalysis,
        generalTags: [...generalSet],
        culturalTags: [...culturalSet],
        statistics
    };
}

function metadataEntries(place, tagger, generalTags) {
    const entries = new Map();
    const add = (tag, confidence, source) => {
        const current = entries.get(tag);
        if (!current || confidence > current.confidence) {
            entries.set(tag, {
                tag,
                confidence,
                source,
                group: generalTags.includes(tag) ? "general" : "cultural"
            });
        }
    };

    for (const type of place.types || []) {
        for (const tag of TYPE_TAGS[type] || []) add(tag, 0.6, "google_place_type");
    }

    const summary = String(place.editorialSummary?.text || "").trim();
    if (summary) {
        const summaryAnalysis = tagger.aggregatePlace([{
            text: summary,
            weight: 0.8,
            languageCode: place.editorialSummary?.languageCode || "en"
        }]);
        for (const tag of [
            ...summaryAnalysis.generalTags,
            ...summaryAnalysis.culturalTags
        ]) {
            add(tag, 0.8, "editorial_summary");
        }
    }
    return [...entries.values()];
}

function analyzePlace(place, tagger, generalTags) {
    const normalized = normalizeGoogleReviews(place.reviews || []);
    const reviewAnalysis = tagger.aggregatePlace(normalized.reviews);
    const analysis = mergeEvidence(
        reviewAnalysis,
        metadataEntries(place, tagger, generalTags)
    );
    return {
        ...analysis,
        languageSummary: normalized.languageSummary,
        evidenceSummary: {
            reviewTagCount:
                (reviewAnalysis.generalTags?.length || 0)
                + (reviewAnalysis.culturalTags?.length || 0),
            metadataTagCount: Object.values(analysis.statistics)
                .filter(stat => [
                    "google_place_type",
                    "editorial_summary",
                    "hybrid"
                ].includes(stat.source)).length
        }
    };
}

module.exports = { TYPE_TAGS, metadataEntries, mergeEvidence, analyzePlace };
