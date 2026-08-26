const readline = require("readline");
const natural = require("natural");

/*
============================================================
AUTOMATIC ATTRACTION TAGGING SERVICE
============================================================

Rule-Based NLP Tagging

Methods:
1. Exact keyword matching
2. Keyword phrase matching
3. Synonym dictionary
4. N-gram detection
5. Context window
6. Negation handling
7. Weighted evidence scoring
8. Multi-label classification
9. Review aggregation
10. Place-level final tagging

NO:
- Sentence embeddings
- Neural networks
- TF-IDF
- Naive Bayes
- Model training

The system is deterministic and explainable.
============================================================
*/


// ============================================================
// CONFIGURATION
// ============================================================

const CONFIG = {

    // --------------------------------------------------------
    // Review-level threshold
    //
    // A tag needs this score to be considered supported
    // by an individual review.
    // --------------------------------------------------------

    REVIEW_TAG_THRESHOLD: 4,


    // --------------------------------------------------------
    // Place-level threshold
    //
    // Percentage of reviews that need to support a tag
    // before the tag is assigned to the attraction.
    //
    // Example:
    //
    // 30 reviews
    // 6 support "Heritage"
    //
    // 6 / 30 = 20%
    //
    // If threshold = 10%
    // → Heritage is assigned.
    // --------------------------------------------------------

    PLACE_TAG_THRESHOLD: 0.10,


    // Cultural tags are more prone to false positives from broad
    // words such as "culture", "history", and "experience".
    // Establish that the PLACE is culturally relevant using agreement
    // across reviews, then allow individual specific cultural tags.
    CULTURAL_PLACE_MIN_REVIEWS: 2,


    // Google Places currently supplies at most five reviews in the
    // place-details response. Keep that limit explicit here too.
    MAX_RELEVANT_REVIEWS: 5,


    // Ignore extremely short comments such as "nice place" because
    // they do not contain enough information for reliable tagging.
    MIN_REVIEW_TOKENS: 3,


    // --------------------------------------------------------
    // Context window
    //
    // Number of words around a keyword that can contribute
    // contextual evidence.
    // --------------------------------------------------------

    CONTEXT_WINDOW: 10,


    // --------------------------------------------------------
    // Maximum score from the same category.
    //
    // Prevents a review containing many similar words from
    // producing an unreasonable score.
    // --------------------------------------------------------

    MAX_KEYWORD_SCORE: 50,


    // --------------------------------------------------------
    // Negation window
    //
    // Number of words before a matched phrase to check for
    // negation.
    // --------------------------------------------------------

    NEGATION_WINDOW: 5
};


// ============================================================
// SCORE WEIGHTS
// ============================================================

const WEIGHTS = {
    // Exact strong phrase
    strongPhrase: 8,
    // Exact medium phrase
    mediumPhrase: 5,
    // Exact weak keyword
    weakKeyword: 3,
    // Synonym
    synonym: 3,
    // Contextual supporting word
    context: 3,
    // N-gram / phrase combination
    ngram: 3,
    // Negation penalty
    negationPenalty: 1
};


// ============================================================
// NEGATION WORDS
// ============================================================

const NEGATION_WORDS = [

    "not",
    "no",
    "never",
    "none",
    "without",
    "doesn't",
    "doesnt",
    "don't",
    "dont",
    "didn't",
    "didnt",
    "isn't",
    "isnt",
    "wasn't",
    "wasnt",
    "weren't",
    "werent",
    "hardly",
    "neither",
    "nor"
];


// ============================================================
// TAG DEFINITIONS
// ============================================================
//
// Each tag has:
//
// description
// strong phrases
// medium phrases
// weak keywords
// synonyms
// contextual words
//
// One review can receive multiple tags.
// ============================================================


