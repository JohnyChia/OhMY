function buildContext({

userMessage,

shortMemory,

tripState,

profile,

language,

interactionMode,

sessionId
,
attachment,
savedItems
,
inputLanguage
,
currentLocation

})
{ 

const destination = tripState?.destination;
const latitude = Number(currentLocation?.latitude);
const longitude = Number(currentLocation?.longitude);
const deviceLocation = Number.isFinite(latitude)
  && latitude >= -90
  && latitude <= 90
  && Number.isFinite(longitude)
  && longitude >= -180
  && longitude <= 180
  ? {
      latitude,
      longitude,
      accuracy: Number.isFinite(Number(currentLocation?.accuracy))
        ? Number(currentLocation.accuracy)
        : null,
      captured_at: typeof currentLocation?.captured_at === 'string'
        ? currentLocation.captured_at.slice(0, 64)
        : null,
    }
  : null;


return {


current_message:
userMessage,



conversation_history:
(shortMemory || []).slice(-6),



current_trip_state:
tripState || {},



traveler_profile:
profile || {},



language,

input_language: inputLanguage || null,

interaction_mode: interactionMode || "chat_text",

session_context: {
  session_id: sessionId || null,
  conversation: {
    recent_turn_count: (shortMemory || []).length
  },
  // Destination context comes from persisted trip state, never from a
  // hard-coded place-name list or an unrelated previous chat turn.
  location: destination ? { destination } : {},
  trip: tripState || {},
  preferences: profile || {}
  ,device_location: deviceLocation
},

attachment: attachment || null,

saved_travel_items: Array.isArray(savedItems) ? savedItems.slice(0, 5) : []



};



}



module.exports={
buildContext
};
