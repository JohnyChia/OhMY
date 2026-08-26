const tripStateService = require("../services/tripStateService");

const { ATTRACTION_TAGS } = require("../config/attractionTags");

function mapToStandardTags(interests) {
  if (!Array.isArray(interests)) return [];

  const lowercasedTags = ATTRACTION_TAGS.map(t => t.toLowerCase());
  const validTags = new Set();

  interests.forEach(tag => {
    if (typeof tag !== "string") return;
    const t = tag.toLowerCase().trim();
    
    // Strict semantic validation: only accept tags that exactly match our taxonomy
    const index = lowercasedTags.indexOf(t);
    if (index !== -1) {
      validTags.add(ATTRACTION_TAGS[index]);
    }
  });

  return Array.from(validTags);
}

async function createTrip(user_id, parameters, context) {
  console.log("CREATE TRIP:", parameters);

  const old = await tripStateService.getTripState(user_id);
  const mappedInterests = mapToStandardTags(parameters.interest || []);

  let resolution = null;

  if (parameters.destination) {
    const geoResolver = require("../utils/geoResolver");
    resolution = await geoResolver.resolveDestination(parameters.destination, context);
    if (resolution.status !== "RESOLVED") {
      const errorMessages = {
        AMBIGUOUS: `Ambiguous destination. I cannot confidently resolve '${parameters.destination}'. Please explicitly ask the user to clarify where they want to go.`,
        NO_CANDIDATE: `I could not find any geographic location matching '${parameters.destination}'. Please ask the user to clarify the destination name.`,
        LLM_FAILURE: `A temporary system error occurred while resolving '${parameters.destination}'. Please ask the user to try again.`,
        GEO_API_FAILURE: `A temporary system error occurred while verifying '${parameters.destination}'. Please ask the user to try again.`,
        OUT_OF_SCOPE: `The destination '${parameters.destination}' is outside Malaysia. Please inform the user that this app only supports travel within Malaysia.`
      };
      return { 
        success: false, 
        error: errorMessages[resolution.status] || errorMessages.AMBIGUOUS
      };
    }
    parameters.destination = resolution.canonical;
  }

  const result = await tripStateService.updateTripState(
    user_id,
    {
      destination: parameters.destination || "",
      duration: parameters.duration || old.duration || null,
      travel_date: parameters.travel_date || old.travel_date || "",
      interest: mappedInterests,
      budget: parameters.budget || old.budget || "",
      language: parameters.language || "english",
      replace_trip: true,
      reset_itinerary: true,
      itinerary: []
    }
  );

  return {
    status: "success",
    resolution_metadata: resolution,
    trip_state: result
  };
}



module.exports={
createTrip,
mapToStandardTags
};