const MALAY_TO_ENGLISH_PHRASES = [
    ["seni bina tradisional", "traditional architecture"],
    ["bangunan bersejarah", "historic building"],
    ["tempat bersejarah", "historical place"],
    ["warisan agama", "religious heritage"],
    ["warisan budaya", "cultural heritage"],
    ["makanan tempatan", "local cuisine"],
    ["makanan tradisional", "traditional food"],
    ["kraf tradisional", "traditional craft"],
    ["belajar budaya", "cultural learning"],
    ["pengalaman budaya", "cultural experience"],
    ["muzium", "museum"],
    ["warisan", "heritage"],
    ["sejarah", "history"],
    ["budaya", "culture"],
    ["tradisional", "traditional"],
    ["masjid", "mosque"],
    ["kuil", "temple"],
    ["gereja", "church"],
    ["pasar", "market"],
    ["taman", "park"],
    ["alam semula jadi", "nature"]
];

function languageRoot(languageCode) {
    return String(languageCode || "und")
        .trim()
        .toLowerCase()
        .split("-")[0];
}

function appendMalayAliases(text) {
    const normalized = String(text || "").toLowerCase();
    const aliases = MALAY_TO_ENGLISH_PHRASES
        .filter(([phrase]) => normalized.includes(phrase))
        .map(([, english]) => english);
    return aliases.length > 0
        ? `${text} ${[...new Set(aliases)].join(" ")}`
        : text;
}

function informativenessWeight(text) {
    const tokenCount = (String(text).match(/[\p{L}\p{N}'-]+/gu) || []).length;
    if (tokenCount >= 35) return 1.2;
    if (tokenCount >= 18) return 1.1;
    if (tokenCount >= 8) return 1;
    return 0.8;
}

function recencyWeight(publishTime, now = Date.now()) {
    const published = Date.parse(publishTime || "");
    if (!Number.isFinite(published)) return 0.9;
    const ageDays = Math.max(0, (now - published) / 86_400_000);
    if (ageDays <= 365) return 1;
    if (ageDays <= 730) return 0.92;
    return 0.85;
}

function languageConfidence(languageCode) {
    const language = languageRoot(languageCode);
    if (language === "en") return 1;
    if (language === "ms") return 0.9;
    return 0.7;
}

function normalizeGoogleReviews(reviews, now = Date.now()) {
    const languageSummary = {};
    let unsupportedCount = 0;
    const normalizedReviews = [];

    for (const review of reviews || []) {
        const localized = review?.text || {};
        const original = review?.originalText || {};
        const text = String(localized.text || "").trim();
        if (!text) continue;

        const languageCode = localized.languageCode || "und";
        const originalLanguageCode = original.languageCode || languageCode;
        const language = languageRoot(languageCode);
        languageSummary[language] = (languageSummary[language] || 0) + 1;

        // Place Details is explicitly requested in English. If Google still
        // returns another language, Tagger V2 currently supports Malay rules
        // and safely excludes other languages from lexical classification.
        if (language !== "en" && language !== "ms") {
            unsupportedCount++;
            continue;
        }

        const taggableText = language === "ms"
            ? appendMalayAliases(text)
            : text;
        const weight = Math.max(
            0.5,
            Math.min(
                1.2,
                informativenessWeight(taggableText)
                    * recencyWeight(review.publishTime, now)
                    * languageConfidence(languageCode)
            )
        );
        normalizedReviews.push({
            text: taggableText,
            weight: Number(weight.toFixed(3)),
            languageCode,
            originalLanguageCode,
            rating: Number.isFinite(review.rating) ? review.rating : null,
            publishTime: review.publishTime || null
        });
    }

    return {
        reviews: normalizedReviews,
        languageSummary: {
            ...languageSummary,
            unsupported: unsupportedCount,
            usable: normalizedReviews.length,
            received: (reviews || []).length
        }
    };
}

module.exports = {
    MALAY_TO_ENGLISH_PHRASES,
    languageRoot,
    appendMalayAliases,
    normalizeGoogleReviews,
    informativenessWeight,
    recencyWeight,
    languageConfidence
};
