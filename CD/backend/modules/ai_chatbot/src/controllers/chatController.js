const memory = require("../services/memoryService");
const tripState = require("../services/tripStateService");
const { buildContext } = require("../orchestration/contextBuilder");

const profileService = require("../services/profileService");
const savedTravelItemService = require("../services/savedTravelItemService");
const { runAgent } = require("../services/agentService");
const { buildAgentActions, buildPrimaryAction, validatePrimaryAction } = require("../services/agentActionService");

async function chatController(req, res) {
  const reqId = "REQ-" + Math.random().toString(36).substr(2, 9);
  const startedAt = Date.now();
  const timing = (stage) => console.info(`[${reqId}] timing ${stage}=${Date.now() - startedAt}ms`);
  console.log(`\n--- [CHAT START] ${reqId} ---`);
  
  try {
    const session = req.session;
    const {
      user_id,
      message,
      isVoice,
      interaction_mode,
      attachment,
      input_language,
    } = req.body;
    console.log(`[${reqId}] Chat request received.`);

    if (!message || !user_id) {
      return res.status(400).json({ success: false, error: "Missing parameters" });
    }

    if (!session || !session.id) {
      return res.status(400).json({ success: false, error: "session unavailable" });
    }

    const cleanMessage = message.trim();
    const normalizedAttachment = attachment && typeof attachment === 'object'
      ? {
          type: typeof attachment.type === 'string' ? attachment.type : 'unknown',
          name: typeof attachment.name === 'string' ? attachment.name.slice(0, 160) : '',
          analysisStatus: typeof attachment.analysisStatus === 'string'
            ? attachment.analysisStatus
            : 'providerUnavailable',
          analysis: attachment.analysis && typeof attachment.analysis === 'object'
            ? {
                type: String(attachment.analysis.type || '').slice(0, 32),
                filename: String(attachment.analysis.filename || '').slice(0, 160),
                travelTags: Array.isArray(attachment.analysis.travelTags)
                  ? attachment.analysis.travelTags.slice(0, 21).map((tag) => String(tag).slice(0, 80))
                  : [],
                extractedText: String(attachment.analysis.extractedText || '').slice(0, 12000),
                protectedFacts: Array.isArray(attachment.analysis.protectedFacts)
                  ? attachment.analysis.protectedFacts.slice(0, 80).map((fact) => String(fact).slice(0, 160))
                  : [],
                visualContext: attachment.analysis.visualContext
                  ? String(attachment.analysis.visualContext).slice(0, 2000)
                  : null,
                locationHint: attachment.analysis.locationHint
                  ? String(attachment.analysis.locationHint).slice(0, 240)
                  : '',
                uncertainInferences: Array.isArray(attachment.analysis.uncertainInferences)
                  ? attachment.analysis.uncertainInferences.slice(0, 20).map((item) => String(item).slice(0, 240))
                  : [],
                normalizedContext: attachment.analysis.normalizedContext && typeof attachment.analysis.normalizedContext === 'object'
                  ? {
                      source: String(attachment.analysis.normalizedContext.source || '').slice(0, 64),
                      factualText: String(attachment.analysis.normalizedContext.factualText || '').slice(0, 12000),
                      protectedFacts: Array.isArray(attachment.analysis.normalizedContext.protectedFacts)
                        ? attachment.analysis.normalizedContext.protectedFacts.slice(0, 80).map((fact) => String(fact).slice(0, 160))
                        : [],
                      visualContext: attachment.analysis.normalizedContext.visualContext
                        ? String(attachment.analysis.normalizedContext.visualContext).slice(0, 2000)
                        : null,
                      locationHint: attachment.analysis.normalizedContext.locationHint
                        ? String(attachment.analysis.normalizedContext.locationHint).slice(0, 240)
                        : '',
                      uncertainInferences: Array.isArray(attachment.analysis.normalizedContext.uncertainInferences)
                        ? attachment.analysis.normalizedContext.uncertainInferences.slice(0, 20).map((item) => String(item).slice(0, 240))
                        : [],
                      instruction: String(attachment.analysis.normalizedContext.instruction || '').slice(0, 500),
                    }
                  : null,
                warnings: Array.isArray(attachment.analysis.warnings)
                  ? attachment.analysis.warnings.slice(0, 10).map((item) => String(item).slice(0, 240))
                  : [],
              }
            : null,
        }
      : null;

    const [shortMemory, tripStateData, profile, savedItemResult] = await Promise.all([
      memory.getShortMemory(user_id, session.id),
      tripState.getTripState(user_id),
      profileService.getProfile(user_id),
      savedTravelItemService.list(user_id, 30),
    ]);
    timing('T1_context_ready');
    const language = null; // Agent will detect language natively

    await memory.saveMessage(user_id, session.id, "user", cleanMessage);


    const interactionMode = ["chat_text", "driving_voice"].includes(interaction_mode)
      ? interaction_mode
      : (isVoice ? "driving_voice" : "chat_text");
    console.log(`[${reqId}] interaction_mode=${interactionMode}`);
    const relevantSavedItems = savedTravelItemService.relevant(
      savedItemResult.items || [],
      cleanMessage,
    );
    const context = buildContext({
      userMessage: cleanMessage,
      shortMemory,
      tripState: tripStateData,
      profile,
      language,
      interactionMode,
      sessionId: session.id
      ,attachment: normalizedAttachment,
      savedItems: relevantSavedItems.length
        ? relevantSavedItems
        : (savedItemResult.items || []).slice(0, 5),
      inputLanguage: ['en', 'ms', 'zh-CN'].includes(input_language)
        ? input_language
        : null,
    });

    console.log(`[${reqId}] Entering agentService...`);
    const agentResponse = await runAgent(context, user_id, reqId);
    timing('T7_agent_complete');
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

    const [updatedState, updatedProfile] = await Promise.all([
      tripState.getTripState(user_id),
      profileService.getProfile(user_id),
    ]);
    const actions = buildAgentActions({
      intent: agentResponse.intent,
      toolResult,
      tripState: updatedState,
      profile: updatedProfile,
      routing: agentResponse.routing,
    });
    const action = validatePrimaryAction(buildPrimaryAction({
      intent: agentResponse.intent,
      toolResult,
      tripState: updatedState,
      profile: updatedProfile,
      routing: agentResponse.routing,
    }));

    console.log(`--- [CHAT END] ${reqId} ---`);
    timing('T7_response_sent');
    return res.json({
      success: true,
      response: reply,
      session,
      reply,
      action,
      data: toolResult || {},
      intent,
      tool_result: toolResult,
      tool_results: agentResponse.toolResults || [],
      short_memory: await memory.getShortMemory(user_id, session.id),
      trip_state: updatedState,
      agent_actions: actions,
      language: replyLanguageName,
      languageCode: replyLanguageCode,
      routing: agentResponse.routing,
    });
  } catch (error) {
    console.error(`--- [CHAT ERROR] ${reqId} ---`, error);
    return res.status(500).json({ success: false, error: error.message });
  }
}

module.exports = { chatController };
