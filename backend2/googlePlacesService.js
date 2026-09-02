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
        await Promise.allSettled([
            searchPlaces(query),
            searchPlaces(
                `tourist attractions in ${query}`
            )
        ]);

    const places = [];
    const seenIds = new Set();

    const failures = [];

    for (const search of searches) {
        if (search.status === "rejected") {
            failures.push(search.reason);
            continue;
        }

        for (const place of search.value.places || []) {
            if (!place.id || seenIds.has(place.id)) {
                continue;
            }

            seenIds.add(place.id);
            places.push(place);
        }
    }

    if (places.length === 0 && failures.length === searches.length) {
        throw failures[0];
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
                },
                routingParameters: {
                    origin: {
                        latitude,
                        longitude
                    },
                    travelMode: "DRIVE"
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
                    "types",
                    "primaryType",
                    "primaryTypeDisplayName",
                    "editorialSummary",
                    "photos",
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


// ============================================================
// PLACE PHOTO MEDIA
// ============================================================

async function getPlacePhoto(
    photoName,
    maxWidthPx = 1200,
    maxHeightPx = 800
) {
    if (
        !/^places\/[^/]+\/photos\/[^/]+$/.test(
            photoName
        )
    ) {
        throw new Error("Invalid Google Place photo name.");
    }

    const url = new URL(
        `${GOOGLE_PLACES_URL}/${photoName}/media`
    );

    url.searchParams.set(
        "maxWidthPx",
        String(maxWidthPx)
    );
    url.searchParams.set(
        "maxHeightPx",
        String(maxHeightPx)
    );
    url.searchParams.set("key", getApiKey());

    const response = await fetch(url);

    if (!response.ok) {
        throw new Error(
            `Google Place photo failed: ${response.status}`
        );
    }

    return response;
}


module.exports = {
    searchPlaces,
    searchPlacesAndAttractions,
    searchNearbyPlaces,
    getPlaceDetails,
    getPlacePhoto
};
