// Reuse the Google Places implementation already used by the Map owner. Nova
// only adapts its verified output; it never manufactures venues or ratings.
const { searchPlaces } = require('../../../../googlePlacesService');

function cleanList(values) {
  return [...new Set((Array.isArray(values) ? values : [])
    .map((value) => String(value || '').trim())
    .filter(Boolean))];
}

function selectPreferences({ requirements, profile }) {
  const explicit = cleanList(requirements);
  if (explicit.length) return { values: explicit, source: 'current_request' };

  const saved = cleanList(profile?.favorite_categories);
  if (saved.length) return { values: saved, source: 'traveler_profile' };

  return { values: [], source: 'destination' };
}

function buildSearchQuery(destination, preferences) {
  const preferenceText = cleanList(preferences).join(' ');
  return preferenceText
    ? `travel places matching ${preferenceText} in ${destination}`
    : `travel places in ${destination}`;
}

async function getRecommendations(options, dependencies = {}) {
  const destination = String(options?.destination || '').trim();
  if (!destination) {
    return {
      success: false,
      unavailable: true,
      code: 'DESTINATION_REQUIRED',
      recommendations: [],
    };
  }

  const selected = selectPreferences(options || {});
  const excluded = cleanList(options?.excludedRequirements);
  const query = buildSearchQuery(destination, selected.values);
  const placeSearch = dependencies.searchPlaces || searchPlaces;

  try {
    const data = await placeSearch(query);
    const recommendations = (data.places || []).map((place) => ({
      id: String(place.id || ''),
      name: String(place.displayName?.text || '').trim(),
      address: String(place.formattedAddress || '').trim(),
      mapsUrl: String(place.googleMapsUri || '').trim(),
      types: Array.isArray(place.types) ? place.types.map(String) : [],
      location: place.location || null,
      rating: Number.isFinite(Number(place.rating)) ? Number(place.rating) : null,
      ratingCount: Number.isFinite(Number(place.userRatingCount))
        ? Number(place.userRatingCount)
        : null,
    })).filter((place) => {
      if (!place.name) return false;
      if (!excluded.length) return true;
      const searchable = [place.name, place.address, ...place.types]
        .join(' ')
        .toLocaleLowerCase();
      return !excluded.some((value) => searchable.includes(value.toLocaleLowerCase()));
    }).slice(0, 5);
    return {
      success: true,
      destination,
      applied_preferences: selected.values,
      preference_source: selected.source,
      excluded_requirements: excluded,
      recommendations,
      provider: 'Google Places API',
    };
  } catch (error) {
    return {
      success: false,
      unavailable: true,
      code: 'PLACE_PROVIDER_UNAVAILABLE',
      destination,
      applied_preferences: selected.values,
      preference_source: selected.source,
      recommendations: [],
      provider_error: String(error?.message || error),
    };
  }
}

module.exports = {
  getRecommendations,
  selectPreferences,
  buildSearchQuery,
};