const TAGS = {


    // ========================================================
    // GENERAL TAGS
    // ========================================================

    "Restaurant": {

        description:
            "Restaurant or dining establishment.",

        strong: [
            "restaurant",
            "dining restaurant",
            "dining place",
            "eatery"
        ],

        medium: [
            "food restaurant",
            "dining establishment"
        ],

        weak: [
            "dining",
            "dinner",
            "lunch",
            "food",
            "meal"
        ],

        synonyms: [
            "eatery",
            "diner",
            "food outlet",
            "dining outlet"
        ],

        context: [
            "menu",
            "chef",
            "waiter",
            "table",
            "dish",
            "meal",
            "serve",
            "serves"
        ]
    },


    "Cafe": {

        description:
            "Cafe or coffee shop.",

        strong: [
            "cafe",
            "café",
            "coffee shop",
            "coffeehouse",
            "coffee house"
        ],

        medium: [
            "coffee place",
            "coffee cafe"
        ],

        weak: [
            "coffee",
            "latte",
            "cappuccino",
            "espresso"
        ],

        synonyms: [
            "coffeehouse",
            "coffee shop",
            "coffee place"
        ],

        context: [
            "pastry",
            "cake",
            "drink",
            "beverage",
            "barista",
            "dessert"
        ]
    },


    "Museum": {

        description:
            "Museum or institution displaying collections or exhibits.",

        strong: [
            "museum",
            "museum gallery"
        ],

        medium: [
            "museum exhibition",
            "museum collection"
        ],

        weak: [
            "exhibition",
            "exhibit",
            "gallery",
            "artefact",
            "artefacts",
            "artifact",
            "artifacts"
        ],

        synonyms: [
            "exhibition hall",
            "display centre",
            "display center"
        ],

        context: [
            "collection",
            "display",
            "curator",
            "historical",
            "artwork",
            "artefacts"
        ]
    },


    "Market": {

        description:
            "Market, bazaar, marketplace, or vendor area.",

        strong: [
            "market",
            "street market",
            "night market",
            "flea market",
            "local market"
        ],

        medium: [
            "marketplace",
            "street vendors",
            "local marketplace"
        ],

        weak: [
            "vendors",
            "vendor",
            "stalls",
            "stall"
        ],

        synonyms: [
            "bazaar",
            "marketplace",
            "trading area"
        ],

        context: [
            "seller",
            "selling",
            "goods",
            "products",
            "souvenir",
            "vendors"
        ]
    },


    "Landmark": {

        description:
            "Famous, iconic, notable, or recognizable landmark.",

        strong: [
            "landmark",
            "famous landmark",
            "iconic landmark"
        ],

        medium: [
            "iconic place",
            "famous place",
            "notable site",
            "famous attraction"
        ],

        weak: [
            "attraction",
            "must visit",
            "must-see",
            "notable"
        ],

        synonyms: [
            "icon",
            "iconic site",
            "point of interest"
        ],

        context: [
            "famous",
            "iconic",
            "popular",
            "recognizable",
            "well known"
        ]
    },


    "Shopping": {

        description:
            "Shopping, retail, malls, stores, or purchasing goods.",

        strong: [
            "shopping mall",
            "shopping centre",
            "shopping center",
            "shopping",
            "mall"
        ],

        medium: [
            "retail centre",
            "retail center",
            "shopping area"
        ],

        weak: [
            "shops",
            "shop",
            "stores",
            "store",
            "retail",
            "buy",
            "purchase"
        ],

        synonyms: [
            "shopping centre",
            "shopping center",
            "retail area",
            "commercial centre"
        ],

        context: [
            "brand",
            "clothing",
            "souvenir",
            "fashion",
            "products",
            "stores"
        ]
    },


    "Park": {

        description:
            "Public park, recreational park, garden, or green space.",

        strong: [
            "park",
            "public park",
            "city park",
            "theme park"
        ],

        medium: [
            "recreational park",
            "garden park"
        ],

        weak: [
            "playground",
            "picnic",
            "green space"
        ],

        synonyms: [
            "recreation park",
            "public garden"
        ],

        context: [
            "grass",
            "trees",
            "playground",
            "picnic",
            "walking",
            "recreation"
        ]
    },


    "Nature": {

        description:
            "Natural attraction involving forests, wildlife, beaches, rivers, lakes, mountains, or scenery.",

        strong: [
            "nature",
            "natural attraction",
            "nature reserve",
            "rainforest",
            "forest",
            "waterfall",
            "beach",
            "lake",
            "river"
        ],

        medium: [
            "natural scenery",
            "natural landscape",
            "wildlife area"
        ],

        weak: [
            "wildlife",
            "scenery",
            "landscape",
            "mountain",
            "jungle",
            "greenery",
            "outdoors",
            "outdoor"
        ],

        synonyms: [
            "natural environment",
            "natural area",
            "wilderness"
        ],

        context: [
            "animals",
            "plants",
            "trees",
            "forest",
            "sea",
            "river",
            "water",
            "wildlife"
        ]
    },


    "Adventure": {

        description:
            "Adventure, outdoor, physical, exciting, or extreme activities.",

        strong: [
            "adventure",
            "adventure activity",
            "extreme activity"
        ],

        medium: [
            "adventure activity",
            "outdoor adventure"
        ],

        weak: [
            "hiking",
            "trekking",
            "climbing",
            "rafting",
            "zipline",
            "kayaking",
            "exciting",
            "thrilling"
        ],

        synonyms: [
            "outdoor adventure",
            "extreme sport",
            "adventure experience"
        ],

        context: [
            "trail",
            "climb",
            "explore",
            "active",
            "challenge",
            "outdoor"
        ]
    },


    "Educational": {

        description:
            "Educational place or experience where visitors learn or gain knowledge.",

        strong: [
            "educational",
            "educational experience",
            "learning experience"
        ],

        medium: [
            "learning centre",
            "learning center",
            "educational program",
            "guided tour"
        ],

        weak: [
            "learn",
            "learning",
            "information",
            "knowledge",
            "explained"
        ],

        synonyms: [
            "learning centre",
            "learning center",
            "educational site"
        ],

        context: [
            "school",
            "students",
            "lesson",
            "information",
            "guide",
            "knowledge"
        ]
    },


    "Entertainment": {

        description:
            "Entertainment, shows, performances, amusement, movies, concerts, or recreation.",

        strong: [
            "entertainment",
            "entertainment venue",
            "amusement park"
        ],

        medium: [
            "theme park",
            "entertainment centre",
            "entertainment center"
        ],

        weak: [
            "show",
            "performance",
            "concert",
            "movie",
            "cinema",
            "fun",
            "enjoyable"
        ],

        synonyms: [
            "amusement",
            "recreation",
            "leisure entertainment"
        ],

        context: [
            "music",
            "stage",
            "performer",
            "actor",
            "audience",
            "event"
        ]
    },


    "International Cuisine": {

        description:
            "International, foreign, Western, Japanese, Korean, Chinese, Indian, Italian, or other non-local cuisine.",

        strong: [
            "international cuisine",
            "international food",
            "western cuisine",
            "western food",
            "italian cuisine",
            "japanese cuisine",
            "korean cuisine",
            "chinese cuisine",
            "indian cuisine"
        ],

        medium: [
            "foreign cuisine",
            "international dishes"
        ],

        weak: [
            "pizza",
            "pasta",
            "sushi",
            "ramen",
            "burger",
            "steak"
        ],

        synonyms: [
            "foreign food",
            "global cuisine",
            "international dishes"
        ],

        context: [
            "italian",
            "japanese",
            "korean",
            "chinese",
            "indian",
            "western",
            "foreign"
        ]
    },


    // ========================================================
    // CULTURAL VALUE TAGS
    // ========================================================
    "Heritage": {

        description:
            "Place with historical, cultural, preserved, or inherited heritage significance.",

        strong: [
            "heritage",
            "cultural heritage",
            "heritage site",
            "world heritage"
        ],

        medium: [
            "heritage building",
            "heritage area",
            "preserved heritage",
            "heritage attraction"
        ],

        weak: [
            "preserved",
            "traditional"
        ],

        synonyms: [
            "cultural heritage",
            "historic heritage",
            "heritage site"
        ],

        context: [
            "preserved",
            "historical",
            "traditional",
            "culture",
            "legacy",
            "historic"
        ]
    },


    "Cultural Learning": {

        description:
            "Place or experience where visitors learn about local culture, history, traditions, or cultural practices.",

        strong: [
            "cultural learning",
            "learn about the culture",
            "learn about local culture",
            "learn about malaysian culture"
        ],

        medium: [
            "learn about history",
            "learn about traditions",
            "cultural education",
            "educational cultural experience",
            "understand the culture"
        ],

        weak: [
            "culture",
            "tradition",
            "history"
        ],

        synonyms: [
            "cultural education",
            "cultural knowledge",
            "learn about culture"
        ],

        context: [
            "learn",
            "education",
            "knowledge",
            "history",
            "tradition",
            "culture",
            "heritage"
        ]
    },


    "Historical Landmark": {

        description:
            "Historical or historic place, building, monument, site, or landmark.",

        strong: [
            "historical landmark",
            "historic landmark",
            "historical site",
            "historic site",
            "historical building",
            "historic building"
        ],

        medium: [
            "historical place",
            "historic place",
            "historical monument",
            "historical significance"
        ],

        weak: [
            "historic",
            "historical",
            "ancient"
        ],

        synonyms: [
            "historic site",
            "historical site",
            "historic monument"
        ],

        context: [
            "past",
            "history",
            "old",
            "preserved",
            "monument",
            "historic"
        ]
    },


    "Traditional Architecture": {

        description:
            "Traditional local architecture, buildings, structures, construction methods, or architectural design.",

        strong: [
            "traditional architecture",
            "traditional building",
            "traditional house",
            "traditional structure",
            "traditional architectural style"
        ],

        medium: [
            "traditional design",
            "local architecture",
            "local architectural style",
            "wooden architecture",
            "traditional construction"
        ],

        weak: [
            "old building",
            "wooden building",
            "architectural design",
            "architecture"
        ],

        synonyms: [
            "vernacular architecture",
            "local architectural style",
            "traditional building style"
        ],

        context: [
            "building",
            "house",
            "architecture",
            "design",
            "structure",
            "wooden"
        ]
    },


    // "Indigenous Culture": {

    //     description:
    //         "Indigenous, native, or Orang Asli communities and their culture or traditions.",

    //     strong: [
    //         "indigenous culture",
    //         "indigenous community",
    //         "indigenous people",
    //         "orang asli",
    //         "native community"
    //     ],

    //     medium: [
    //         "native culture",
    //         "indigenous traditions",
    //         "indigenous heritage"
    //     ],

    //     weak: [
    //         "indigenous",
    //         "native"
    //     ],

    //     synonyms: [
    //         "culture",
    //         "indigenous heritage",
    //         "community"
    //     ],

    //     context: [
    //         "tribe",
    //         "community",
    //         "tradition",
    //         "native",
    //         "indigenous"
    //     ]
    // },


    "Traditional Craft": {

        description:
            "Traditional handmade crafts, handicrafts, artisans, local crafts, or traditional artwork.",

        strong: [
            "traditional craft",
            "traditional crafts",
            "traditional handicraft",
            "traditional handicrafts",
            "local handicraft",
            "local handicrafts"
        ],

        medium: [
            "handmade craft",
            "handmade crafts",
            "local crafts",
            "traditional artwork",
            "artisan work"
        ],

        weak: [
            "handmade",
            "craft",
            "crafts",
            "artisan"
        ],

        synonyms: [
            "handicraft",
            "handicrafts",
            "artisan work",
            "local handmade products"
        ],

        context: [
            "batik",
            "songket",
            "weaving",
            "carving",
            "pottery",
            "handmade",
            "artisan"
        ]
    },


    "Religious Heritage": {

        description:
            "Religious site with historical, cultural, architectural, or heritage significance.",

        strong: [
            "religious heritage",
            "religious heritage site",
            "religious monument",
            "religious historical site"
        ],

        medium: [
            "mosque",
            "temple",
            "church",
            "shrine",
            "monastery"
        ],

        weak: [
            "religious",
            "worship",
            "prayer"
        ],

        synonyms: [
            "place of worship",
            "religious site",
            "sacred site"
        ],

        context: [
            "islamic",
            "buddhist",
            "hindu",
            "christian",
            "religion",
            "faith",
            "worship"
        ]
    },


    "Cultural Festival": {

        description:
            "Cultural or traditional festival, celebration, cultural event, or traditional gathering.",

        strong: [
            "cultural festival",
            "traditional festival",
            "cultural celebration",
            "traditional celebration"
        ],

        medium: [
            "festival",
            "cultural event",
            "traditional event",
            "cultural performance"
        ],

        weak: [
            "celebration",
            "event",
            "performance"
        ],

        synonyms: [
            "cultural celebration",
            "traditional celebration",
            "cultural event"
        ],

        context: [
            "festival",
            "celebration",
            "event",
            "performance",
            "ceremony",
            "dance"
        ]
    },


    "Local Cuisine": {

        description:
            "Malaysian, local, or traditional food, dishes, restaurants, or culinary culture.",

        strong: [
            "local cuisine",
            "local food",
            "traditional cuisine",
            "traditional food",
            "local dishes"
        ],

        medium: [
            "local delicacy",
            "local delicacies",
            "malaysia food",
            "malaysia cuisine"
        ],

        weak: [
            "delicacy",
            "dish",
            "traditional dish"
        ],

        synonyms: [
            "local dishes",
            "local delicacies",
            "traditional cuisine",
            "traditional dishes"
        ],

        context: [
            "food",
            "dish",
            "cuisine",
            "delicacy",
            "recipe"
        ]
    },


    "Cultural Experience": {

        description:
            "Place or activity providing an immersive or meaningful experience of local culture, traditions, or heritage.",

        strong: [
            "cultural experience",
            "cultural immersion",
            "immersive cultural experience"
        ],

        medium: [
            "experience the culture",
            "experience local culture",
            "experience local traditions",
            "cultural activity",
            "traditional experience"
        ],

        weak: [
            "cultural",
            "local experience"
        ],

        synonyms: [
            "cultural activity",
            "cultural immersion",
            "local cultural experience",
            "culture",
            "community"
        ],

        context: [
            "culture",
            "tradition",
            "local",
            "experience",
            "activity",
            "native",
            "immersive"
        ]
    }
};


