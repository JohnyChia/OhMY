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
const { searchPlaces } = require('../../../preference_recommender/googlePlacesService');

function applyContextDestination(intent, context) {
  if (intent.parameters.destination) return;
  const destination = context?.session_context?.location?.destination;
  if (typeof destination === 'string' && destination.trim()) {
    intent.parameters.destination = destination;
  }
}

async function resolveMapDestination(rawDestination, context) {
  const latitude = Number(context?.current_location?.latitude);
  const longitude = Number(context?.current_location?.longitude);
  const hasCurrentLocation = Number.isFinite(latitude) && Number.isFinite(longitude);
  try {
    const result = await searchPlaces(rawDestination, hasCurrentLocation
      ? { latitude, longitude }
      : {});
    const place = (result.places || []).find((candidate) =>
      typeof candidate?.displayName?.text === 'string' &&
      candidate.displayName.text.trim());
    if (place) {
      let resolvedPlaces = result.places || [];
      const areaTypes = new Set([
        'administrative_area_level_1',
        'administrative_area_level_2',
        'administrative_area_level_3',
        'locality',
        'sublocality',
        'postal_town',
      ]);
      const isArea = Array.isArray(place.types) &&
        place.types.some((type) => areaTypes.has(type));
      if (isArea) {
        try {
          const areaResults = await searchPlaces(
            `points of interest in ${place.displayName.text.trim()}`,
          );
          if (Array.isArray(areaResults.places) && areaResults.places.length) {
            resolvedPlaces = areaResults.places;
          }
        } catch (areaError) {
          console.warn('[Nova map] Area place search unavailable:', areaError.message);
        }
      }
      const places = resolvedPlaces.filter((candidate) =>
        candidate?.displayName?.text && candidate?.location,
      ).map((candidate) => ({
        id: String(candidate.id || ''),
        name: String(candidate.displayName.text),
        address: String(candidate.formattedAddress || ''),
        mapsUrl: String(candidate.googleMapsUri || ''),
        types: Array.isArray(candidate.types) ? candidate.types.map(String) : [],
        location: candidate.location,
      }));
      return {
        status: 'RESOLVED',
        canonical: place.displayName.text.trim(),
        original_input: rawDestination,
        resolved_destination: place.displayName.text.trim(),
        corrected: place.displayName.text.trim().toLocaleLowerCase() !==
          rawDestination.toLocaleLowerCase(),
        confidence: 1,
        source: 'google_places',
        place_id: String(place.id || ''),
        maps_url: String(place.googleMapsUri || ''),
        location: place.location || null,
        types: Array.isArray(place.types) ? place.types.map(String) : [],
        places,
      };
    }
  } catch (error) {
    console.warn('[Nova map] Google Places resolution unavailable:', error.message);
  }
  const geoResolver = require("../utils/geoResolver");
  return geoResolver.resolveDestination(rawDestination, context);
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
  // With live coordinates, an omitted destination deliberately means nearby;
  // do not silently replace it with an older trip destination.
  if (!context?.current_location) applyContextDestination(intent, context);
  if (!intent.parameters.destination && !context?.current_location) {
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
  const resolution = await resolveMapDestination(rawDestination, context);
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
    place_id: resolution.place_id || '',
    maps_url: resolution.maps_url || '',
    location: resolution.location || null,
    places: Array.isArray(resolution.places) ? resolution.places : [],
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
