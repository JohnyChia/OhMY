const recommendationService = require("../services/recommendationService");
const { requestTags } = require('../services/requestTagService');

function deviceLocation(context) {
  const value = context?.session_context?.device_location || {};
  const latitude = Number(value.latitude);
  const longitude = Number(value.longitude);
  return Number.isFinite(latitude) && Number.isFinite(longitude)
    ? { latitude, longitude }
    : null;
}

async function get(params, userProfile = {}, context = {}, dependencies = {}) {
  const message = String(context.current_message || '').toLowerCase();
  const nearMe = /\b(?:near me|nearby|around me|my area|current location|dekat saya|sekitar saya)\b|附近|附近的|我这里/.test(message);
  const refersBack = /\b(?:there|that stop|that place|di sana|situ)\b|那里|那边/.test(message);
  let requestedDestination = String(params.destination || '').trim();
  if (message && (nearMe || (!refersBack &&
      !message.includes(requestedDestination.toLowerCase())))) {
    requestedDestination = '';
  }
  if (!nearMe && refersBack && !requestedDestination) {
    requestedDestination = String(context?.session_context?.location?.destination || '').trim();
  }
  let destination = requestedDestination || 'your current location';
  let resolution = null;
  if (requestedDestination) {
    const geoResolver = dependencies.geoResolver || require('../utils/geoResolver');
    resolution = await geoResolver.resolveDestination(requestedDestination, context);
    if (resolution.status !== 'RESOLVED') {
      return {
        success: false,
        unavailable: true,
        code: resolution.status,
        destination: requestedDestination,
        recommendations: [],
        error: resolution.status === 'OUT_OF_SCOPE'
          ? `The destination ${requestedDestination} is outside Malaysia.`
          : `The destination could not be verified: ${requestedDestination}.`,
      };
    }
    destination = resolution.canonical;
  }
  const currentLocation = deviceLocation(context);
  if (!requestedDestination && !currentLocation) {
    return {
      success: false,
      unavailable: true,
      code: 'CURRENT_LOCATION_REQUIRED',
      recommendations: [],
      error: 'Your current location is unavailable. Enable location access or name an area to search.',
    };
  }
  const currentRequestTags = requestTags(context.current_message);
  const requirements = [...new Set([
    ...currentRequestTags.map(tag => tag.query),
    ...(Array.isArray(params.requirements) ? params.requirements : []),
    ...(Array.isArray(params.interest) ? params.interest : []),
    ...(params.category ? [params.category] : []),
  ])];

  let excluded = params.excluded_requirements || params.excluded_locations || [];
  if (typeof excluded === "string") {
    excluded = [excluded];
  }

  // The agent receives this profile from User Management, so recommendations
  // stay personalised even when the user only asks a short follow-up.
  const service = dependencies.recommendationService || recommendationService;
  const data = await service.getRecommendations({
    destination,
    latitude: resolution?.latitude ?? currentLocation?.latitude,
    longitude: resolution?.longitude ?? currentLocation?.longitude,
    requirements,
    searchQuery: params.search_query,
    excludedRequirements: excluded,
    profile: userProfile,
  });
  return {
    ...data,
    display_destination: destination,
    requested_destination: requestedDestination,
  };
}

module.exports = {
  get,
  deviceLocation,
};
