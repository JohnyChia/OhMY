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

const RESIDENTIAL_PLACE_TYPES = new Set([
    "apartment_building",
    "apartment_complex",
    "condominium_complex",
    "housing_complex",
    "housing_development",
    "private_guest_room",
    "residential_building"
]);

const TOURISM_PROTECTIVE_TYPES = new Set([
    "art_gallery",
    "art_museum",
    "botanical_garden",
    "cultural_center",
    "historical_place",
    "history_museum",
    "museum",
    "national_park",
    "park",
    "performing_arts_theater",
    "tourist_attraction",
    "visitor_center",
    "wildlife_park"
]);

const RESIDENTIAL_NAME_PATTERN =
    /\b(apartments?|condominiums?|condos?|pangsapuri|private\s+(?:property|residence)|residences?|residency|residential|serviced\s+(?:apartment|residence)s?)\b/i;

const { normalizeGoogleReviews } = require("./review-normalizer");

function mergeEvidence(reviewAnalysis, metadataEntries) {
    const generalSet = new Set(reviewAnalysis.generalTags || []);
    const culturalSet = new Set(reviewAnalysis.culturalTags || []);
    const statistics = { ...(reviewAnalysis.statistics || {}) };

    for (const entry of metadataEntries) {
        const existing = statistics[entry.tag];
        if (
            entry.group === "cultural"
            && entry.source === "google_place_type"
            && !existing?.assigned
        ) {
            // Google categories are discovery/supporting metadata, never
            // sufficient evidence for cultural significance on their own.
            continue;
        }
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
            existing.evidenceCount = Number(existing.evidenceCount || 0) + 1;
            existing.evidenceTypes = {
                ...(existing.evidenceTypes || {}),
                [entry.source]:
                    Number(existing.evidenceTypes?.[entry.source] || 0) + 1
            };
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
        const key = `${tag}:${source}`;
        const current = entries.get(key);
        if (!current || confidence > current.confidence) {
            entries.set(key, {
                tag,
                confidence,
                source,
                group: generalTags.includes(tag) ? "general" : "cultural"
            });
        }
    };

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
            if (
                !generalTags.includes(tag)
                && !hasMeaningfulCulturalTextEvidence(
                    summaryAnalysis.statistics[tag]
                )
            ) {
                continue;
            }
            add(tag, 0.8, "editorial_summary");
        }
    }

    // Process Google types after textual metadata so a matching category can
    // strengthen existing evidence, but cannot originate a cultural tag.
    for (const type of place.types || []) {
        for (const tag of TYPE_TAGS[type] || []) add(tag, 0.6, "google_place_type");
    }
    return [...entries.values()];
}

function hasMeaningfulCulturalTextEvidence(statistic) {
    if (!statistic?.assigned) return false;
    if (Number(statistic.supportingReviews || 0) >= 2) return true;
    const evidence = statistic.evidenceTypes || {};
    return ["strong", "medium", "synonym", "ngram"].some(
        type => Number(evidence[type] || 0) > 0
    );
}

function removeInsufficientCulturalTags(analysis, generalTags) {
    const rejected = [];
    const culturalTags = (analysis.culturalTags || []).filter(tag => {
        const sufficient = hasMeaningfulCulturalTextEvidence(
            analysis.statistics?.[tag]
        );
        if (!sufficient) {
            rejected.push(tag);
            if (analysis.statistics?.[tag]) {
                analysis.statistics[tag].assigned = false;
            }
        }
        return sufficient;
    });
    return {
        ...analysis,
        generalTags: (analysis.generalTags || []).filter(
            tag => generalTags.includes(tag)
        ),
        culturalTags,
        rejected
    };
}

function validatePlaceCandidate(place) {
    const placeTypes = new Set([
        place.primaryType,
        ...(place.types || [])
    ].filter(Boolean));
    const displayName = String(
        place.displayName?.text || place.displayName || ""
    ).trim();
    const reasons = [];

    if ([...placeTypes].some(type => RESIDENTIAL_PLACE_TYPES.has(type))) {
        reasons.push("residential_place_type");
    }
    if (
        RESIDENTIAL_NAME_PATTERN.test(displayName)
        && ![...placeTypes].some(type => TOURISM_PROTECTIVE_TYPES.has(type))
    ) {
        reasons.push("residential_place_name");
    }

    return {
        eligible: reasons.length === 0,
        reasons,
        displayName,
        placeTypes: [...placeTypes]
    };
}

function analyzePlace(place, tagger, generalTags) {
    const normalized = normalizeGoogleReviews(place.reviews || []);
    const validation = validatePlaceCandidate(place);
    if (!validation.eligible) {
        const emptyAnalysis = tagger.aggregatePlace([]);
        return {
            ...emptyAnalysis,
            inputReviewCount: (place.reviews || []).length,
            languageSummary: normalized.languageSummary,
            evidenceSummary: {
                reviewTagCount: 0,
                metadataTagCount: 0,
                excluded: true
            },
            validation: {
                ...validation,
                rejectedCulturalTags: []
            }
        };
    }
    const reviewAnalysis = removeInsufficientCulturalTags(
        tagger.aggregatePlace(normalized.reviews),
        generalTags
    );
    const entries = metadataEntries(place, tagger, generalTags);
    const analysis = mergeEvidence(
        reviewAnalysis,
        entries
    );
    const unsupportedCategoryTags = entries
        .filter(entry =>
            entry.group === "cultural"
            && entry.source === "google_place_type"
            && !analysis.culturalTags.includes(entry.tag)
        )
        .map(entry => entry.tag);
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
                ].includes(stat.source)).length,
            excluded: false
        },
        validation: {
            ...validation,
            rejectedCulturalTags: [
                ...new Set([
                    ...reviewAnalysis.rejected,
                    ...unsupportedCategoryTags
                ])
            ]
        }
    };
}

module.exports = {
    TYPE_TAGS,
    RESIDENTIAL_PLACE_TYPES,
    RESIDENTIAL_NAME_PATTERN,
    hasMeaningfulCulturalTextEvidence,
    validatePlaceCandidate,
    metadataEntries,
    mergeEvidence,
    analyzePlace
};
