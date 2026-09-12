const openai =
require("../config/openai");


const supabase =
require("../config/supabase");


const tripState =
require("./tripStateService");


const profileService =
require("./profileService");





async function generateItinerary(user_id)
{


console.log(
"GENERATING ITINERARY:",
user_id
);







const trip =
await tripState.getTripState(
user_id
);



if(
!trip ||
!trip.id
)
{
throw new Error(
"No trip state found"
);
}








if(
!trip.destination ||
!trip.duration
)
{

throw new Error(
"Trip information incomplete"
);

}






const profile =
await profileService.getProfile(
user_id
);





const rawInterests = Array.isArray(trip.interest) ? trip.interest : [];
const positiveInterests = rawInterests.filter(i => !i.startsWith('-'));
const negativeInterests = rawInterests.filter(i => i.startsWith('-')).map(i => i.substring(1));

const interest = positiveInterests.length > 0 ? positiveInterests : ["general"];







console.log(
"TRIP DATA:",
{
destination:trip.destination,
duration:trip.duration,
interest,
budget:trip.budget
}
);









const result =
await openai.chat.completions.create({


model:
process.env.GROQ_MODEL,


temperature:
0.3,


response_format:
{
type:"json_object"
},



messages:[


{


role:"system",

content:
`
You are an expert travel planner.

Generate itinerary.

Return JSON only.

Format:

{
"days":[]
}



Rules:


1.
Number of days MUST equal duration.


2.
Each day requires:

day
title
description
location
category



3.
Location:

Must be a real attraction.

Format:

Place name, city, state



Example:

Cheong Fatt Tze Mansion, George Town, Penang


Do NOT output:

Penang

George Town

Malaysia


${trip.avoid_locations && trip.avoid_locations.length > 0 ? `\nCRITICAL: DO NOT recommend or include any of the following locations in the itinerary: ${trip.avoid_locations.join(", ")}.` : ""}

${negativeInterests.length > 0 ? `\nCRITICAL: DO NOT recommend activities or locations related to: ${negativeInterests.join(", ")}.` : ""}

4.
Category:

Must come from interest list.


If interest list is empty,
use "general".



5.
Do not reuse old itinerary.


6.
Use profile only for style:

luxury
budget
premium
casual



7.
Description:

2-3 sentences.

Explain activity and experience.



Return JSON only.
`

},



{


role:"user",

content:

JSON.stringify({

destination:
trip.destination,


duration:
trip.duration,


interest,


budget:
trip.budget || "",


profile


})

}


]

});






console.log(
"AI RESPONSE:"
);

console.log(
result.choices[0]
.message
.content
);








let itinerary;


try
{

itinerary =
JSON.parse(

result.choices[0]
.message
.content

);

}
catch(error)
{

console.log("AI returned invalid JSON, falling back to empty itinerary");
itinerary = { days: [] };

}





if (!itinerary || !Array.isArray(itinerary.days)) {
  itinerary = itinerary || {};
  itinerary.days = [];
}

if (itinerary.days.length > trip.duration) {
  itinerary.days = itinerary.days.slice(0, trip.duration);
} else if (itinerary.days.length < trip.duration) {
  const last = itinerary.days[itinerary.days.length - 1] || {};
  while (itinerary.days.length < trip.duration) {
    const idx = itinerary.days.length + 1;
    itinerary.days.push({
      day: idx,
      title: last.title || `Day ${idx} — Explore`,
      description: last.description || `Enjoy another day exploring ${trip.destination}.`,
      location: last.location || `${trip.destination}, Malaysia`,
      category: last.category || (interest[0] || "general")
    });
  }
}

const allowedCategories = interest.map(x => String(x).toLowerCase());

for (const day of itinerary.days) {
  day.title       = day.title       || `Day ${day.day} — ${trip.destination}`;
  day.description = day.description || `Discover the best of ${trip.destination}.`;
  day.location    = day.location    || `${trip.destination}, Malaysia`;
  day.category    = day.category    || interest[0] || "general";

  day.category = String(day.category).toLowerCase().trim();

  const parts = day.location.split(",").map(x => x.trim()).filter(Boolean);
  if (parts.length < 2) {
    day.location = `${day.location}, ${trip.destination}, Malaysia`;
  } else if (parts.length < 3) {
    day.location = `${day.location}, Malaysia`;
  }

  if (
    allowedCategories[0] !== "general" &&
    !allowedCategories.includes(day.category)
  ) {
    day.category = allowedCategories[0] || "general";
  }
}













itinerary.days =

itinerary.days.map(

(day,index)=>
({

day:index+1,

title:
day.title,

description:
day.description,

location:
day.location,

category:
day.category


})

);










try {
  await supabase.from("itineraries").delete().eq("trip_id", trip.id);
  const rows = itinerary.days.map((day) => ({
    user_id,
    trip_id: trip.id,
    day: day.day,
    title: day.title,
    description: day.description,
    location: day.location,
    category: day.category
  }));
  await supabase.from("itineraries").insert(rows);
} catch (err) {
  console.log("Supabase itineraries table operation ignored:", err.message);
}











await tripState.updateTripState(

user_id,

{

itinerary:
itinerary.days


}

);








console.log(
"ITINERARY SAVED"
);



return itinerary;


}







module.exports={

generateItinerary

};