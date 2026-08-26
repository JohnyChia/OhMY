const {
executeTool
}
=
require("./toolManager");



async function routeIntent(
intent,
user_id
)
{


switch(intent.intent)
{


case "generate_itinerary":


intent.tool =
"generate_itinerary";


break;



case "plan_trip":


intent.tool =
"create_trip";


break;



case "modify_trip":


intent.tool =
"update_trip";


break;



case "update_profile":


intent.tool =
"update_profile";


break;



case "weather_check":


intent.tool =
"weather";


break;



case "recommend_place":


intent.tool =
"recommendation";


break;



case "traffic_check":


intent.tool =
"traffic";


break;



case "reroute_trip":


intent.tool =
"reroute";


break;



default:


intent.tool =
"";

break;


}



return await executeTool(
intent,
user_id
);



}



module.exports={
routeIntent
};
