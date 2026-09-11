function buildContext({

userMessage,

shortMemory,

tripState,

profile,

language

})
{


return {


current_message:
userMessage,



conversation_history:
(shortMemory || []).slice(-6),



current_trip_state:
tripState || {},



traveler_profile:
profile || {},



language



};



}



module.exports={
buildContext
};