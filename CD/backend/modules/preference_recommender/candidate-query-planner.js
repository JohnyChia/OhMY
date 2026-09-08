const TAG_TO_PLACE_TYPES = {
    Restaurant: ["restaurant"],
    Cafe: ["cafe", "coffee_shop"],
    Museum: ["museum", "history_museum", "art_museum"],
    Market: ["market", "shopping_mall"],
    Landmark: ["tourist_attraction", "historical_landmark"],
    Shopping: ["shopping_mall", "market"],
    Park: ["park", "botanical_garden"],
    Nature: ["national_park", "park", "wildlife_park"],
    Adventure: ["hiking_area", "adventure_sports_center"],
    Educational: ["museum", "library", "cultural_center"],
    Entertainment: ["performing_arts_theater", "amusement_park"],
    "International Cuisine": ["restaurant"],

    Heritage: [
        "historical_place",
        "historical_landmark",
        "cultural_landmark",
        "monument"
    ],
    "Cultural Learning": [
        "museum",
        "cultural_center",
        "history_museum"
    ],
    "Historical Landmark": [
        "historical_landmark",
        "historical_place",
        "monument"
    ],
    "Traditional Architecture": [
        "cultural_landmark",
        "historical_place",
        "tourist_attraction"
    ],
    "Traditional Craft": [
        "cultural_center",
        "art_gallery",
        "market"
    ],
    "Religious Heritage": [
        "hindu_temple",
        "mosque",
        "church",
        "buddhist_temple"
    ],
    "Cultural Festival": [
        "cultural_center",
        "event_venue",
        "performing_arts_theater"
    ],
    "Local Cuisine": ["restaurant", "market"],
    "Cultural Experience": [
        "cultural_center",
        "cultural_landmark",
        "tourist_attraction"
    ]
};

const FALLBACK_TYPE = "tourist_attraction";


function buildNearbySearchPlan({
    generalTags = [],
    culturalTags = [],
    maximumSearchTypes = 6
}) {
    const referenceTags = [
        ...generalTags.map(name => ({ name, group: "general" })),
        ...culturalTags.map(name => ({ name, group: "cultural" }))
    ];

    const candidates = new Map();

    for (const tag of referenceTags) {
        const mappedTypes = TAG_TO_PLACE_TYPES[tag.name] || [];

        mappedTypes.forEach((type, mappingIndex) => {
            if (!candidates.has(type)) {
                candidates.set(type, {
                    type,
                    reasons: [],
                    mappingPriority: 0
                });
            }

            const candidate = candidates.get(type);
            candidate.reasons.push(tag);
            candidate.mappingPriority +=
                (tag.group === "cultural" ? 3 : 2)
                + Math.max(0, 2 - mappingIndex);
        });
    }

    const selected = [];
    const uncoveredTags =
        new Set(referenceTags.map(tag => tag.name));
    const remaining = Array.from(candidates.values());

    while (
        selected.length < maximumSearchTypes
        && remaining.length > 0
    ) {
        remaining.sort((a, b) => {
            const uncoveredA = a.reasons.filter(
                reason => uncoveredTags.has(reason.name)
            ).length;
            const uncoveredB = b.reasons.filter(
                reason => uncoveredTags.has(reason.name)
            ).length;

            return uncoveredB - uncoveredA
                || b.mappingPriority - a.mappingPriority
                || a.type.localeCompare(b.type);
        });

        const next = remaining.shift();
        selected.push(next);
        next.reasons.forEach(
            reason => uncoveredTags.delete(reason.name)
        );
    }

    if (
        selected.length < maximumSearchTypes
        && !selected.some(item => item.type === FALLBACK_TYPE)
    ) {
        selected.push({
            type: FALLBACK_TYPE,
            reasons: [{
                name: "Broad attraction fallback",
                group: "fallback"
            }],
            mappingPriority: 0
        });
    }

    if (selected.length === 0) {
        selected.push({
            type: FALLBACK_TYPE,
            reasons: [{
                name: "No mapped reference tags",
                group: "fallback"
            }],
            mappingPriority: 0
        });
    }

    return selected
        .slice(0, maximumSearchTypes)
        .map(item => ({
            type: item.type,
            reasons: item.reasons.map(reason => ({ ...reason }))
        }));
}


module.exports = {
    TAG_TO_PLACE_TYPES,
    buildNearbySearchPlan
};
