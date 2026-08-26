require("dotenv").config();

const express = require("express");
const cors = require("cors");
const path = require("node:path");
const { createClient } = require("@supabase/supabase-js");
const {
    searchPlaces,
    searchPlacesAndAttractions,
    searchNearbyPlaces,
    getPlaceDetails,
    getPlacePhoto
} = require("./googlePlacesService");
const {
    TaggingService,
    GENERAL_TAGS,
    CULTURAL_TAGS
} = require("./tagging-service");
const {
    buildNearbySearchPlan
} = require("./candidate-query-planner");
const {
    calculateRecommendationScore,
    rankTaggedPlaces
} = require("./ranking-service");
const { getWeatherOverview } = require("./weather-service");
const { computeDrivingRoutes } = require("./routing-service");
const app = express();

app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

app.get("/api/weather/overview", async (req, res) => {
    try {
        const weather = await getWeatherOverview(req.query.lat, req.query.lon);
        res.json({ success: true, weather });
    } catch (error) {
        const clientError = error.message.startsWith("Invalid ");
        console.error("Weather overview error:", error.message);
        res.status(clientError ? 400 : 502).json({
            error: clientError ? error.message : "Failed to retrieve weather information.",
            details: error.message
        });
    }
});

app.get("/api/routes", async (req, res) => {
    try {
        const result = await computeDrivingRoutes(req.query);
        res.json({ success: true, ...result });
    } catch (error) {
        const clientError = error.message.startsWith("Invalid ");
        console.error("Route calculation error:", error.message);
        res.status(clientError ? 400 : 502).json({
            success: false,
            error: clientError ? error.message : "Failed to calculate driving routes.",
            details: error.message
        });
    }
});

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

const MAX_RECOMMENDATIONS = 5;
const tagger = new TaggingService();


/* =====================================================
   WEB MAP CONFIGURATION
===================================================== */

app.get(
  "/api/config/maps",
  (req, res) => {
    const apiKey =
      process.env.GOOGLE_MAPS_BROWSER_API_KEY;

    if (!apiKey) {
      return res.status(503).json({
        error:
          "GOOGLE_MAPS_BROWSER_API_KEY is not configured."
      });
    }

    res.json({
      apiKey,
      mapId:
        process.env.GOOGLE_MAPS_MAP_ID
        || null
    });
  }
);


/* =====================================================
   GET TAGS FOR A PLACE
===================================================== */

async function getPlaceTags(placeId) {

  const { data, error } = await supabase
    .from("place_tags")
    .select(`
      tag_id,
      confidence,
      tags (
        id,
        name,
        tag_type
      )
    `)
    .eq("place_id", placeId);

  if (error) {
    throw error;
  }

  return data.map(item => ({
    id: item.tags.id,
    name: item.tags.name,
    tagType: item.tags.tag_type,
    confidence: item.confidence ?? 1
  }));
}


/* =====================================================
   CALCULATE TAG SIMILARITY

   Reference-tag coverage:

       matching tags
       -------------
       reference tags

   This measures how much of the reference
   characteristics the candidate satisfies.

   It is used for BOTH:

   1. Destination-based recommendations
   2. Preference-based recommendations
===================================================== */

function calculateSimilarity(
  referenceTags,
  candidateTags
) {

  const referenceNames =
    new Set(
      referenceTags.map(tag => tag.name)
    );

  const candidateNames =
    new Set(
      candidateTags.map(tag => tag.name)
    );


  // No reference tags = cannot calculate
  if (referenceNames.size === 0) {

    return {
      score: 0,
      matchingTags: [],
      generalMatches: [],
      culturalMatches: [],

      referenceTagCount: 0,
      candidateTagCount: candidateNames.size,
      matchingTagCount: 0
    };
  }


  // Find matching tags
  const matchingTags = [
    ...referenceNames
  ].filter(
    tagName =>
      candidateNames.has(tagName)
  );


  // -----------------------------------------------
  // Reference-tag coverage
  //
  // Example:
  //
  // Reference = 5 tags
  // Matching  = 3 tags
  //
  // 3 / 5 = 0.60
  // -----------------------------------------------

  const score =
    matchingTags.length /
    referenceNames.size;


  // -----------------------------------------------
  // Separate General and Cultural matches
  // -----------------------------------------------

  const generalMatches =
    matchingTags.filter(tagName => {

      const tag =
        referenceTags.find(
          t => t.name === tagName
        );

      return tag?.tagType === "general";
    });


  const culturalMatches =
    matchingTags.filter(tagName => {

      const tag =
        referenceTags.find(
          t => t.name === tagName
        );

      return tag?.tagType === "cultural";
    });


  return {

    score,

    matchingTags,

    generalMatches,

    culturalMatches,

    culturalRelevance:
      getCulturalRelevance(culturalMatches),

    referenceTagCount:
      referenceNames.size,

    candidateTagCount:
      candidateNames.size,

    matchingTagCount:
      matchingTags.length
      
  };
}

