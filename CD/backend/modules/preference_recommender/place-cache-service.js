const DEFAULT_CACHE_DAYS = 30;

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
            place_tags (
                confidence, evidence_count, supporting_reviews,
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
        if (tagRows.length === 0) continue;
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
                supportingReviews: Number(row.supporting_reviews || 0)
            };
        }
        cache.set(place.google_place_id, {
            databaseId: place.id,
            metadataFresh: place.google_data_expires_at
                ? new Date(place.google_data_expires_at).getTime() > Date.now()
                : false,
            place: placeSnapshot(place),
            analysis: { generalTags, culturalTags, statistics }
        });
    }
    return cache;
}

async function storeTaggedPlace(client, place, analysis, taggerVersion, generalTagNames) {
    if (!client) return;
    const now = new Date();
    const expiresAt = new Date(
        now.getTime() + DEFAULT_CACHE_DAYS * 24 * 60 * 60 * 1000
    );
    const location = place.location || {};
    const { data: storedPlace, error: placeError } = await client
        .from("places")
        .upsert({
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
            google_data_expires_at: expiresAt.toISOString(),
            tags_updated_at: now.toISOString(),
            tagger_version: taggerVersion,
            tag_status: "processed"
        }, { onConflict: "google_place_id" })
        .select("id")
        .single();
    if (placeError) throw placeError;

    const assignedTags = [
        ...(analysis.generalTags || []),
        ...(analysis.culturalTags || [])
    ];
    if (assignedTags.length === 0) return;
    const tagRecords = assignedTags.map(name => ({
        name,
        tag_type: tagType(name, generalTagNames)
    }));
    const { data: storedTags, error: tagError } = await client
        .from("tags")
        .upsert(tagRecords, { onConflict: "name" })
        .select("id,name");
    if (tagError) throw tagError;

    const { error: deleteError } = await client
        .from("place_tags")
        .delete()
        .eq("place_id", storedPlace.id);
    if (deleteError) throw deleteError;

    const rows = (storedTags || []).map(tag => {
        const statistic = analysis.statistics?.[tag.name] || {};
        return {
            place_id: storedPlace.id,
            tag_id: tag.id,
            confidence: Number(statistic.supportPercentage || 0),
            evidence_count: Number(statistic.supportingReviews || 0),
            supporting_reviews: Number(statistic.supportingReviews || 0),
            source: "rule_based_reviews",
            updated_at: now.toISOString()
        };
    });
    const { error: relationError } = await client.from("place_tags").insert(rows);
    if (relationError) throw relationError;
}

module.exports = { getCachedTaggedPlaces, storeTaggedPlace };
