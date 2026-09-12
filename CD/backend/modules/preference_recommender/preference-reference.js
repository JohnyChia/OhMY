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

    const uniqueNames = [
        ...new Set(
            requestedPreferences
                .map(tag => String(tag).trim())
                .filter(Boolean)
        )
    ];

    return {
        generalTags: uniqueNames.filter(
            tag => generalTags.includes(tag)
        ),
        culturalTags: uniqueNames.filter(
            tag => culturalTags.includes(tag)
        )
    };
}

module.exports = { splitSupportedPreferences };