/* =====================================================
   CULTURAL RELEVANCE

   This is NOT added to the similarity score.

   It is used as a secondary ranking factor.

   Example:

   Candidate A:
   similarity = 0.75
   cultural matches = 0

   Candidate B:
   similarity = 0.75
   cultural matches = 2

   B ranks above A.

   But:

   Candidate A:
   similarity = 0.80

   Candidate B:
   similarity = 0.75
   cultural matches = 3

   A remains above B.
===================================================== */
function getCulturalRelevance(
  culturalMatches
) {

  return culturalMatches.length;
}


/* =====================================================
   RANK CANDIDATES

   PRIMARY:
   similarity score

   SECONDARY:
   cultural relevance

   TERTIARY:
   number of matching tags
===================================================== */

function rankRecommendations(
  recommendations
) {

  recommendations.sort((a, b) => {

    // 1. Highest similarity first
    if (
      b.similarity !== a.similarity
    ) {
      return (
        b.similarity -
        a.similarity
      );
    }


    // 2. If similarity is equal,
    //    promote cultural relevance
    if (
      b.culturalRelevance !==
      a.culturalRelevance
    ) {
      return (
        b.culturalRelevance -
        a.culturalRelevance
      );
    }


    // 3. Finally, more matching tags
    return (
      b.matchingTags.length -
      a.matchingTags.length
    );
  });

  return recommendations;
}


/* =====================================================
   DESTINATION-BASED RECOMMENDATIONS

   GET:

   /recommendations/destination/1
===================================================== */

app.get(
  "/recommendations/destination/:placeId",
  async (req, res) => {

    try {

      const placeId =
        Number(req.params.placeId);


      if (Number.isNaN(placeId)) {

        return res.status(400).json({
          error: "Invalid place ID"
        });
      }


      /* ---------------------------------------------
         Get selected destination
      --------------------------------------------- */

      const {
        data: destination,
        error: destinationError
      } = await supabase
        .from("places")
        .select("*")
        .eq("id", placeId)
        .single();


      if (
        destinationError ||
        !destination
      ) {

        return res.status(404).json({
          error:
            "Destination not found"
        });
      }


      /* ---------------------------------------------
         Get destination tags
      --------------------------------------------- */

      const destinationTags =
        await getPlaceTags(placeId);


      /* ---------------------------------------------
         Get all other attractions

         NO 10 KM FILTER YET
      --------------------------------------------- */

      const {
        data: places,
        error: placesError
      } = await supabase
        .from("places")
        .select("*")
        .neq("id", placeId);


      if (placesError) {
        throw placesError;
      }


      const recommendations = [];


      /* ---------------------------------------------
         Compare destination against every place
      --------------------------------------------- */

      for (const place of places) {

        const candidateTags =
          await getPlaceTags(place.id);


        const similarity =
          calculateSimilarity(
            destinationTags,
            candidateTags
          );


        // Ignore completely unrelated places
        if (similarity.score <= 0) {
          continue;
        }

const culturalRelevance =
  getCulturalRelevance(
    similarity.culturalMatches
  );


        recommendations.push({

          id: place.id,

          name: place.name,

          description:
            place.description ?? "",

          latitude:
            place.latitude,

          longitude:
            place.longitude,


          similarity:
            Number(
              similarity.score.toFixed(3)
            ),


          similarityPercentage:
            Number(
              (
                similarity.score * 100
              ).toFixed(1)
            ),


          matchingTags:
            similarity.matchingTags,

          generalMatches:
            similarity.generalMatches,

          culturalMatches:
            similarity.culturalMatches,


          culturalRelevance
        });
      }


      /* ---------------------------------------------
         Rank
      --------------------------------------------- */

      rankRecommendations(
        recommendations
      );


      /* ---------------------------------------------
         Return top results
      --------------------------------------------- */

      const topRecommendations =
        recommendations.slice(
          0,
          MAX_RECOMMENDATIONS
        );


      res.json({

        mode:
          "destination",

        reference: {

          id:
            destination.id,

          name:
            destination.name,

          tags:
            destinationTags.map(
              tag => ({
                name: tag.name,
                type: tag.tagType
              })
            )
        },


        recommendations:
          topRecommendations
      });

    } catch (error) {

      console.error(
        "Destination recommendation error:",
        error
      );

      res.status(500).json({
        error:
          "Failed to generate recommendations",

        details:
          error.message
      });
    }
  }
);


