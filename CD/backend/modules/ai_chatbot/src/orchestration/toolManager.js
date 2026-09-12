const tripTool =
require("../tools/tripTool");


const modifyTripTool =
require("../tools/modifyTripTool");


const profileTool =
require("../tools/profileTool");


const itineraryService =
require("../services/itineraryService");


const weatherTool =
require("../tools/weatherTool");


const recommendationTool =
require("../tools/recommendationTool");


const trafficTool =
require("../tools/trafficTool");


const tripStateService =
require("../services/tripStateService");

const rerouteTool =
require("../tools/rerourteTool");

const communityTool = require("../tools/communityTool");
const savedTravelItemService = require("../services/savedTravelItemService");
const linkAnalysisService = require("../services/linkAnalysisService");

function applyContextDestination(intent, context) {
  if (intent.parameters.destination) return;
  const destination = context?.session_context?.location?.destination;
  if (typeof destination === 'string' && destination.trim()) {
    intent.parameters.destination = destination;
  }
}




async function executeTool(
intent,
user_id,
context
)
{


switch(intent.tool)
{


case "create_trip":

return await tripTool.createTrip(
user_id,
intent.parameters,
context
);


case "update_trip":
{

return await modifyTripTool.update(
user_id,
intent.parameters,
context
);


}







case "generate_itinerary":


return await itineraryService.generateItinerary(
user_id
);







case "update_profile":


return await profileTool.update(
user_id,
intent.profile_update || intent.parameters
);










case "weather":
{
  applyContextDestination(intent, context);
  if (!intent.parameters.destination) {
    const state = await tripStateService.getTripState(user_id);
    if (state && state.destination) intent.parameters.destination = state.destination;
  }
  return await weatherTool.get(intent.parameters);
}

case "recommendation":
{
  applyContextDestination(intent, context);
  if (!intent.parameters.destination) {
    const state = await tripStateService.getTripState(user_id);
    if (state && state.destination) intent.parameters.destination = state.destination;
  }
  return await recommendationTool.get(
    intent.parameters,
    context?.traveler_profile || {},
    context,
  );
}

case "discover_community":
  return await communityTool.get(intent.parameters);

case "show_location":
{
  const rawDestination = String(intent.parameters.destination || "").trim();
  if (!rawDestination) {
    return { success: false, unavailable: true, error: "A location is required." };
  }
  const geoResolver = require("../utils/geoResolver");
  const resolution = await geoResolver.resolveDestination(rawDestination, context);
  if (resolution.status !== "RESOLVED") {
    return {
      success: false,
      unavailable: true,
      code: resolution.status,
      error: resolution.status === "OUT_OF_SCOPE"
        ? "Nova only supports map locations within Malaysia."
        : `The location could not be verified: ${rawDestination}.`,
    };
  }
  return {
    success: true,
    destination: resolution.canonical,
    resolution_metadata: resolution,
  };
}

case "show_attachment_location":
{
  const analysis = context?.attachment?.analysis;
  const destination = String(
    analysis?.locationHint || analysis?.normalizedContext?.locationHint || "",
  ).trim();
  if (!destination || context?.attachment?.analysisStatus !== "ready") {
    return { success: false, error: "ATTACHMENT_LOCATION_UNAVAILABLE" };
  }
  return { success: true, destination, attachment_only: true };
}

case "save_travel_item":
  return await savedTravelItemService.save(user_id, intent.parameters, context);

case "list_saved_travel_items":
  return await savedTravelItemService.list(user_id, intent.parameters.limit);

case "delete_saved_travel_item":
  return await savedTravelItemService.remove(user_id, intent.parameters.item_id);

case "analyze_link":
  return await linkAnalysisService.analyze(intent.parameters.url);

case "traffic":
{
  applyContextDestination(intent, context);
  if (!intent.parameters.destination) {
    const state = await tripStateService.getTripState(user_id);
    if (state && state.destination) intent.parameters.destination = state.destination;
  }
  return await trafficTool.get(intent.parameters);
}


case "reroute":
{
  // Do not mutate the itinerary as a side effect of an AI suggestion. The
  // existing Recommendation/Route owner remains responsible for presenting
  // verified alternatives after the traveller confirms the handoff.
  const state = await tripStateService.getTripState(user_id);
  if (!state?.destination) {
    return { success: false, error: "No active trip to reroute." };
  }
  return {
    success: true,
    proposal: true,
    destination: state.destination,
    reason: String(intent.parameters.reason || "Traffic or weather disruption"),
    avoid_locations: Array.isArray(intent.parameters.avoid_locations)
      ? intent.parameters.avoid_locations
      : [],
  };
}






default:

return null;



}



}





module.exports={
executeTool
};