// ============================================================
// TAG GROUPS
// ============================================================

const GENERAL_TAGS = [

    "Restaurant",
    "Cafe",
    "Museum",
    "Market",
    "Landmark",
    "Shopping",
    "Park",
    "Nature",
    "Adventure",
    "Educational",
    "Entertainment",
    "International Cuisine"
];


const CULTURAL_TAGS = [

    "Heritage",
    "Cultural Learning",
    "Historical Landmark",
    "Traditional Architecture",
    // "Indigenous Culture",
    "Traditional Craft",
    "Religious Heritage",
    "Cultural Festival",
    "Local Cuisine",
    "Cultural Experience"
];


// ============================================================
// TOKENIZER
// ============================================================

const tokenizer =
    new natural.WordTokenizer();


// ============================================================
// TAGGING SERVICE
// ============================================================

class TaggingService {


    // ========================================================
    // PREPROCESS TEXT
    // ========================================================

    preprocess(text) {

        return String(text)

            .toLowerCase()

            .replace(
                /[“”]/g,
                "\""
            )

            .replace(
                /[‘’]/g,
                "'"
            )

            .replace(
                /\s+/g,
                " "
            )

            .trim();
    }


    // ========================================================
    // TOKENIZE
    // ========================================================

    tokenize(text) {

        return tokenizer.tokenize(
            text
        );
    }