/* =====================================================
   PREFERENCE-BASED RECOMMENDATIONS

   TEMPORARY TEST VERSION

   Example:

   GET /recommendations/preferences
       ?tags=Heritage,Cultural%20Learning,Museum

   Later this will retrieve the actual user's
   preference profile from Supabase.
===================================================== */

app.get(
  "/recommendations/preferences",
  async (req, res) => {

    try {

      let preferenceNames = [];


      /* ---------------------------------------------
         Temporary manual preference input
      --------------------------------------------- */

      if (req.query.tags) {

        preferenceNames =
          req.query.tags
            .split(",")
            .map(
              tag => tag.trim()
            )
            .filter(
              tag => tag.length > 0
            );
      }


      if (
        preferenceNames.length === 0
      ) {

        return res.status(400).json({

          error:
            "No preference tags provided",

          example:
            "/recommendations/preferences?tags=Heritage,Cultural%20Learning,Museum"
        });
      }


      /* ---------------------------------------------
         Convert preference names into
         the same tag structure
      --------------------------------------------- */

      const {
        data: preferenceTagData,
        error: preferenceError
      } = await supabase
        .from("tags")
        .select("*")
        .in(
          "name",
          preferenceNames
        );


      if (preferenceError) {
        throw preferenceError;
      }


      const preferenceTags =
        preferenceTagData.map(tag => ({
          id: tag.id,
          name: tag.name,
          tagType: tag.tag_type,
          confidence: 1
        }));


      /* ---------------------------------------------
         Get all places

         NO LOCATION FILTER YET
      --------------------------------------------- */

      const {
        data: places,
        error: placesError
      } = await supabase
        .from("places")
        .select("*");


      if (placesError) {
        throw placesError;
      }


      const recommendations = [];


      /* ---------------------------------------------
         Compare user preferences with places
      --------------------------------------------- */

      for (const place of places) {

        const candidateTags =
          await getPlaceTags(place.id);


        const similarity =
          calculateSimilarity(
            preferenceTags,
            candidateTags
          );


        if (similarity.score <= 0) {
          continue;
        }


        const culturalRelevance =
          getCulturalRelevance(
            similarity.culturalMatches
          );


        recommendations.push({

          id: place.id,

          name: place.name,

          description:
            place.description ?? "",

          latitude:
            place.latitude,

          longitude:
            place.longitude,


          similarity:
            Number(
              similarity.score.toFixed(3)
            ),


          similarityPercentage:
            Number(
              (
                similarity.score * 100
              ).toFixed(1)
            ),


          matchingTags:
            similarity.matchingTags,

          generalMatches:
            similarity.generalMatches,

          culturalMatches:
            similarity.culturalMatches,


          culturalRelevance
        });
      }


      /* ---------------------------------------------
         Rank
      --------------------------------------------- */

      rankRecommendations(
        recommendations
      );


      const topRecommendations =
        recommendations.slice(
          0,
          MAX_RECOMMENDATIONS
        );


      res.json({

        mode:
          "preferences",

        reference: {

          tags:
            preferenceTags.map(
              tag => ({
                name: tag.name,
                type: tag.tagType
              })
            )
        },


        recommendations:
          topRecommendations
      });

    } catch (error) {

      console.error(
        "Preference recommendation error:",
        error
      );

      res.status(500).json({

        error:
          "Failed to generate preference recommendations",

        details:
          error.message
      });
    }
  }
);


// ============================================================
// TEST ROUTE
// ============================================================

app.get(
    "/",
    (req, res) => {

        res.json({

            success:
                true,

            message:
                "Recommendation backend is running."

        });

    }
);


