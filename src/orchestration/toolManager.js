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
  if (!intent.parameters.destination) {
    const state = await tripStateService.getTripState(user_id);
    if (state && state.destination) intent.parameters.destination = state.destination;
  }
  return await weatherTool.get(intent.parameters);
}

case "recommendation":
{
  if (!intent.parameters.destination) {
    const state = await tripStateService.getTripState(user_id);
    if (state && state.destination) intent.parameters.destination = state.destination;
  }
  return await recommendationTool.get(intent.parameters);
}

case "traffic":
{
  if (!intent.parameters.destination) {
    const state = await tripStateService.getTripState(user_id);
    if (state && state.destination) intent.parameters.destination = state.destination;
  }
  return await trafficTool.get(intent.parameters);
}


case "reroute":


return await rerouteTool.execute(
user_id,
intent.parameters
);






default:

return null;



}



}





module.exports={
executeTool
};
