// Nova is a client of the existing preference_recommender module. It does not
// modify provider search or preference ranking; this adapter consumes existing
// endpoints and enforces Nova's current request constraints locally.

const { requestTags, matchesRequest } = require('./requestTagService');

function cleanList(values) {
  return [...new Set((Array.isArray(values) ? values : [])
    .map((value) => String(value || '').trim())
    .filter(Boolean))];
}

function packageRecommendationRequest(options) {
  const explicit = cleanList(options?.requirements);
  const explicitQuery = explicit
    .join(' ')
    .replace(/\bcuisine\b/gi, 'restaurant')
    .replace(/\bfood\b/gi, 'restaurant')
    .replace(/\s+/g, ' ')
    .trim();
  const selected = selectPreferences(options || {});
  return {
    nearbyForYou: {
      latitude: Number(options?.latitude),
      longitude: Number(options?.longitude),
      mode: 'preferences',
      preferences: selected.values,
    },
    explicit,
    explicitQuery,
    preferenceSource: selected.source,
  };
}

function selectPreferences({ requirements, profile }) {
  const saved = cleanList(profile?.favorite_categories);
  if (saved.length) return { values: saved, source: 'traveler_profile' };

  const explicit = cleanList(requirements);
  if (explicit.length) return { values: explicit, source: 'current_request' };

  return { values: [], source: 'traveler_profile' };
}

function recommenderUrl() {
  const base = String(
    process.env.PREFERENCE_RECOMMENDER_URL || 'http://127.0.0.1:3000',
  ).replace(/\/+$/, '');
  return `${base}/api/recommendations/nearby-tagged`;
}

function placeSearchUrl() {
  return recommenderUrl().replace('/api/recommendations/nearby-tagged', '/api/places/search');
}

function recommendationCard(item) {
  const place = item?.place || {};
  const name = String(place.displayName?.text || '').trim();
  if (!name) return null;
  return {
    id: String(place.id || ''),
    name,
    address: String(place.formattedAddress || '').trim(),
    mapsUrl: String(place.googleMapsUri || '').trim(),
    types: Array.isArray(place.types) ? place.types.map(String) : [],
    location: place.location || null,
    rating: Number.isFinite(Number(place.rating)) ? Number(place.rating) : null,
    distanceKm: Number.isFinite(Number(place.routeDistanceKm))
      ? Number(place.routeDistanceKm)
      : Number.isFinite(Number(place.distanceKm)) ? Number(place.distanceKm) : null,
    etaMinutes: Number.isFinite(Number(place.etaMinutes))
      ? Number(place.etaMinutes)
      : null,
    photo: place.photo || null,
    matchedPreferences: cleanList(item.matchedPreferences),
    recommendationScore: Number.isFinite(Number(item.ranking?.score))
      ? Number(item.ranking.score)
      : null,
  };
}

async function requestRankedRecommendations(body, dependencies = {}) {
  const request = dependencies.fetch || fetch;
  const configuredTimeout = Number(process.env.NOVA_RECOMMENDER_TIMEOUT_MS);
  const timeoutMs = Number.isFinite(configuredTimeout) && configuredTimeout > 0
    ? configuredTimeout
    : 12000;
  const response = await request(recommenderUrl(), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const payload = await response.json();
  if (!response.ok) {
    const error = new Error(payload?.error || `Preference recommender HTTP ${response.status}`);
    error.status = response.status;
    throw error;
  }
  return payload;
}

async function requestExplicitPlaceSearch({ query, latitude, longitude }, dependencies = {}) {
  const request = dependencies.fetch || fetch;
  const response = await request(placeSearchUrl(), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      query,
      latitude,
      longitude,
      radiusMeters: 10000,
      placesOnly: true,
    }),
    signal: AbortSignal.timeout(12000),
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload?.error || `Place search HTTP ${response.status}`);
  }
  const words = cleanList(String(query).toLowerCase().split(/\s+/))
    .filter((word) => !['cuisine', 'food', 'restaurant', 'nearby'].includes(word));
  const radians = (value) => value * Math.PI / 180;
  const kilometresFromOrigin = (place) => {
    const location = place?.location || {};
    if (!Number.isFinite(location.latitude) || !Number.isFinite(location.longitude)) return Infinity;
    const latitudeDelta = radians(location.latitude - latitude);
    const longitudeDelta = radians(location.longitude - longitude);
    const value = Math.sin(latitudeDelta / 2) ** 2
      + Math.cos(radians(latitude)) * Math.cos(radians(location.latitude))
        * Math.sin(longitudeDelta / 2) ** 2;
    return 6371 * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value));
  };
  return (payload.places || [])
    .filter((place) => kilometresFromOrigin(place) <= 10)
    .filter((place) => {
      if (!/\b(?:restaurant|food|cuisine)\b/i.test(query)) return true;
      return [place.primaryType, ...(place.types || [])].filter(Boolean).some((type) =>
        /restaurant|cafe|meal_takeaway|meal_delivery|food_court/.test(type));
    })
    .filter((place) => {
      const constraints = requestTags(query);
      if (constraints.length && constraints.some(constraint =>
          constraint.query.toLowerCase() === String(query).toLowerCase().trim())) {
        return matchesRequest(place, constraints);
      }
      if (!words.length) return true;
      const searchable = [
        place.displayName?.text,
        place.formattedAddress,
        place.primaryTypeDisplayName?.text,
        ...(place.types || []),
      ].join(' ').toLowerCase();
      return words.every((word) => searchable.includes(word));
    })
    .sort((left, right) => kilometresFromOrigin(left) - kilometresFromOrigin(right))
    .map((place) => recommendationCard({ place: {
      ...place,
      distanceKm: kilometresFromOrigin(place),
    } }))
    .filter(Boolean)
    .slice(0, 5);
}

