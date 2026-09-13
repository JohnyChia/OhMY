const recommendationService = require("../services/recommendationService");

async function get(params, userProfile = {}, context = {}) {
  const requestedDestination = String(params.destination || "").trim();
  const latitude = Number(params.latitude ?? context?.current_location?.latitude);
  const longitude = Number(params.longitude ?? context?.current_location?.longitude);
  const hasCurrentLocation = Number.isFinite(latitude) && Number.isFinite(longitude);
  let destination = requestedDestination;
  if (requestedDestination) {
    const geoResolver = require('../utils/geoResolver');
    const resolution = await geoResolver.resolveDestination(requestedDestination, context);
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
    if (Number.isFinite(Number(resolution.latitude)) &&
        Number.isFinite(Number(resolution.longitude))) {
      params.latitude = Number(resolution.latitude);
      params.longitude = Number(resolution.longitude);
    }
  }
  const requirements = [
    ...(Array.isArray(params.requirements) ? params.requirements : []),
    ...(Array.isArray(params.interest) ? params.interest : []),
    ...(params.category ? [params.category] : []),
  ];

  let excluded = params.excluded_requirements || params.excluded_locations || [];
  if (typeof excluded === "string") {
    excluded = [excluded];
  }

  // The agent receives this profile from User Management, so recommendations
  // stay personalised even when the user only asks a short follow-up.
  const data = await recommendationService.getRecommendations({
    destination,
    requirements,
    excludedRequirements: excluded,
    profile: userProfile,
    latitude: Number.isFinite(Number(params.latitude)) ? Number(params.latitude) : (hasCurrentLocation ? latitude : undefined),
    longitude: Number.isFinite(Number(params.longitude)) ? Number(params.longitude) : (hasCurrentLocation ? longitude : undefined),
  });
  return {
    ...data,
    display_destination: destination,
    requested_destination: requestedDestination,
  };
}

module.exports = {
  get
};
