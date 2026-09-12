const recommendationService = require("../services/recommendationService");

async function get(params, userProfile = {}, context = {}) {
  const requestedDestination = String(params.destination || "").trim();
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
