const DEFAULT_CACHE_DAYS = 30;
const { createHash } = require("node:crypto");

function tagType(tag, generalTags) {
    return generalTags.includes(tag) ? "general" : "cultural";
}

function placeSnapshot(place) {
    return {
        displayName: { text: place.name },
        description: place.description || null,
        formattedAddress: place.formatted_address || "",
        location: {
            latitude: place.latitude,
            longitude: place.longitude
        },
        rating: place.rating,
        googleMapsUri: place.google_maps_uri,
        primaryType: place.primary_type,
        types: place.place_types || [],
        photos: place.photo_references || []
    };
}

async function getCachedTaggedPlaces(client, googlePlaceIds, taggerVersion) {
    if (!client || googlePlaceIds.length === 0) return new Map();
    const { data, error } = await client
        .from("places")
        .select(`
            id, name, description, latitude, longitude, google_place_id,
            formatted_address, rating, google_maps_uri, primary_type,
            place_types, photo_references, google_data_expires_at,
            tags_updated_at, tagger_version, tag_status,
            tag_fingerprint, tag_language_summary, tag_evidence_summary,
            place_tags (
                confidence, evidence_count, supporting_reviews,
                average_score, evidence_details, source,
                tags (name, tag_type)
            )
        `)
        .in("google_place_id", googlePlaceIds)
        .eq("tag_status", "processed")
        .eq("tagger_version", taggerVersion);

    if (error) throw error;
    const cache = new Map();
    for (const place of data || []) {
        const tagRows = (place.place_tags || []).filter(row => row.tags?.name);
        const generalTags = [];
        const culturalTags = [];
        const statistics = {};
        for (const row of tagRows) {
            const name = row.tags.name;
            if (row.tags.tag_type === "general") generalTags.push(name);
            else culturalTags.push(name);
            statistics[name] = {
                assigned: true,
                supportPercentage: Number(row.confidence || 0),
                supportingReviews: Number(row.supporting_reviews || 0),
                averageScore: Number(row.average_score || 0),
                evidenceCount: Number(row.evidence_count || 0),
                evidenceTypes: row.evidence_details || {},
                source: row.source || "rule_based_reviews"
            };
        }
        cache.set(place.google_place_id, {
            databaseId: place.id,
            metadataFresh: place.google_data_expires_at
                ? new Date(place.google_data_expires_at).getTime() > Date.now()
                : false,
            place: placeSnapshot(place),
            analysis: {
                generalTags,
                culturalTags,
                statistics,
                languageSummary: place.tag_language_summary || {},
                evidenceSummary: place.tag_evidence_summary || {}
            },
            fingerprint: place.tag_fingerprint || null
        });
    }
    return cache;
}

function buildTagAssignments(analysis, generalTagNames) {
    return [
        ...(analysis.generalTags || []),
        ...(analysis.culturalTags || [])
    ].map(name => {
        const statistic = analysis.statistics?.[name] || {};
        return {
            name,
            tagType: tagType(name, generalTagNames),
            // Avoid rewriting relationships for insignificant float movement.
            confidence: Number(Number(statistic.supportPercentage || 0).toFixed(2)),
            evidenceCount: Number(statistic.evidenceCount || 0),
            supportingReviews: Number(statistic.supportingReviews || 0),
            averageScore: Number(Number(statistic.averageScore || 0).toFixed(2)),
            evidenceDetails: statistic.evidenceTypes || {},
            source: statistic.source || "rule_based_reviews"
        };
    }).sort((a, b) => a.name.localeCompare(b.name));
}

function tagFingerprint(assignments) {
    const stable = [...assignments]
        .sort((a, b) => a.name.localeCompare(b.name))
        .map(tag => [
            tag.name,
            tag.tagType,
            tag.confidence.toFixed(2),
            tag.evidenceCount,
            tag.supportingReviews,
            tag.averageScore.toFixed(2),
            tag.source,
            Object.entries(tag.evidenceDetails || {}).sort()
        ]);
    return createHash("sha256")
        .update(JSON.stringify(stable))
        .digest("hex");
}

async function storeTaggedPlace(client, place, analysis, taggerVersion, generalTagNames) {
    if (!client) return { changed: false, persisted: false };
    const now = new Date();
    const expiresAt = new Date(
        now.getTime() + DEFAULT_CACHE_DAYS * 24 * 60 * 60 * 1000
    );
    const assignments = buildTagAssignments(analysis, generalTagNames);
    const fingerprint = tagFingerprint(assignments);
    const location = place.location || {};
    const { data, error } = await client.rpc("replace_place_tags_v2", {
        p_place: {
            google_place_id: place.id,
            name: place.displayName?.text || "Unknown place",
            description: place.editorialSummary?.text || null,
            latitude: location.latitude,
            longitude: location.longitude,
            formatted_address: place.formattedAddress || null,
            rating: place.rating ?? null,
            google_maps_uri: place.googleMapsUri || null,
            primary_type: place.primaryType || null,
            place_types: place.types || [],
            photo_references: (place.photos || []).slice(0, 9).map(photo => ({
                name: photo.name,
                authorAttributions: photo.authorAttributions || []
            })),
            google_data_cached_at: now.toISOString(),
            google_data_expires_at: expiresAt.toISOString()
        },
        p_tags: assignments,
        p_tagger_version: taggerVersion,
        p_fingerprint: fingerprint,
        p_language_summary: analysis.languageSummary || {},
        p_evidence_summary: analysis.evidenceSummary || {}
    });
    if (error) throw error;
    return {
        persisted: true,
        changed: Boolean(data?.changed),
        placeId: data?.place_id,
        fingerprint
    };
}

module.exports = {
    getCachedTaggedPlaces,
    storeTaggedPlace,
    buildTagAssignments,
    tagFingerprint
};