async function getRecommendations(options, dependencies = {}) {
  const destination = String(options?.destination || '').trim();
  const latitude = Number(options?.latitude);
  const longitude = Number(options?.longitude);
  if (!destination || !Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return {
      success: false,
      unavailable: true,
      code: 'DESTINATION_REQUIRED',
      recommendations: [],
    };
  }

  const packaged = packageRecommendationRequest(options);
  const constraints = requestTags(packaged.explicit.join(' '));
  const unverifiedConstraints = packaged.explicit.filter(value =>
    /\b(?:halal|wheelchair|accessible|accessibility|cheap|budget|quiet|open now|indoor|parking)\b|无障碍|清真|便宜|室内/i.test(value));
  const excluded = requestTags(cleanList(options.excludedRequirements).join(' '));
  const excludedText = cleanList(options.excludedRequirements);
  const semanticQuery = typeof options.searchQuery === 'string'
    ? options.searchQuery.trim().slice(0, 240) : '';
  const dynamicQuery = semanticQuery || (constraints.length
    ? [...new Set(packaged.explicit.map(value => {
        const tags = requestTags(value);
        return tags.length ? tags.map(tag => tag.query).join(' ') : value;
      }))].join(' ') : packaged.explicitQuery);
  if (packaged.explicit.length || semanticQuery) {
    try {
      const searched = await requestExplicitPlaceSearch({
        query: dynamicQuery,
        latitude,
        longitude,
      }, dependencies);
      const recommendations = searched.filter(place => {
        const metadata = [place.name, ...place.types].join(' ').toLowerCase().replace(/_/g, ' ');
        return !excluded.some(constraint => matchesRequest({
          displayName: { text: place.name }, types: place.types,
        }, [constraint])) && !excludedText.some(value => metadata.includes(value.toLowerCase()));
      });
      return {
        success: true,
        destination,
        recommendations,
        request_tags: constraints.map((constraint) => constraint.tag),
        applied_preferences: [],
        preference_source: 'current_request',
        request_requirements: packaged.explicit,
        provider: 'nearby_place_search',
        ranked: false,
        radiusMetres: 10000,
        search_query: dynamicQuery,
        matching_evidence: 'Provider search, venue metadata and distance; not independent verification of every requested attribute.',
        unverified_constraints: unverifiedConstraints,
        unverified_exclusions: excludedText,
        limitations: unverifiedConstraints.length
          ? 'These options match the requested category and distance only. Additional requirements are not verified; do not claim they are satisfied.' : '',
      };
    } catch (error) {
      return { success: false, unavailable: true, recommendations: [],
        code: 'NEARBY_SEARCH_UNAVAILABLE', error: String(error.message) };
    }
  }
  const selected = {
    values: packaged.nearbyForYou.preferences,
    source: packaged.preferenceSource,
  };
  if (!selected.values.length) {
    return {
      success: false,
      unavailable: true,
      code: 'PREFERENCES_REQUIRED',
      destination,
      recommendations: [],
      error: 'Complete your travel preferences before asking for personalised recommendations.',
    };
  }

  try {
    const data = await requestRankedRecommendations(packaged.nearbyForYou, dependencies);
    const recommendations = (data.matchedPlaces || [])
      .map(recommendationCard)
      .filter(Boolean)
      .slice(0, 5);
    const explicitRequirements = cleanList(options?.requirements);
    const foodRequest = /\b(?:food|cuisine|restaurant)\b/i.test(packaged.explicitQuery)
      || /\b(?:food|cuisine|restaurant)\b/i.test(explicitRequirements.join(' '));
    const searchedRecommendations = (recommendations.length === 0 || foodRequest)
      && explicitRequirements.length > 0
      ? await requestExplicitPlaceSearch({
          query: packaged.explicitQuery,
          latitude,
          longitude,
        }, dependencies)
      : [];
    const finalRecommendations = recommendations.length && !foodRequest
      ? recommendations
      : searchedRecommendations;
    return {
      success: true,
      destination,
      applied_preferences: selected.values,
      preference_source: selected.source,
      request_requirements: explicitRequirements,
      recommendations: finalRecommendations,
      provider: searchedRecommendations.length
        ? 'preference_recommender+place_search'
        : 'preference_recommender',
      ranked: data.ranked === true,
      taggerVersion: data.taggerVersion || null,
      radiusMetres: data.radiusMetres || null,
    };
  } catch (error) {
    return {
      success: false,
      unavailable: true,
      code: 'PREFERENCE_RECOMMENDER_UNAVAILABLE',
      destination,
      applied_preferences: selected.values,
      preference_source: selected.source,
      request_requirements: cleanList(options?.requirements),
      recommendations: [],
      provider: 'preference_recommender',
      provider_error: String(error?.message || error),
    };
  }
}

module.exports = {
  getRecommendations,
  selectPreferences,
  recommendationCard,
  requestRankedRecommendations,
  requestExplicitPlaceSearch,
  packageRecommendationRequest,
};
