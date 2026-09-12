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

})
{ 

const destination = tripState?.destination;


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
},

attachment: attachment || null,

saved_travel_items: Array.isArray(savedItems) ? savedItems.slice(0, 5) : []



};



}



module.exports={
buildContext
};
