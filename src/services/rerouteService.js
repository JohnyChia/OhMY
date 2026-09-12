const itineraryService = require("./itineraryService");
const tripStateService = require("./tripStateService");

async function rerouteItinerary(user_id, reason, avoidLocations = []) {
  console.log(`Rerouting trip for user ${user_id} due to: ${reason}. Avoiding: ${avoidLocations.join(", ")}`);
  const state = await tripStateService.getTripState(user_id);
  if (!state || !state.destination) {
    return { success: false, message: "No active trip to reroute." };
  }

  const updatedState = await tripStateService.updateTripState(user_id, {
    reset_itinerary: true,
    avoid_locations: avoidLocations
  });
  const updatedItinerary = await itineraryService.generateItinerary(user_id);

  return {
    success: true,
    action: "Reroute completed successfully.",
    avoid_locations_applied: updatedState.avoid_locations,
    itinerary: updatedItinerary
  };
}

module.exports = {
  rerouteItinerary
};
