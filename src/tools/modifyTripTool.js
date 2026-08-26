const tripStateService = require("../services/tripStateService");
const itineraryService = require("../services/itineraryService");
const { mapToStandardTags } = require("./tripTool");





async function update(
user_id,
parameters,
context
)
{


console.log(
"MODIFY TRIP:",
parameters
);



const updateData={};





let resolution_metadata = null;
if (parameters.destination) {
const geoResolver = require("../utils/geoResolver");
resolution_metadata = await geoResolver.resolveDestination(parameters.destination, context);
if (resolution_metadata.status !== "RESOLVED") {
  const errorMessages = {
    AMBIGUOUS: `Ambiguous destination. I cannot confidently resolve '${parameters.destination}'. Please explicitly ask the user to clarify where they want to go.`,
    NO_CANDIDATE: `I could not find any geographic location matching '${parameters.destination}'. Please ask the user to clarify the destination name.`,
    LLM_FAILURE: `A temporary system error occurred while resolving '${parameters.destination}'. Please ask the user to try again.`,
    GEO_API_FAILURE: `A temporary system error occurred while verifying '${parameters.destination}'. Please ask the user to try again.`,
    OUT_OF_SCOPE: `The destination '${parameters.destination}' is outside Malaysia. Please inform the user that this app only supports travel within Malaysia.`
  };
  return { 
    success: false, 
    error: errorMessages[resolution_metadata.status] || errorMessages.AMBIGUOUS
  };
}
updateData.destination = resolution_metadata.canonical;
}

if(parameters.duration!==null) {
updateData.duration = parameters.duration;
}

if(parameters.travel_date) {
updateData.travel_date = parameters.travel_date;
}

if(parameters.budget) {
updateData.budget = parameters.budget;
}

let interestArr = parameters.interest || [];
if (typeof interestArr === "string") interestArr = [interestArr];
interestArr = mapToStandardTags(interestArr);

let interestRemoveArr = parameters.interest_remove || [];
if (typeof interestRemoveArr === "string") interestRemoveArr = [interestRemoveArr];
interestRemoveArr = mapToStandardTags(interestRemoveArr);

if(parameters.interest_action==="remove_item" || (Array.isArray(interestRemoveArr) && interestRemoveArr.length>0)) {
updateData.interest = interestArr;
updateData.interest_action = "remove_item";
updateData.interest_remove = interestRemoveArr;
} else if(parameters.interest_action==="add_item" || (Array.isArray(interestArr) && interestArr.length>0)) {
updateData.interest = interestArr;
updateData.interest_action = "add_item";
updateData.interest_remove=[];
}

await tripStateService.updateTripState(user_id, updateData);

const regenerate = Object.keys(updateData).some(key =>
  ["destination", "duration", "travel_date", "budget"].includes(key)
) || Boolean(updateData.interest_action);

const latestState = await tripStateService.getTripState(user_id);

let itineraryResult = null;
if (regenerate && latestState.destination && latestState.duration) {
  await tripStateService.updateTripState(user_id, { reset_itinerary: true });
  itineraryResult = await itineraryService.generateItinerary(user_id);
}

const finalState = await tripStateService.getTripState(user_id);

return {
  status: "success",
  resolution_metadata: resolution_metadata,
  trip_state: finalState,
  itinerary_result: itineraryResult
};



}




module.exports={
update
};