    // ========================================================
    // NORMALIZE TOKEN
    // ========================================================

    normalizeToken(token) {

        return token
            .toLowerCase()
            .replace(
                /[^a-z0-9'-]/g,
                ""
            );
    }


    // ========================================================
    // FIND PHRASE
    // ========================================================

    findPhrasePositions(
        tokens,
        phrase
    ) {

        const phraseTokens =
            this.tokenize(
                phrase
            )
                .map(
                    token =>
                        this.normalizeToken(
                            token
                        )
                )
                .filter(
                    Boolean
                );


        const positions = [];


        for (
            let i = 0;
            i <=
            tokens.length -
            phraseTokens.length;
            i++
        ) {

            let matched = true;


            for (
                let j = 0;
                j < phraseTokens.length;
                j++
            ) {

                if (
                    this.normalizeToken(
                        tokens[i + j]
                    )
                    !==
                    phraseTokens[j]
                ) {

                    matched = false;

                    break;
                }
            }


            if (matched) {

                positions.push(
                    i
                );
            }
        }


        return positions;
    }


    // ========================================================
    // NEGATION CHECK
    // ========================================================

    hasNegation(
        tokens,
        startIndex
    ) {

        const start =
            Math.max(
                0,
                startIndex -
                CONFIG.NEGATION_WINDOW
            );


        for (
            let i = start;
            i < startIndex;
            i++
        ) {

            const token =
                this.normalizeToken(
                    tokens[i]
                );


            if (
                NEGATION_WORDS.includes(
                    token
                )
            ) {

                return true;
            }
        }


        return false;
    }


    // ========================================================
    // CONTEXT CHECK
    // ========================================================

    getContextWords(
        tokens,
        position
    ) {

        const start =
            Math.max(
                0,
                position -
                CONFIG.CONTEXT_WINDOW
            );


        const end =
            Math.min(
                tokens.length,
                position +
                CONFIG.CONTEXT_WINDOW +
                1
            );


        return tokens
            .slice(
                start,
                end
            )
            .map(
                token =>
                    this.normalizeToken(
                        token
                    )
            );
    }


    // ========================================================
    // N-GRAM DETECTION
    // ========================================================
    //
    // Creates:
    // 2-word phrases
    // 3-word phrases
    //
    // Example:
    //
    // "traditional Malaysian architecture"
    //
    // →
    // traditional Malaysian
    // Malaysian architecture
    // traditional Malaysian architecture
    // ========================================================

    generateNgrams(
        tokens
    ) {

        const ngrams = [];


        for (
            let n = 2;
            n <= 3;
            n++
        ) {

            for (
                let i = 0;
                i <=
                tokens.length - n;
                i++
            ) {

                const gram =
                    tokens
                        .slice(
                            i,
                            i + n
                        )
                        .map(
                            token =>
                                this.normalizeToken(
                                    token
                                )
                        )
                        .join(" ");


                ngrams.push({
                    text: gram,
                    position: i,
                    size: n
                });
            }
        }


        return ngrams;
    }


    // ========================================================
    // MATCH KEYWORD CATEGORY
    // ========================================================

    matchCategory(
        text,
        tokens,
        tag,
        category,
        weight
    ) {

        const rules =
            TAGS[tag][category] || [];


        const evidence = [];


        for (
            const phrase
            of rules
        ) {

            const positions =
                this.findPhrasePositions(
                    tokens,
                    phrase
                );


            for (
                const position
                of positions
            ) {

                const negated =
                    this.hasNegation(
                        tokens,
                        position
                    );


                evidence.push({

                    type:
                        category,

                    phrase,

                    position,

                    weight,

                    negated,

                    score:
                        negated
                            ? -WEIGHTS.negationPenalty
                            : weight
                });
            }
        }


        return evidence;
    }


    // ========================================================
    // SYNONYM MATCHING
    // ========================================================

    matchSynonyms(
        tokens,
        tag
    ) {

        const synonyms =
            TAGS[tag].synonyms || [];


        const evidence = [];


        for (
            const synonym
            of synonyms
        ) {

            const positions =
                this.findPhrasePositions(
                    tokens,
                    synonym
                );


            for (
                const position
                of positions
            ) {

                const negated =
                    this.hasNegation(
                        tokens,
                        position
                    );


                evidence.push({

                    type:
                        "synonym",

                    phrase:
                        synonym,

                    position,

                    weight:
                        WEIGHTS.synonym,

                    negated,

                    score:
                        negated
                            ? -WEIGHTS.negationPenalty
                            : WEIGHTS.synonym
                });
            }
        }


        return evidence;
    }


    // ========================================================
    // CONTEXT MATCHING
    // ========================================================

    matchContext(
        tokens,
        tag
    ) {

        const contextWords =
            TAGS[tag].context || [];


        const evidence = [];


        for (
            let i = 0;
            i < tokens.length;
            i++
        ) {

            const token =
                this.normalizeToken(
                    tokens[i]
                );


            if (
                contextWords.includes(
                    token
                )
            ) {

                evidence.push({

                    type:
                        "context",

                    phrase:
                        token,

                    position:
                        i,

                    weight:
                        WEIGHTS.context,

                    score:
                        WEIGHTS.context
                });
            }
        }


        return evidence;
    }


    // ========================================================
    // N-GRAM MATCHING
    // ========================================================
    //
    // If an N-gram contains multiple meaningful words
    // from a tag's rule set, provide additional evidence.
    // ========================================================

    matchNgrams(
        tokens,
        tag
    ) {

        const ngrams =
            this.generateNgrams(
                tokens
            );


        const allRules = [

            ...(TAGS[tag].strong || []),

            ...(TAGS[tag].medium || []),

            ...(TAGS[tag].synonyms || [])
        ];


        const evidence = [];


        for (
            const ngram
            of ngrams
        ) {

            for (
                const rule
                of allRules
            ) {

                const ruleTokens =
                    this.tokenize(
                        rule
                    )
                        .map(
                            token =>
                                this.normalizeToken(
                                    token
                                )
                        );


                const ngramTokens =
                    ngram.text
                        .split(" ");


                const overlap =
                    ngramTokens.filter(
                        token =>
                            ruleTokens.includes(
                                token
                            )
                    ).length;


                /*
                Require at least two matching
                words for N-gram evidence.
                */

                if (
                    overlap >= 2
                ) {

                    evidence.push({

                        type:
                            "ngram",

                        phrase:
                            ngram.text,

                        position:
                            ngram.position,

                        weight:
                            WEIGHTS.ngram,

                        score:
                            WEIGHTS.ngram
                    });


                    break;
                }
            }
        }


        return evidence;
    }


    // ========================================================
    // CALCULATE TAG SCORE
    // ========================================================

    calculateTagScore(
        text,
        tag
    ) {

        const tokens =
            this.tokenize(
                text
            );


        let evidence = [];


        // ----------------------------------------------------
        // Strong phrases
        // ----------------------------------------------------

        evidence.push(
            ...this.matchCategory(
                text,
                tokens,
                tag,
                "strong",
                WEIGHTS.strongPhrase
            )
        );


        // ----------------------------------------------------
        // Medium phrases
        // ----------------------------------------------------

        evidence.push(
            ...this.matchCategory(
                text,
                tokens,
                tag,
                "medium",
                WEIGHTS.mediumPhrase
            )
        );


        // ----------------------------------------------------
        // Weak keywords
        // ----------------------------------------------------

        evidence.push(
            ...this.matchCategory(
                text,
                tokens,
                tag,
                "weak",
                WEIGHTS.weakKeyword
            )
        );


        // ----------------------------------------------------
        // Synonyms
        // ----------------------------------------------------

        evidence.push(
            ...this.matchSynonyms(
                tokens,
                tag
            )
        );


        // ----------------------------------------------------
        // Context
        // ----------------------------------------------------

        evidence.push(
            ...this.matchContext(
                tokens,
                tag
            )
        );


        // ----------------------------------------------------
        // N-grams
        // ----------------------------------------------------

        evidence.push(
            ...this.matchNgrams(
                tokens,
                tag
            )
        );


        // ----------------------------------------------------
        // Remove excessive duplicate evidence
        // ----------------------------------------------------
        //
        // We don't want:
        //
        // food
        // food
        // food
        // food
        //
        // to create an enormous score.
        //
        // Keep the strongest evidence per phrase.
        // ----------------------------------------------------

        const phraseMap =
            new Map();


        for (
            const item
            of evidence
        ) {

            // The same word can appear as a weak keyword, synonym,
            // context word, and n-gram. It is still only one piece of
            // semantic evidence, so count its strongest occurrence once.
            const key =
                this.preprocess(item.phrase);


            if (
                !phraseMap.has(key)
            ) {

                phraseMap.set(
                    key,
                    item
                );

            } else {

                const existing =
                    phraseMap.get(
                        key
                    );


                if (
                    item.score >
                    existing.score
                ) {

                    phraseMap.set(
                        key,
                        item
                    );
                }
            }
        }


        evidence =
            Array.from(
                phraseMap.values()
            );


        // ----------------------------------------------------
        // Calculate total
        // ----------------------------------------------------

        let totalScore = 0;


        for (
            const item
            of evidence
        ) {

            totalScore +=
                item.score;
        }


        // ----------------------------------------------------
        // Limit score
        // ----------------------------------------------------

        totalScore =
            Math.max(
                0,
                Math.min(
                    totalScore,
                    CONFIG.MAX_KEYWORD_SCORE
                )
            );


        // ----------------------------------------------------
        // Determine assignment
        // ----------------------------------------------------

        const positiveCoreEvidence =
            evidence.filter(
                item =>
                    item.score > 0
                    && [
                        "strong",
                        "medium",
                        "weak",
                        "synonym"
                    ].includes(item.type)
            );

        const hasSpecificCulturalEvidence =
            positiveCoreEvidence.some(
                item =>
                    item.type === "strong"
                    || item.type === "medium"
            )
            || new Set(
                positiveCoreEvidence.map(
                    item => this.preprocess(item.phrase)
                )
            ).size >= 2;

        const assigned =
            totalScore >=
            CONFIG.REVIEW_TAG_THRESHOLD
            && (
                !CULTURAL_TAGS.includes(tag)
                || hasSpecificCulturalEvidence
            );


        return {

            tag,

            score:
                Number(
                    totalScore.toFixed(2)
                ),

            assigned,

            evidence
        };
    }


    // ========================================================
    // CLASSIFY ONE REVIEW
    // ========================================================

    classifyReview(
        originalText
    ) {

        const text =
            this.preprocess(
                originalText
            );


        if (!text) {

            return {

                review:
                    originalText,

                tags: [],

                details: {}
            };
        }


        const details = {};

        const selectedTags = [];


        // ----------------------------------------------------
        // Check EVERY tag
        // ----------------------------------------------------

        for (
            const tag
            of Object.keys(
                TAGS
            )
        ) {

            const result =
                this.calculateTagScore(
                    text,
                    tag
                );


            details[tag] =
                result;


            if (
                result.assigned
            ) {

                selectedTags.push(
                    tag
                );
            }
        }


        return {

            review:
                originalText,

            tags:
                selectedTags,

            details
        };
    }


    // ========================================================
    // CLASSIFY MULTIPLE REVIEWS
    // ========================================================

    classifyReviews(
        reviews
    ) {

        return reviews.map(
            review =>
                this.classifyReview(
                    review
                )
        );
    }


    // ========================================================
    // SELECT RELEVANT REVIEWS
    // ========================================================

    selectRelevantReviews(
        reviews,
        limit = CONFIG.MAX_RELEVANT_REVIEWS
    ) {

        const selected = [];
        const seen = new Set();

        for (const review of reviews || []) {

            const text =
                this.preprocess(
                    typeof review === "string"
                        ? review
                        : review?.text || ""
                );

            if (!text || seen.has(text)) {
                continue;
            }

            const meaningfulTokens =
                new Set(
                    this.tokenize(text)
                        .map(token => this.normalizeToken(token))
                        .filter(Boolean)
                );

            if (
                meaningfulTokens.size
                < CONFIG.MIN_REVIEW_TOKENS
            ) {
                continue;
            }

            seen.add(text);
            selected.push(text);

            if (selected.length >= limit) {
                break;
            }
        }

        return selected;
    }


    // ========================================================
    // AGGREGATE PLACE
    // ========================================================

    aggregatePlace(
        reviews
    ) {

        const relevantReviews =
            this.selectRelevantReviews(reviews);

        const results =
            this.classifyReviews(
                relevantReviews
            );


        // ----------------------------------------------------
        // PLACE-LEVEL CULTURAL RELEVANCE
        // ----------------------------------------------------
        //
        // Do not require two reviews for every individual tag.
        // A museum may have one review mentioning its traditional
        // architecture and other reviews discussing its culture and
        // history. Together they establish a cultural place, allowing
        // the specific architecture evidence to remain sensitive.
        //
        // A generic restaurant with one noisy use of "culture" does
        // not establish place-level cultural relevance.
        // ----------------------------------------------------

        const culturallyRelevantReviewCount =
            results.filter(
                result =>
                    result.tags.some(
                        tag => CULTURAL_TAGS.includes(tag)
                    )
            ).length;

        const culturallyRelevantPlace =
            relevantReviews.length < 2
            || culturallyRelevantReviewCount
                >= CONFIG.CULTURAL_PLACE_MIN_REVIEWS;


        const statistics = {};


        // ----------------------------------------------------
        // Initialize
        // ----------------------------------------------------

        for (
            const tag
            of Object.keys(
                TAGS
            )
        ) {

            statistics[tag] = {

                supportingReviews:
                    0,

                supportPercentage:
                    0,

                averageScore:
                    0,

                totalScore:
                    0,

                assigned:
                    false
            };
        }


        // ----------------------------------------------------
        // Aggregate
        // ----------------------------------------------------

        for (
            const result
            of results
        ) {

            for (
                const tag
                of Object.keys(
                    TAGS
                )
            ) {

                const details =
                    result.details[tag];


                statistics[tag]
                    .totalScore +=
                    details.score;


                if (
                    details.assigned
                ) {

                    statistics[tag]
                        .supportingReviews++;
                }
            }
        }


        // ----------------------------------------------------
        // Calculate percentages
        // ----------------------------------------------------

        for (
            const tag
            of Object.keys(
                TAGS
            )
        ) {

            const stat =
                statistics[tag];


            stat.supportPercentage =

                relevantReviews.length > 0

                    ?

                    stat.supportingReviews
                    /
                    relevantReviews.length

                    :

                    0;


            stat.averageScore =

                relevantReviews.length > 0

                    ?

                    stat.totalScore
                    /
                    relevantReviews.length

                    :

                    0;


            stat.supportPercentage =
                Number(
                    stat.supportPercentage
                        .toFixed(3)
                );


            stat.averageScore =
                Number(
                    stat.averageScore
                        .toFixed(2)
                );


            // ------------------------------------------------
            // FINAL PLACE-LEVEL THRESHOLD
            // ------------------------------------------------

            stat.assigned =

                stat.supportPercentage
                >= CONFIG.PLACE_TAG_THRESHOLD
                && (
                    !CULTURAL_TAGS.includes(tag)
                    || culturallyRelevantPlace
                );
        }


        // ----------------------------------------------------
        // Final tags
        // ----------------------------------------------------

        const finalTags =
            Object.keys(
                TAGS
            ).filter(
                tag =>
                    statistics[tag]
                        .assigned
            );


        const generalTags =
            finalTags.filter(
                tag =>
                    GENERAL_TAGS.includes(
                        tag
                    )
            );


        const culturalTags =
            finalTags.filter(
                tag =>
                    CULTURAL_TAGS.includes(
                        tag
                    )
            );


        return {

            reviewCount:
                relevantReviews.length,

            inputReviewCount:
                (reviews || []).length,

            culturallyRelevantReviewCount,

            culturallyRelevantPlace,

            generalTags,

            culturalTags,

            statistics
        };
    }


    // ========================================================
    // DISPLAY REVIEW RESULT
    // ========================================================

    displayReviewResult(
        result
    ) {

        console.log("");
        console.log(
            "============================================================"
        );

        console.log(
            "REVIEW"
        );

        console.log(
            "============================================================"
        );

        console.log(
            result.review
        );


        console.log("");
        console.log(
            "FINAL REVIEW TAGS"
        );

        console.log(
            "------------------------------------------------------------"
        );


        if (
            result.tags.length === 0
        ) {

            console.log(
                "No tags assigned."
            );

        } else {

            for (
                const tag
                of result.tags
            ) {

                const group =
                    GENERAL_TAGS.includes(
                        tag
                    )
                    ? "GENERAL"
                    : "CULTURAL";


                const details =
                    result.details[tag];


                console.log(
                    `✓ ${tag} [${group}]`
                );


                console.log(
                    `  Score: ${details.score}`
                );


                console.log(
                    "  Evidence:"
                );


                for (
                    const item
                    of details.evidence
                ) {

                    const sign =
                        item.score >= 0
                            ? "+"
                            : "";


                    console.log(
                        `    ${sign}${item.score} `
                        + `[${item.type}] `
                        + `"${item.phrase}"`
                    );


                    if (
                        item.negated
                    ) {

                        console.log(
                            "       ↳ NEGATED"
                        );
                    }
                }


                console.log("");
            }
        }


        // ----------------------------------------------------
        // TOP ALTERNATIVES
        // ----------------------------------------------------

        const alternatives =
            Object.values(
                result.details
            )
                .filter(
                    item =>
                        !item.assigned
                        &&
                        item.score > 0
                )
                .sort(
                    (a, b) =>
                        b.score -
                        a.score
                )
                .slice(
                    0,
                    5
                );


        console.log(
            "TOP UNSUBMITTED TAGS"
        );

        console.log(
            "------------------------------------------------------------"
        );


        for (
            const item
            of alternatives
        ) {

            console.log(
                `${item.tag}: ${item.score}`
            );
        }


        console.log(
            "============================================================"
        );
    }


    // ========================================================
    // DISPLAY PLACE RESULT
    // ========================================================

    displayPlaceResult(
        result
    ) {

        console.log("");
        console.log(
            "============================================================"
        );

        console.log(
            "FINAL PLACE TAG ANALYSIS"
        );

        console.log(
            "============================================================"
        );


        console.log(
            `Reviews processed: ${result.reviewCount}`
        );


        console.log("");
        console.log(
            "TAG SUPPORT"
        );

        console.log(
            "------------------------------------------------------------"
        );


        for (
            const [
                tag,
                stat
            ]
            of Object.entries(
                result.statistics
            )
        ) {

            if (
                stat.supportingReviews
                > 0
            ) {

                console.log(

                    `${tag.padEnd(25)} `

                    +

                    `${stat.supportingReviews}/`
                    +
                    `${result.reviewCount} `

                    +

                    `(${(
                        stat.supportPercentage
                        * 100
                    ).toFixed(1)}%) `

                    +

                    `score=${stat.averageScore}`

                    +

                    (
                        stat.assigned
                            ? " ✓"
                            : ""
                    )
                );
            }
        }


        console.log("");
        console.log(
            "FINAL GENERAL TAGS"
        );

        console.log(
            "------------------------------------------------------------"
        );


        console.log(
            result.generalTags.length
                ? result.generalTags.join(
                    ", "
                )
                : "None"
        );


        console.log("");
        console.log(
            "FINAL CULTURAL TAGS"
        );

        console.log(
            "------------------------------------------------------------"
        );


        console.log(
            result.culturalTags.length
                ? result.culturalTags.join(
                    ", "
                )
                : "None"
        );


        console.log(
            "============================================================"
        );
    }
}


// // ============================================================
// // CLI
// // ============================================================
// module.exports = {
//     TaggingService
// };

// if (require.main === module) {

//     const service =
//         new TaggingService();

//     const rl =
//         readline.createInterface({
//             input:
//                 process.stdin,

//             output:
//                 process.stdout
//         });

//     function ask(question) {
//         // Keep your existing ask implementation.
//     }

//     async function singleReviewMode() {
//         // Keep your existing function implementation.
//     }

//     async function placeMode() {
//         // Keep your existing function implementation.
//     }

//     async function main() {
//         // Keep your existing function implementation.
//     }

//     main();
// }



// ============================================================
// SINGLE REVIEW TEST
// ============================================================

const service = new TaggingService();

let rl;

function ask(question) {
    return new Promise((resolve) => {
        rl.question(question, resolve);
    });
}

function elapsedMilliseconds(startTime) {
    return Number(process.hrtime.bigint() - startTime) / 1_000_000;
}

async function singleReviewMode() {

    const review =
        await ask(
            "\nEnter review:\n> "
        );


    if (
        !review.trim()
    ) {

        console.log(
            "No review entered."
        );

        return;
    }


    const startTime = process.hrtime.bigint();

    const result =
        service.classifyReview(
            review
        );

    const processingTime = elapsedMilliseconds(startTime);


    service.displayReviewResult(
        result
    );

    console.log(
        `\nProcessing time: ${processingTime.toFixed(3)} ms`
    );
}


// ============================================================
// MULTIPLE REVIEW TEST
// ============================================================

async function placeMode() {

    console.log("");

    console.log(
        "Enter reviews one by one."
    );

    console.log(
        "Press ENTER on an empty line when finished."
    );

    console.log("");


    const reviews = [];


    while (true) {

        const review =
            await ask(
                `Review ${reviews.length + 1}: `
            );


        if (
            !review.trim()
        ) {

            break;
        }


        reviews.push(
            review.trim()
        );
    }


    if (
        reviews.length === 0
    ) {

        console.log(
            "No reviews entered."
        );

        return;
    }


    console.log("");

    console.log(
        `Processing ${reviews.length} reviews...`
    );


    const startTime = process.hrtime.bigint();

    const result =
        service.aggregatePlace(
            reviews
        );

    const processingTime = elapsedMilliseconds(startTime);


    service.displayPlaceResult(
        result
    );

    console.log(
        `\nProcessing time: ${processingTime.toFixed(3)} ms `
        + `(${(processingTime / reviews.length).toFixed(3)} ms/review)`
    );
}


// ============================================================
// MAIN
// ============================================================

async function main() {

    const programStartTime = process.hrtime.bigint();

    console.log("");

    console.log(
        "============================================================"
    );

    console.log(
        " AUTOMATIC ATTRACTION TAGGING SERVICE"
    );

    console.log(
        "============================================================"
    );

    console.log(
        "Rule-Based NLP"
    );

    console.log(
        "Keyword + Phrase + Synonym + N-gram"
    );

    console.log(
        "+ Context + Negation + Weighted Scoring"
    );

    console.log(
        "============================================================"
    );


    while (true) {

        console.log("");

        console.log(
            "1. Test one review"
        );

        console.log(
            "2. Test multiple reviews for one attraction"
        );

        console.log(
            "3. Exit"
        );


        const choice =
            await ask(
                "\nSelect option: "
            );


        switch (
            choice
        ) {

            case "1":

                await singleReviewMode();

                break;


            case "2":

                await placeMode();

                break;


            case "3":

                rl.close();

                console.log(
                    "\nTagging service stopped."
                );

                console.log(
                    `Total runtime: ${(
                        elapsedMilliseconds(programStartTime) / 1000
                    ).toFixed(3)} s`
                );

                return;


            default:

                console.log(
                    "Invalid option."
                );
        }
    }
}
module.exports = {
    TaggingService,
    GENERAL_TAGS,
    CULTURAL_TAGS
};

if (require.main === module) {
    rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    });

    main().catch((error) => {
        console.error(error);
        rl.close();
        process.exitCode = 1;
    });
}
