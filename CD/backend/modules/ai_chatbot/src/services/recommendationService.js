const { ATTRACTION_TAGS } = require('../config/attractionTags');

const canonicalTags = new Map(ATTRACTION_TAGS.map((tag) => [tag.toLocaleLowerCase('en'), tag]));

function cleanCanonicalPreferences(values) {
  const result = [];
  const seen = new Set();
  for (const value of Array.isArray(values) ? values : []) {
    const tag = canonicalTags.get(String(value || '').trim().toLocaleLowerCase('en'));
    if (tag && !seen.has(tag)) {
      seen.add(tag);
      result.push(tag);
    }
  }
  return result;
}

function selectPreferences({ requirements, profile }) {
  const explicit = cleanCanonicalPreferences(requirements);
  if (explicit.length) return { values: explicit, source: 'current_request' };
  const saved = cleanCanonicalPreferences(profile?.favorite_categories);
  if (saved.length) return { values: saved, source: 'traveler_profile' };
  return { values: [], source: 'none' };
}

function compactTaggedPlace(item) {
  const place = item?.place || {};
  const ranking = item?.ranking || {};
  return {
    rank: Number(item?.rank) || null,
    place: {
      id: String(place.id || ''),
      displayName: { text: String(place.displayName?.text || '') },
      formattedAddress: String(place.formattedAddress || ''),
      location: place.location || null,
      googleMapsUri: String(place.googleMapsUri || ''),
      description: place.description || null,
      rating: Number.isFinite(Number(place.rating)) ? Number(place.rating) : null,
      primaryType: place.primaryType || null,
      primaryTypeDisplayName: place.primaryTypeDisplayName || place.primaryType || null,
      types: Array.isArray(place.types) ? place.types.slice(0, 20) : [],
      photo: place.photo?.name ? { name: String(place.photo.name) } : null,
      photos: Array.isArray(place.photos)
        ? place.photos.slice(0, 9)
          .filter((photo) => photo?.name)
          .map((photo) => ({ name: String(photo.name) }))
        : [],
      distanceMetres: place.distanceMetres ?? null,
      distanceKm: place.distanceKm ?? null,
      routeDistanceMetres: place.routeDistanceMetres ?? null,
      routeDistanceKm: place.routeDistanceKm ?? null,
      etaMinutes: place.etaMinutes ?? null,
      etaEstimated: place.etaEstimated === true,
      directionsUri: place.directionsUri || null,
    },
    analysis: {
      generalTags: Array.isArray(item?.analysis?.generalTags) ? item.analysis.generalTags.slice(0, 20) : [],
      culturalTags: Array.isArray(item?.analysis?.culturalTags) ? item.analysis.culturalTags.slice(0, 20) : [],
    },
    matchedPreferences: Array.isArray(item?.matchedPreferences) ? item.matchedPreferences.slice(0, 20) : [],
    ranking: {
      finalScore: ranking.finalScore ?? 0,
      similarityPercentage: ranking.similarityPercentage ?? 0,
      matchingTags: Array.isArray(ranking.matchingTags) ? ranking.matchingTags.slice(0, 20) : [],
    },
  };
}

async function getRecommendations(options) {
  const latitude = Number(options?.latitude);
  const longitude = Number(options?.longitude);
  const selected = selectPreferences(options || {});
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return { success: false, unavailable: true, code: 'CURRENT_LOCATION_REQUIRED', recommendations: [] };
  }
  if (!selected.values.length) {
    return { success: false, unavailable: true, code: 'PREFERENCES_REQUIRED', recommendations: [] };
  }
  const baseUrl = String(process.env.RECOMMENDATION_BACKEND_URL || 'http://127.0.0.1:3000').replace(/\/$/, '');
  try {
    const response = await fetch(`${baseUrl}/api/recommendations/nearby-tagged`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ latitude, longitude, mode: 'preferences', preferences: selected.values }),
      signal: AbortSignal.timeout(20000),
    });
    const data = await response.json();
    if (!response.ok) throw new Error(data?.details || data?.error || `HTTP ${response.status}`);
    return {
      success: true,
      destination: String(options?.destination || ''),
      origin: data.origin || { latitude, longitude },
      applied_preferences: data.preferences || selected.values,
      preference_source: selected.source,
      recommendations: (data.matchedPlaces || []).map(compactTaggedPlace),
      provider: 'preference_recommender',
    };
  } catch (error) {
    return { success: false, unavailable: true, code: 'RECOMMENDER_UNAVAILABLE', recommendations: [], provider_error: String(error?.message || error) };
  }
}

module.exports = { getRecommendations, selectPreferences };