// ============================================================
// 2A / 2B
// SEARCH PLACE
// ============================================================

app.post(
    "/api/places/search",

    async (
        req,
        res
    ) => {

        try {

            const {
                query
            } = req.body;


            if (
                !query ||
                !query.trim()
            ) {

                return res.status(
                    400
                ).json({

                    error:
                        "Search query is required."

                });

            }


            const data =
                await searchPlacesAndAttractions(
                    query.trim()
                );

            const areaTypes = new Set([
                "locality",
                "sublocality",
                "sublocality_level_1",
                "administrative_area_level_1",
                "administrative_area_level_2",
                "neighborhood",
                "postal_code"
            ]);

            const places =
                (data.places || []).map(
                    place => ({
                        ...place,
                        isArea:
                            (place.types || []).some(
                                type => areaTypes.has(type)
                            )
                    })
                );


            res.json({

                success:
                    true,

                places:
                    places

            });

        }

        catch (error) {

            console.error(
                "Place search error:",
                error
            );


            res.status(
                500
            ).json({

                error:
                    "Failed to search Google Places."

            });

        }

    }
);


// ============================================================
// 2B / 2C
// PLACE DETAILS + REVIEWS
// ============================================================

app.post(
    "/api/places/details",

    async (
        req,
        res
    ) => {

        try {

            const {
                placeId
            } = req.body;


            if (
                !placeId ||
                !placeId.trim()
            ) {

                return res.status(
                    400
                ).json({

                    error:
                        "Place ID is required."

                });

            }


            const data =
                await getPlaceDetails(
                    placeId.trim()
                );


            // -------------------------------------------------
            // Normalize reviews
            // -------------------------------------------------

            const reviews =
                (
                    data.reviews ||
                    []
                ).map(
                    review => ({

                        author:

                            review
                                .authorAttribution
                                ?.displayName
                            || "Unknown",

                        rating:
                            review.rating
                            || null,

                        text:
                            review.text
                                ?.text
                            || "",

                        languageCode:
                            review.text
                                ?.languageCode
                            || null,

                        publishTime:
                            review.publishTime
                            || null

                    })
                );


            // -------------------------------------------------
            // Return clean response to Flutter
            // -------------------------------------------------

            res.json({

                success:
                    true,

                place: {

                    id:
                        data.id,

                    displayName:
                        data.displayName,

                    formattedAddress:
                        data.formattedAddress,

                    location:
                        data.location,

                    rating:
                        data.rating,

                    googleMapsUri:
                        data.googleMapsUri,

                    description:
                        data.editorialSummary?.text
                        || null,

                    primaryTypeDisplayName:
                        data.primaryTypeDisplayName?.text
                        || null,

                    photo: data.photos?.[0]
                        ? {
                            name: data.photos[0].name,
                            authorAttributions:
                                data.photos[0]
                                    .authorAttributions
                                || []
                        }
                        : null,

                    photos: (data.photos || [])
                        .slice(0, 5)
                        .map(photo => ({
                            name: photo.name,
                            authorAttributions:
                                photo.authorAttributions
                                || []
                        }))

                },

                reviews:
                    reviews

            });

        }

        catch (error) {

            console.error(
                "Place details error:",
                error
            );


            res.status(
                500
            ).json({

                error:
                    "Failed to retrieve place details."

            });

        }

    }
);


// ============================================================
// PLACE DETAILS + REVIEW TAGGING
// ============================================================

