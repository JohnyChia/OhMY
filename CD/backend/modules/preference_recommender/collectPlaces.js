require("dotenv").config({
    quiet: true
});

const fs =
    require("node:fs/promises");

const path =
    require("node:path");

const {
    searchPlaces,
    getPlaceDetails
} = require("./googlePlacesService");

const {
    TaggingService
} = require("./tagging-service");


const DATA_FILE =
    path.join(
        __dirname,
        "attractions.json"
    );

const MAX_REVIEWS = 5;


function normalizeReview(review) {

    return {
        author:
            review.authorAttribution
                ?.displayName
            || "Unknown",

        rating:
            review.rating
            || null,

        text:
            review.text
                ?.text
                ?.trim()
            || "",

        languageCode:
            review.text
                ?.languageCode
            || null,

        publishTime:
            review.publishTime
            || null
    };
}


async function loadAttractions() {

    try {

        const file =
            await fs.readFile(
                DATA_FILE,
                "utf8"
            );

        const data =
            JSON.parse(file);

        if (
            Array.isArray(
                data.attractions
            )
        ) {
            return data;
        }

    } catch (error) {

        // A missing or empty file starts
        // a fresh collection.
    }

    return {
        attractions: []
    };
}


async function saveAttractions(data) {

    await fs.mkdir(
        path.dirname(DATA_FILE),
        {
            recursive: true
        }
    );

    await fs.writeFile(
        DATA_FILE,
        JSON.stringify(
            data,
            null,
            2
        )
    );
}


async function main() {

    const programStartTime = process.hrtime.bigint();

    const query =
        process.argv
            .slice(2)
            .join(" ")
            .trim();

    if (!query) {

        throw new Error(
            "Provide a place name. Example: "
            + 'node collectPlaces.js '
            + '"National Museum of Malaysia Kuala Lumpur"'
        );
    }


    console.log(
        `Searching Google Places for: ${query}`
    );

    const searchData =
        await searchPlaces(query);

    const selectedPlace =
        searchData.places?.[0];

    if (!selectedPlace) {

        throw new Error(
            "No Google Place result found."
        );
    }


    console.log(
        `Selected: `
        + `${selectedPlace.displayName?.text}`
    );

    console.log(
        `Place ID: ${selectedPlace.id}`
    );


    const details =
        await getPlaceDetails(
            selectedPlace.id
        );

    const reviews =
        (details.reviews || [])
            .map(normalizeReview)
            .filter(
                review =>
                    review.text.length > 0
            )
            .slice(
                0,
                MAX_REVIEWS
            );

    const attraction = {
        place: {
            id:
                details.id,

            displayName:
                details.displayName,

            formattedAddress:
                details.formattedAddress,

            location:
                details.location,

            rating:
                details.rating
                || null,

            googleMapsUri:
                details.googleMapsUri
        },

        reviews,

        retrievedAt:
            new Date()
                .toISOString()
    };


    const collection =
        await loadAttractions();

    const existingIndex =
        collection.attractions
            .findIndex(
                item =>
                    item.place.id ===
                    attraction.place.id
            );

    if (existingIndex >= 0) {

        collection.attractions[
            existingIndex
        ] = attraction;

    } else {

        collection.attractions.push(
            attraction
        );
    }

    await saveAttractions(
        collection
    );


    console.log("");
    console.log(
        `Saved ${reviews.length} reviews to:`
    );
    console.log(DATA_FILE);


    if (reviews.length === 0) {

        console.log(
            "No review text was returned, so tagging was skipped."
        );

        return;
    }


    const tagger =
        new TaggingService();

    const reviewTexts =
        reviews.map(
            review =>
                review.text
        );

    const taggingStartTime = process.hrtime.bigint();

    const result =
        tagger.aggregatePlace(
            reviewTexts
        );

    const taggingTimeMs =
        Number(
            process.hrtime.bigint()
            - taggingStartTime
        ) / 1_000_000;

    console.log("");
    console.log(
        `TAGGING RESULT: `
        + `${attraction.place.displayName?.text}`
    );

    tagger.displayPlaceResult(
        result
    );

    const totalTimeMs =
        Number(
            process.hrtime.bigint()
            - programStartTime
        ) / 1_000_000;

    console.log(
        `Tagging time: ${taggingTimeMs.toFixed(3)} ms `
        + `(${(taggingTimeMs / reviews.length).toFixed(3)} ms/review)`
    );

    console.log(
        `Total runtime: ${(totalTimeMs / 1000).toFixed(3)} s`
    );
}


main()
    .catch(
        error => {

            console.error(
                "Collection failed:",
                error.message
            );

            process.exitCode = 1;
        }
    );
