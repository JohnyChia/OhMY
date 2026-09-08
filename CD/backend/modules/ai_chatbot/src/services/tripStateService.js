const supabase =
require("../config/supabase");





function normalizeDuration(value)
{

if(
value===null ||
value===undefined
)
{
return null;
}


if(
typeof value==="number"
)
{
return value;
}



if(
typeof value==="string"
)
{

const match =
value.match(/\d+/);


if(match)
{
return Number(match[0]);
}


const text =
value.toLowerCase();


if(
text.includes("week")
)
{
return 7;
}


if(
text.includes("month")
)
{
return 30;
}


}


return null;

}







function normalizeInterest(list)
{

if(!Array.isArray(list))
{
return [];
}


return list.map(x=>

String(x)
.toLowerCase()
.replace(
/\s*(trip|tour|holiday|vacation)$/i,
""
)
.trim()

)
.filter(Boolean);

}





const memoryTripStates = new Map();

async function getTripState(user_id) {
  try {
    const { data, error } = await supabase
      .from("trip_states")
      .select("*")
      .eq("user_id", user_id)
      .maybeSingle();

    if (!error && data) {
      return data;
    }
  } catch (err) {
    console.log("Supabase getTripState exception, using memory fallback:", err.message);
  }

  return memoryTripStates.get(user_id) || { id: "temp_" + user_id, user_id };
}

async function updateTripState(user_id, newData) {
  const old = await getTripState(user_id);
  let interests = [];

  if (newData.replace_trip === true) {
    interests = normalizeInterest(newData.interest);
  } else {
    interests = Array.isArray(old.interest)
      ? normalizeInterest(old.interest)
      : [];

    if (newData.interest_action === "" && Array.isArray(newData.interest)) {
      interests = normalizeInterest(newData.interest);
    } else {
      if (Array.isArray(newData.interest) && newData.interest.length > 0) {
        for (const item of normalizeInterest(newData.interest)) {
          if (!interests.includes(item)) {
            interests.push(item);
          }
        }
      }

      if (Array.isArray(newData.interest_remove) && newData.interest_remove.length > 0) {
        const removeList = normalizeInterest(newData.interest_remove);
        interests = interests.filter((x) => !removeList.includes(x));
        
        for (const item of removeList) {
          const negItem = `-${item}`;
          if (!interests.includes(negItem)) {
            interests.push(negItem);
          }
        }
      }
    }
  }

  let avoidList = Array.isArray(old.avoid_locations) ? old.avoid_locations : [];
  if (Array.isArray(newData.avoid_locations)) {
    for (const loc of newData.avoid_locations) {
      if (!avoidList.includes(loc)) avoidList.push(loc);
    }
  }
  if (newData.replace_trip === true) {
    avoidList = [];
  }

  const merged = {
    id: old.id || "trip_" + Date.now(),
    user_id,
    destination: newData.destination ?? old.destination ?? "",
    duration: normalizeDuration(newData.duration ?? old.duration ?? null),
    travel_date: newData.travel_date ?? old.travel_date ?? "",
    interest: interests,
    budget: newData.budget ?? old.budget ?? "",
    language: newData.language ?? old.language ?? "english",
    avoid_locations: avoidList,
    itinerary: newData.reset_itinerary === true
      ? []
      : (newData.itinerary ?? old.itinerary ?? []),
    updated_at: new Date()
  };

  try {
    const { data, error } = await supabase
      .from("trip_states")
      .upsert(merged, { onConflict: "user_id" })
      .select()
      .single();

    if (!error && data) {
      memoryTripStates.set(user_id, data);
      return data;
    }
  } catch (err) {
    console.log("Supabase updateTripState exception, saving in memory fallback:", err.message);
  }

  memoryTripStates.set(user_id, merged);
  return merged;
}






module.exports={

normalizeDuration,

normalizeInterest,

getTripState,

updateTripState

};