function splitSupportedPreferences(
    requestedPreferences,
    generalTags,
    culturalTags
) {
    if (
        !Array.isArray(requestedPreferences)
        || requestedPreferences.length === 0
    ) {
        return null;
    }

    const canonicalGeneralTags = new Map(
        generalTags.map(tag => [tag.toLocaleLowerCase("en"), tag])
    );
    const canonicalCulturalTags = new Map(
        culturalTags.map(tag => [tag.toLocaleLowerCase("en"), tag])
    );
    const uniqueNames = [];
    const seenNames = new Set();

    for (const requestedTag of requestedPreferences) {
        const normalizedName = String(requestedTag).trim();
        const comparisonName = normalizedName.toLocaleLowerCase("en");
        const canonicalName = canonicalGeneralTags.get(comparisonName)
            ?? canonicalCulturalTags.get(comparisonName);

        if (canonicalName && !seenNames.has(canonicalName)) {
            seenNames.add(canonicalName);
            uniqueNames.push(canonicalName);
        }
    }

    return {
        generalTags: uniqueNames.filter(
            tag => canonicalGeneralTags.has(tag.toLocaleLowerCase("en"))
        ),
        culturalTags: uniqueNames.filter(
            tag => canonicalCulturalTags.has(tag.toLocaleLowerCase("en"))
        )
    };
}

module.exports = { splitSupportedPreferences };