app.post(
    "/api/places/analyze",
    async (req, res) => {
        try {
            const placeId =
                String(req.body.placeId || "").trim();

            if (!placeId) {
                return res.status(400).json({
                    error: "Place ID is required."
                });
            }

            const requestStart =
                process.hrtime.bigint();

            const place =
                await getPlaceDetails(placeId);

            const reviewTexts =
                (place.reviews || [])
                    .map(
                        review =>
                            review.text?.text?.trim()
                            || ""
                    )
                    .filter(Boolean);

            if (reviewTexts.length === 0) {
                return res.status(422).json({
                    error:
                        "Google Places returned no review text for this attraction."
                });
            }

            const taggingStart =
                process.hrtime.bigint();

            const analysis =
                tagger.aggregatePlace(reviewTexts);

            const taggingMs =
                Number(
                    process.hrtime.bigint()
                    - taggingStart
                ) / 1_000_000;

            const totalMs =
                Number(
                    process.hrtime.bigint()
                    - requestStart
                ) / 1_000_000;

            res.json({
                success: true,
                place: {
                    id: place.id,
                    displayName: place.displayName,
                    formattedAddress:
                        place.formattedAddress,
                    location: place.location,
                    rating: place.rating ?? null,
                    googleMapsUri:
                        place.googleMapsUri,
                    description:
                        place.editorialSummary?.text
                        || null,
                    primaryTypeDisplayName:
                        place.primaryTypeDisplayName?.text
                        || null,
                    photo: place.photos?.[0]
                        ? {
                            name: place.photos[0].name,
                            authorAttributions:
                                place.photos[0]
                                    .authorAttributions
                                || []
                        }
                        : null,
                    photos: (place.photos || [])
                        .slice(0, 5)
                        .map(photo => ({
                            name: photo.name,
                            authorAttributions:
                                photo.authorAttributions
                                || []
                        }))
                },
                analysis,
                performance: {
                    taggingMs:
                        Number(taggingMs.toFixed(3)),
                    totalMs:
                        Number(totalMs.toFixed(3))
                }
            });
        } catch (error) {
            console.error(
                "Place analysis error:",
                error
            );

            res.status(500).json({
                error:
                    "Failed to fetch and tag this place.",
                details: error.message
            });
        }
    }
);


// ============================================================
// GOOGLE PLACE PHOTO PROXY
// ============================================================

app.get(
    "/api/places/photo",
    async (req, res) => {
        try {
            const photoName =
                String(req.query.name || "");

            const photoResponse =
                await getPlacePhoto(photoName);

            const contentType =
                photoResponse.headers.get(
                    "content-type"
                ) || "image/jpeg";

            const photoBuffer =
                Buffer.from(
                    await photoResponse.arrayBuffer()
                );

            res.set({
                "Content-Type": contentType,
                "Cache-Control":
                    "private, no-store, max-age=0"
            });

            res.send(photoBuffer);
        } catch (error) {
            res.status(404).json({
                error: "Place photo unavailable.",
                details: error.message
            });
        }
    }
);


// ============================================================
// NEARBY TAGGING TEST (NO RANKING / NO DATABASE WRITES)
// ============================================================

const FIXED_TEST_PREFERENCES = [
    "Museum",
    "Heritage",
    "Cultural Learning",
    "Nature",
    "Religious Heritage"
];

const NEARBY_RADIUS_METRES = 10_000;
const NEARBY_CANDIDATE_LIMIT = 30;
const DETAILS_CONCURRENCY = 4;
const MAXIMUM_SEARCH_TYPES = 6;
const RESULTS_PER_SEARCH_TYPE = 8;

const PREFERENCE_PLACE_TYPES = {
    Museum: new Set([
        "museum",
        "art_museum",
        "history_museum"
    ]),
    Nature: new Set([
        "national_park",
        "park",
        "wildlife_park",
        "botanical_garden"
    ]),
    "Religious Heritage": new Set([
        "hindu_temple",
        "mosque",
        "church",
        "buddhist_temple"
    ])
};


function matchesPreference(
    preference,
    assignedTags,
    candidateTypes
) {
    if (!assignedTags.includes(preference)) {
        return false;
    }

    const requiredTypes =
        PREFERENCE_PLACE_TYPES[preference];

    if (!requiredTypes) {
        return true;
    }

    return (candidateTypes || []).some(
        type => requiredTypes.has(type)
    );
}


function splitReferenceTags(tagNames) {
    const uniqueNames = [
        ...new Set(
            (tagNames || [])
                .map(tag => String(tag).trim())
                .filter(Boolean)
        )
    ];

    return {
        generalTags:
            uniqueNames.filter(
                tag => GENERAL_TAGS.includes(tag)
            ),
        culturalTags:
            uniqueNames.filter(
                tag => CULTURAL_TAGS.includes(tag)
            )
    };
}


function distanceMetres(
    latitudeA,
    longitudeA,
    latitudeB,
    longitudeB
) {
    const earthRadius = 6_371_000;
    const toRadians = value => value * Math.PI / 180;
    const latitudeDelta =
        toRadians(latitudeB - latitudeA);
    const longitudeDelta =
        toRadians(longitudeB - longitudeA);

    const value =
        Math.sin(latitudeDelta / 2) ** 2
        + Math.cos(toRadians(latitudeA))
            * Math.cos(toRadians(latitudeB))
            * Math.sin(longitudeDelta / 2) ** 2;

    return earthRadius * 2
        * Math.atan2(
            Math.sqrt(value),
            Math.sqrt(1 - value)
        );
}


