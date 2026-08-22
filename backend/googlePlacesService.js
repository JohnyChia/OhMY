const GOOGLE_PLACES_URL =
    "https://places.googleapis.com/v1";


function getApiKey() {

    const key =
        process.env.GOOGLE_PLACES_API_KEY;

    if (!key) {
        throw new Error(
            "GOOGLE_PLACES_API_KEY is not configured."
        );
    }

    return key;
}

// ============================================================
// SEARCH PLACES
// ============================================================

async function searchPlaces(query) {

    const response = await fetch(
        `${GOOGLE_PLACES_URL}/places:searchText`,
        {
            method: "POST",

            headers: {
                "Content-Type": "application/json",

                "X-Goog-Api-Key":
                    getApiKey(),

                "X-Goog-FieldMask": [
                    "places.id",
                    "places.displayName",
                    "places.formattedAddress",
                    "places.location",
                    "places.viewport",
                    "places.types",
                    "places.primaryType",
                    "places.googleMapsUri"
                ].join(",")
            },

            body: JSON.stringify({
                textQuery: query,
                languageCode: "en",
                regionCode: "MY",
                pageSize: 5
            })
        }
    );

    const data =
        await response.json();

    if (!response.ok) {
        throw new Error(
            JSON.stringify(data)
        );
    }

    return data;
}


// ============================================================
// MIXED AREA + PLACE SEARCH
// ============================================================

async function searchPlacesAndAttractions(query) {

    const searches =
        await Promise.all([
            searchPlaces(query),
            searchPlaces(
                `tourist attractions in ${query}`
            )
        ]);

    const places = [];
    const seenIds = new Set();

    for (const search of searches) {
        for (const place of search.places || []) {
            if (!place.id || seenIds.has(place.id)) {
                continue;
            }

            seenIds.add(place.id);
            places.push(place);
        }
    }

    return { places };
}


// ============================================================
// NEARBY SEARCH (NEW)
// ============================================================

async function searchNearbyPlaces({
    latitude,
    longitude,
    radius = 10_000,
    includedType,
    maxResultCount = 10
}) {

    const response = await fetch(
        `${GOOGLE_PLACES_URL}/places:searchNearby`,
        {
            method: "POST",

            headers: {
                "Content-Type": "application/json",
                "X-Goog-Api-Key": getApiKey(),
                "X-Goog-FieldMask": [
                    "places.id",
                    "places.displayName",
                    "places.formattedAddress",
                    "places.location",
                    "places.types",
                    "places.primaryType",
                    "places.googleMapsUri"
                ].join(",")
            },

            body: JSON.stringify({
                includedTypes: [includedType],
                maxResultCount,
                rankPreference: "DISTANCE",
                languageCode: "en",
                regionCode: "MY",
                locationRestriction: {
                    circle: {
                        center: {
                            latitude,
                            longitude
                        },
                        radius
                    }
                }
            })
        }
    );

    const data = await response.json();

    if (!response.ok) {
        throw new Error(JSON.stringify(data));
    }

    return data;
}


// ============================================================
// PLACE DETAILS + REVIEWS
// ============================================================

async function getPlaceDetails(placeId) {

    const response = await fetch(
        `${GOOGLE_PLACES_URL}/places/${placeId}`,
        {
            method: "GET",

            headers: {
                "Content-Type":
                    "application/json",

                "X-Goog-Api-Key":
                    getApiKey(),

                "X-Goog-FieldMask": [
                    "id",
                    "displayName",
                    "formattedAddress",
                    "location",
                    "rating",
                    "googleMapsUri",
                    "reviews"
                ].join(",")
            }
        }
    );

    const data =
        await response.json();

    if (!response.ok) {
        throw new Error(
            JSON.stringify(data)
        );
    }

    return data;
}


module.exports = {
    searchPlaces,
    searchPlacesAndAttractions,
    searchNearbyPlaces,
    getPlaceDetails
};
