const rerouteService = require("../services/rerouteService");

async function execute(user_id, params) {
  const reason = params.reason || "Traffic / Weather delay";
  let avoidLocations = params.avoid_locations || [];
  if (typeof avoidLocations === "string") avoidLocations = [avoidLocations];

  return await rerouteService.rerouteItinerary(user_id, reason, avoidLocations);
}

module.exports = {
  execute
};