async function mapWithConcurrency(
    items,
    concurrency,
    mapper
) {
    const results = new Array(items.length);
    let nextIndex = 0;

    async function worker() {
        while (nextIndex < items.length) {
            const currentIndex = nextIndex;
            nextIndex++;
            results[currentIndex] =
                await mapper(
                    items[currentIndex],
                    currentIndex
                );
        }
    }

    await Promise.all(
        Array.from(
            {
                length: Math.min(
                    concurrency,
                    items.length
                )
            },
            worker
        )
    );

    return results;
}


app.post(
    "/api/recommendations/nearby-tagged",
    async (req, res) => {
        try {
            const latitude = Number(req.body.latitude);
            const longitude = Number(req.body.longitude);

            if (
                !Number.isFinite(latitude)
                || latitude < -90
                || latitude > 90
                || !Number.isFinite(longitude)
                || longitude < -180
                || longitude > 180
            ) {
                return res.status(400).json({
                    error:
                        "Valid latitude and longitude are required."
                });
            }

            const requestStart =
                process.hrtime.bigint();

            const mode =
                req.body.mode === "destination"
                    ? "destination"
                    : "preferences";

            let reference;

            if (mode === "destination") {
                const destinationPlaceId =
                    String(
                        req.body.destinationPlaceId
                        || ""
                    ).trim();

                if (!destinationPlaceId) {
                    return res.status(400).json({
                        error:
                            "destinationPlaceId is required for destination mode."
                    });
                }

                const destination =
                    await getPlaceDetails(
                        destinationPlaceId
                    );

                const destinationReviews =
                    (destination.reviews || [])
                        .map(
                            review =>
                                review.text?.text?.trim()
                                || ""
                        )
                        .filter(Boolean);

                if (destinationReviews.length === 0) {
                    return res.status(422).json({
                        error:
                            "The selected destination has no usable reviews for tag generation."
                    });
                }

                const destinationAnalysis =
                    tagger.aggregatePlace(
                        destinationReviews
                    );

                reference = {
                    source: "destination",
                    destination: {
                        id: destination.id,
                        name:
                            destination.displayName?.text
                            || "Selected destination"
                    },
                    generalTags:
                        destinationAnalysis.generalTags,
                    culturalTags:
                        destinationAnalysis.culturalTags
                };
            } else {
                const requestedPreferences =
                    Array.isArray(req.body.preferences)
                        && req.body.preferences.length > 0
                        ? req.body.preferences
                        : FIXED_TEST_PREFERENCES;

                const splitPreferences =
                    splitReferenceTags(
                        requestedPreferences
                    );

                reference = {
                    source: "preferences",
                    ...splitPreferences
                };
            }

            if (
                reference.generalTags.length === 0
                && reference.culturalTags.length === 0
            ) {
                return res.status(400).json({
                    error:
                        "No supported general or cultural reference tags were provided."
                });
            }

            const searchPlan =
                buildNearbySearchPlan({
                    generalTags:
                        reference.generalTags,
                    culturalTags:
                        reference.culturalTags,
                    maximumSearchTypes:
                        MAXIMUM_SEARCH_TYPES
                });

            const nearbySearches =
                await Promise.allSettled(
                    searchPlan.map(
                        planItem =>
                            searchNearbyPlaces({
                                latitude,
                                longitude,
                                radius:
                                    NEARBY_RADIUS_METRES,
                                includedType:
                                    planItem.type,
                                maxResultCount:
                                    RESULTS_PER_SEARCH_TYPE
                            })
                    )
                );

            const candidateMap = new Map();

            for (
                let searchIndex = 0;
                searchIndex < nearbySearches.length;
                searchIndex++
            ) {
                const search =
                    nearbySearches[searchIndex];
                const planItem =
                    searchPlan[searchIndex];

                if (search.status !== "fulfilled") {
                    console.warn(
                        "Nearby type search failed:",
                        search.reason?.message
                    );
                    continue;
                }

                const searchPlaces =
                    search.value.places || [];

                for (
                    let placeIndex = 0;
                    placeIndex < searchPlaces.length;
                    placeIndex++
                ) {
                    const place =
                        searchPlaces[placeIndex];
                    const routingSummary =
                        search.value.routingSummaries?.[
                            placeIndex
                        ] || null;

                    if (!place.id || !place.location) {
                        continue;
                    }

                    if (!candidateMap.has(place.id)) {
                        candidateMap.set(place.id, {
                            ...place,
                            discoveredFrom: [],
                            routingSummary,
                            distanceMetres:
                                distanceMetres(
                                    latitude,
                                    longitude,
                                    place.location.latitude,
                                    place.location.longitude
                                )
                        });
                    }

                    const candidate =
                        candidateMap.get(place.id);

                    if (
                        !candidate.routingSummary
                        && routingSummary
                    ) {
                        candidate.routingSummary =
                            routingSummary;
                    }

                    candidate.discoveredFrom.push({
                        googleType: planItem.type,
                        referenceTags:
                            planItem.reasons.map(
                                reason => reason.name
                            )
                    });
                }
            }

            const candidates =
                Array.from(candidateMap.values())
                    .filter(
                        place =>
                            place.distanceMetres
                            <= NEARBY_RADIUS_METRES
                            && place.id
                                !== reference.destination?.id
                    )
                    .sort(
                        (a, b) =>
                            a.distanceMetres
                            - b.distanceMetres
                    )
                    .slice(0, NEARBY_CANDIDATE_LIMIT);

            const processed =
                await mapWithConcurrency(
                    candidates,
                    DETAILS_CONCURRENCY,
                    async candidate => {
                        try {
                            const place =
                                await getPlaceDetails(
                                    candidate.id
                                );

                            const reviewTexts =
                                (place.reviews || [])
                                    .map(
                                        review =>
                                            review.text
                                                ?.text
                                                ?.trim()
                                            || ""
                                    )
                                    .filter(Boolean);

                            if (reviewTexts.length === 0) {
                                return {
                                    status: "skipped",
                                    reason: "no_reviews",
                                    id: candidate.id,
                                    name:
                                        candidate.displayName
                                            ?.text
                                        || "Unknown place"
                                };
                            }

                            const taggingStart =
                                process.hrtime.bigint();

                            const analysis =
                                tagger.aggregatePlace(
                                    reviewTexts
                                );

                            const taggingMs =
                                Number(
                                    process.hrtime.bigint()
                                    - taggingStart
                                ) / 1_000_000;

                            const assignedTags = [
                                ...analysis.generalTags,
                                ...analysis.culturalTags
                            ];

                            const validatedGeneralTags =
                                analysis.generalTags.filter(
                                    tag =>
                                        matchesPreference(
                                            tag,
                                            assignedTags,
                                            candidate.types
                                        )
                                );

                            const ranking =
                                calculateRecommendationScore({
                                    referenceGeneralTags:
                                        reference.generalTags,
                                    referenceCulturalTags:
                                        reference.culturalTags,
                                    candidateGeneralTags:
                                        validatedGeneralTags,
                                    candidateCulturalTags:
                                        analysis.culturalTags,
                                    statistics:
                                        analysis.statistics
                                });

                            const matchedPreferences =
                                ranking.matchingTags;

                            const routeLeg =
                                candidate.routingSummary
                                    ?.legs?.[0]
                                || null;

                            const durationSeconds =
                                Number.parseFloat(
                                    String(
                                        routeLeg?.duration
                                        || ""
                                    ).replace("s", "")
                                );

                            const routeDistanceMetres =
                                Number(
                                    routeLeg?.distanceMeters
                                );

                            const primaryPhoto =
                                place.photos?.[0]
                                || null;

                            return {
                                status: "tagged",
                                place: {
                                    id: place.id,
                                    displayName:
                                        place.displayName,
                                    formattedAddress:
                                        place.formattedAddress,
                                    location:
                                        place.location,
                                    rating:
                                        place.rating ?? null,
                                    googleMapsUri:
                                        place.googleMapsUri,
                                    description:
                                        place.editorialSummary
                                            ?.text
                                        || null,
                                    primaryType:
                                        place.primaryType
                                        || candidate.primaryType
                                        || null,
                                    primaryTypeDisplayName:
                                        place.primaryTypeDisplayName
                                            ?.text
                                        || null,
                                    photo:
                                        primaryPhoto
                                            ? {
                                                name:
                                                    primaryPhoto.name,
                                                authorAttributions:
                                                    primaryPhoto
                                                        .authorAttributions
                                                    || []
                                            }
                                            : null,
                                    photos:
                                        (place.photos || [])
                                            .slice(0, 5)
                                            .map(photo => ({
                                                name: photo.name,
                                                authorAttributions:
                                                    photo.authorAttributions
                                                    || []
                                            })),
                                    types:
                                        candidate.types || [],
                                    distanceMetres:
                                        Math.round(
                                            candidate
                                                .distanceMetres
                                        ),
                                    distanceKm:
                                        Number(
                                            (
                                                candidate
                                                    .distanceMetres
                                                / 1000
                                            ).toFixed(2)
                                        ),
                                    routeDistanceMetres:
                                        Number.isFinite(
                                            routeDistanceMetres
                                        )
                                            ? routeDistanceMetres
                                            : null,
                                    routeDistanceKm:
                                        Number.isFinite(
                                            routeDistanceMetres
                                        )
                                            ? Number(
                                                (
                                                    routeDistanceMetres
                                                    / 1000
                                                ).toFixed(2)
                                            )
                                            : null,
                                    etaMinutes:
                                        Number.isFinite(
                                            durationSeconds
                                        )
                                            ? Math.max(
                                                1,
                                                Math.ceil(
                                                    durationSeconds
                                                    / 60
                                                )
                                            )
                                            : Math.max(
                                                2,
                                                Math.ceil(
                                                    candidate
                                                        .distanceMetres
                                                    / 500
                                                )
                                            ),
                                    etaEstimated:
                                        !Number.isFinite(
                                            durationSeconds
                                        ),
                                    directionsUri:
                                        candidate.routingSummary
                                            ?.directionsUri
                                        || null
                                },
                                analysis,
                                matchedPreferences,
                                ranking,
                                discoveredFrom:
                                    candidate.discoveredFrom,
                                eligible:
                                    matchedPreferences.length > 0,
                                performance: {
                                    taggingMs:
                                        Number(
                                            taggingMs.toFixed(3)
                                        )
                                },
                                source: "live_google_places"
                            };
                        } catch (error) {
                            return {
                                status: "failed",
                                id: candidate.id,
                                name:
                                    candidate.displayName?.text
                                    || "Unknown place",
                                reason: error.message
                            };
                        }
                    }
                );

            const taggedPlaces =
                processed.filter(
                    item => item.status === "tagged"
                );

            const rankedTaggedPlaces =
                rankTaggedPlaces(taggedPlaces);

            const matchedPlaces =
                rankedTaggedPlaces.filter(
                    item => item.eligible
                );

            const totalMs =
                Number(
                    process.hrtime.bigint()
                    - requestStart
                ) / 1_000_000;

            res.json({
                success: true,
                mode,
                ranked: true,
                persisted: false,
                origin: {
                    latitude,
                    longitude
                },
                radiusMetres:
                    NEARBY_RADIUS_METRES,
                preferences:
                    mode === "preferences"
                        ? [
                            ...reference.generalTags,
                            ...reference.culturalTags
                        ]
                        : null,
                reference,
                searchPlan,
                searchedPlaceTypes:
                    searchPlan.map(
                        planItem => planItem.type
                    ),
                candidateCount:
                    candidates.length,
                taggedCount:
                    taggedPlaces.length,
                matchedCount:
                    matchedPlaces.length,
                skippedOrFailedCount:
                    processed.length
                    - taggedPlaces.length,
                taggedPlaces:
                    rankedTaggedPlaces,
                matchedPlaces,
                performance: {
                    totalMs:
                        Number(totalMs.toFixed(3))
                }
            });
        } catch (error) {
            console.error(
                "Nearby tagging test error:",
                error
            );

            res.status(500).json({
                error:
                    "Failed to discover and tag nearby places.",
                details: error.message
            });
        }
    }
);


/* =====================================================
   HEALTH CHECK
===================================================== */

app.get(
  "/",
  (req, res) => {

    res.json({
      status: "ok",
      service:
        "Recommendation API"
    });
  }
);


/* =====================================================
   START SERVER
===================================================== */

const PORT =
  process.env.PORT || 3000;

app.listen(
  PORT,
  () => {

    console.log(
      `Recommendation API running on port ${PORT}`
    );
  }
);
