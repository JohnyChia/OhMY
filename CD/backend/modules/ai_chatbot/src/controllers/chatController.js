const memory = require("../services/memoryService");
const tripState = require("../services/tripStateService");
const { buildContext } = require("../orchestration/contextBuilder");

const profileService = require("../services/profileService");
const { runAgent } = require("../services/agentService");

async function chatController(req, res) {
  const reqId = "REQ-" + Math.random().toString(36).substr(2, 9);
  console.log(`\n--- [CHAT START] ${reqId} ---`);
  
  try {
    const session = req.session;
    const { user_id, message, isVoice } = req.body;
    console.log(`[${reqId}] Input: "${message}"`);

    if (!message || !user_id) {
      return res.status(400).json({ success: false, error: "Missing parameters" });
    }

    if (!session || !session.id) {
      return res.status(400).json({ success: false, error: "session unavailable" });
    }

    const cleanMessage = message.trim();

    const shortMemory = await memory.getShortMemory(user_id, session.id);
    const language = null; // Agent will detect language natively

    await memory.saveMessage(user_id, session.id, "user", cleanMessage);

    const tripStateData = await tripState.getTripState(user_id);
    const profile = await profileService.getProfile(user_id);

    const context = buildContext({
      userMessage: cleanMessage,
      shortMemory,
      tripState: tripStateData,
      profile,
      language
    });

    console.log(`[${reqId}] Entering agentService...`);
    const agentResponse = await runAgent(context, user_id, reqId);
    console.log(`[${reqId}] Exited agentService.`);

    let intent = { intent: agentResponse.intent, parameters: {} };
    let toolResult = agentResponse.toolResult;
    const reply = agentResponse.reply;

    await memory.saveMessage(user_id, session.id, "assistant", reply);

    let replyLanguageCode = agentResponse.languageCode;
    let replyLanguageName = agentResponse.languageCode;
    
    if (!replyLanguageCode) {
      replyLanguageCode = tripStateData.language || "en";
      replyLanguageName = tripStateData.language || "en";
      console.log(`[LANGUAGE FALLBACK] Agent omitted [LANG] tag. Normalized to: ${replyLanguageCode}`);
    } else {
      console.log(`[LANGUAGE DETECTED] Agent returned tag: ${replyLanguageCode}`);
    }

    const updatedState = await tripState.getTripState(user_id);

    console.log(`--- [CHAT END] ${reqId} ---`);
    return res.json({
      success: true,
      session,
      reply,
      intent,
      tool_result: toolResult,
      short_memory: await memory.getShortMemory(user_id, session.id),
      trip_state: updatedState,
      language: replyLanguageName,
      languageCode: replyLanguageCode
    });
  } catch (error) {
    console.error(`--- [CHAT ERROR] ${reqId} ---`, error);
    return res.status(500).json({ success: false, error: error.message });
  }
}

module.exports = { chatController };
