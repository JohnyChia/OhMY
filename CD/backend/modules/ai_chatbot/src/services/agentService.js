const { createChatCompletionWithFailover } = require("../config/openai");
const { executeTool } = require("../orchestration/toolManager");
const { ATTRACTION_TAGS } = require("../config/attractionTags");

const tools = [
  {
    type: "function",
    function: {
      name: "create_trip",
      description: "Whenever the user clearly expresses intent to plan or create a new trip, you MUST call this tool regardless of whether the destination string appears valid, misspelled, phonetic, garbled, or unknown. Pass the destination exactly as transcribed. Do not semantically validate, correct, normalize, or reject the destination at the Agent layer. Geographic validation belongs exclusively to geoResolver.",
      parameters: {
        type: "object",
        properties: {
          destination: { type: "string", description: "The exact destination name transcribed from the user's input, even if misspelled, phonetic, or garbled." },
          duration: { type: "number", description: "Duration in days (optional, e.g. 2 for '2 days')" },
          interest: { type: "array", items: { type: "string", enum: ATTRACTION_TAGS }, description: "List of canonical attraction interests (optional). Semantically map user input (e.g., 'food' -> 'Local Cuisine' or 'Restaurant') to these valid tags." },
          budget: { type: "string", description: "Budget preference (optional, e.g. 'budget', 'RM500')" },
          travel_date: { type: "string", description: "When they plan to travel (optional, e.g. 'next week')" }
        },
        required: ["destination"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "update_trip",
      description: "Whenever the user clearly requests changing the current trip destination or other details, you MUST call this tool and pass the raw destination string unchanged. Do not semantically validate, correct, normalize, or reject the destination at the Agent layer.",
      parameters: {
        type: "object",
        properties: {
          interest: { type: "array", items: { type: "string", enum: ATTRACTION_TAGS }, description: "Interests to add" },
          interest_remove: { type: "array", items: { type: "string", enum: ATTRACTION_TAGS }, description: "Interests to remove" },
          duration: { type: "number", description: "New duration in days" },
          destination: { type: "string", description: "The exact destination name transcribed from the user's input, even if misspelled, phonetic, or garbled." },
          budget: { type: "string", description: "New budget preference" },
          travel_date: { type: "string", description: "New travel date" }
        }
      }
    }
  },
  {
    type: "function",
    function: {
      name: "generate_itinerary",
      description: "Generate or regenerate the day-by-day itinerary timeline for the current active trip. MUST use this when the user says '帮我plan' or agrees to generate the plan after the destination and duration are set.",
      parameters: {
        type: "object",
        properties: {
          generate: { type: "boolean", description: "Always set to true" }
        },
        required: ["generate"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "weather",
      description: "Check the weather or forecast for a destination.",
      parameters: {
        type: "object",
        properties: {
          destination: { type: "string" },
          travel_date: { type: "string", description: "e.g., 'today', 'tomorrow'" }
        },
        required: ["destination"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "recommendation",
      description: "Get place recommendations, cafes, attractions. Also use for vague requests like 'somewhere with a beach'.",
      parameters: {
        type: "object",
        properties: {
          destination: { type: "string", description: "The city or area to search in (if known)" },
          category: { type: "string", description: "The category of place (e.g., 'cafe', 'beach', 'history')" },
          excluded_locations: { type: "array", items: { type: "string" }, description: "Places or categories to exclude" }
        }
      }
    }
  },
  {
    type: "function",
    function: {
      name: "traffic",
      description: "Check road conditions and traffic jams.",
      parameters: {
        type: "object",
        properties: {
          destination: { type: "string", description: "The location to check traffic for" }
        }
      }
    }
  },
  {
    type: "function",
    function: {
      name: "reroute",
      description: "Reroute the trip or find an alternate path due to traffic, weather, closures, or user dislike.",
      parameters: {
        type: "object",
        properties: {
          reason: { type: "string", description: "The reason for rerouting (e.g., 'Traffic', 'Raining')" },
          avoid_locations: { type: "array", items: { type: "string" }, description: "Extract any explicit location reference supplied by the user (e.g., proper nouns, or generic terms like 'the highway', 'the bridge'). Leave empty if none provided." }
        }
      }
    }
  },
  {
    type: "function",
    function: {
      name: "update_profile",
      description: "Save long-term permanent user preferences (e.g., 'I always travel with kids').",
      parameters: {
        type: "object",
        properties: {
          favorite_categories: { type: "array", items: { type: "string" } },
          travel_style: { type: "string" },
          budget_preference: { type: "string" }
        }
      }
    }
  }
];

async function runAgent(context, user_id, reqId = "REQ-UNKN") {
  const diagnostics = {
    totalLLMCalls: 0,
    iterations: 0,
    toolsExecuted: 0,
    fallbackKeyUsed: false,
    promptTokens: 0,
    completionTokens: 0,
    totalTokens: 0,
    apiErrors: 0,
    toolNamesExecuted: []
  };

  const safeTripState = { ...(context.current_trip_state || {}) };
  if (Array.isArray(safeTripState.itinerary) && safeTripState.itinerary.length > 0) {
    safeTripState.itinerary = `[Itinerary generated: ${safeTripState.itinerary.length} days. Full details omitted for brevity.]`;
  }
  delete safeTripState.id;
  delete safeTripState.user_id;
  delete safeTripState.updated_at;

  const systemMessage = {
    role: "system",
    content: `You are Nova, an AI travel assistant. You plan trips, suggest destinations, handle rerouting, and check weather.

RULES:
1. ALWAYS execute tools when enough information is available.
2. Do not invent information.
3. CONVERSATIONAL SUMMARY: When a tool is executed successfully, summarize the action naturally. Do not explicitly say "I executed the tool".
4. MULTIPLE TOOLS: If you need to perform multiple actions, execute them sequentially.
5. TRAFFIC/REROUTE: Only reroute if the user mentions an issue. Extract generic names like "the highway".
6. DESTINATION INFERENCE: Always extract the exact transcribed destination name provided by the user, even if it appears phonetically garbled, misspelled, or ambiguous. Pass the exact raw string directly to the tool. The tool will handle geographic resolution. DO NOT attempt to validate or correct the destination yourself.
7. UNINTELLIGIBLE INPUT & HALLUCINATIONS: If the input contains Thai, Arabic, Jawi, or Urdu script, it is a Whisper STT hallucination. Treat as unintelligible. Ask the user to repeat.
8. CRITICAL FOR TRIP PLANNING: Extract ALL parameters at the same time (destination, duration, interest, budget, travel_date). Mentally translate Pinyin/Malay time words into a NUMBER (e.g., 'liang tian' -> 2). If you have 'destination', that is enough to proceed! Duration is NOT strictly required.
9. When the user provides enough evidence to create or modify a trip, the appropriate trip tool MUST be executed. After the tool execution, provide the conversational summary and ask the appropriate follow-up question. Do not treat the conversational summary itself as completion of the tool action.
10. If a disruption or obstacle is mentioned and rerouting is appropriate, call reroute. If the user explicitly identifies the affected location or route, extract that information into avoid_locations. Locations may be proper nouns or generic route descriptions such as 'the highway', 'the bridge', or 'the main road'. If no location is provided, leave avoid_locations empty. Never invent a location that the user did not provide.
11. MALAYSIAN SHORT FORMS: Expand short forms ('KL' = Kuala Lumpur, 'JB' = Johor Bahru, 'pg' = Penang, 'tmr' = tomorrow).
12. OUTPUT METADATA: When you reply to the user, you may optionally prepend your conversational response with a language tag like [LANG: en] or [LANG: ms] or [LANG: zh-CN] to indicate the language you are speaking in. Example: "[LANG: ms] Boleh, saya tolong rancang!" This is metadata only; do NOT output JSON formatting for your conversational text.
13. TAGGING: Translate natural language preferences semantically to the exact tags allowed in the create_trip/update_trip schemas. Do NOT invent new tags. Broad concepts map logically based on context (e.g. 'food' -> 'Local Cuisine' or 'Restaurant', 'history' -> 'Historical Landmark' or 'Cultural Learning').
14. DESTINATION CORRECTIONS: If a trip tool returns \`resolution_metadata\` with \`corrected: true\` (e.g. interpreting "Saba" as "Sabah"), you MUST explicitly disclose this interpretation in your conversational reply. For materially changed destinations, require the user to confirm the destination before proceeding (e.g. "I understood 'Saba' as Sabah. Is that correct?").
15. TOOL ERRORS: When a tool returns success=false and provides an error message, you MUST communicate the substantive reason to the user. You may paraphrase the message naturally, but must not hide, contradict, or ignore the error. For OUT_OF_SCOPE destination errors, clearly tell the user that WanderVoice currently supports Malaysia-only destinations and ask them to choose a Malaysian destination.

Current Trip State: ${JSON.stringify(safeTripState)}
Traveler Profile: ${JSON.stringify(context.traveler_profile || {})}`
  };

  const messages = [
    systemMessage,
    ...((context.conversation_history || []).map(m => ({
      role: m.role,
      content: m.content
    }))),
    {
      role: "user",
      content: context.current_message
    }
  ];

  let toolResultData = null;
  let finalIntent = "general_chat";
  const MAX_ITERATIONS = 3;
  let iteration = 0;
  let finalReply = "";
  let languageCode = null;
  let callCount = 1;

  while (iteration < MAX_ITERATIONS) {
    iteration++;
    let response;
    
    try {
      diagnostics.totalLLMCalls++;
      response = await createChatCompletionWithFailover({
        model: process.env.GROQ_MODEL,
        temperature: 0.1,
        messages: messages,
        tools: tools,
        tool_choice: "auto",
        parallel_tool_calls: false
      });
    } catch (apiError) {
      console.warn(`[${reqId}] Groq Tool Calling Error:`, apiError.message);
      diagnostics.apiErrors++;
      // Stop the loop cleanly on an API error, do not perform hidden retries
      break;
    }

    if (response._fallbackUsed) diagnostics.fallbackKeyUsed = true;
    if (response.usage) {
      diagnostics.promptTokens += (response.usage.prompt_tokens || 0);
      diagnostics.completionTokens += (response.usage.completion_tokens || 0);
      diagnostics.totalTokens += (response.usage.total_tokens || 0);
    }

    const responseMessage = response.choices[0].message;
    console.log(`[${reqId}] Iteration ${iteration}, tool_calls length: ${responseMessage.tool_calls ? responseMessage.tool_calls.length : 0}`);

    if (responseMessage.tool_calls && responseMessage.tool_calls.length > 0) {
      responseMessage.tool_calls.forEach(tc => {
        try {
          let args = JSON.parse(tc.function.arguments);
          let changed = false;
          Object.keys(args).forEach(k => {
            if (args[k] === null) {
              delete args[k];
              changed = true;
            }
          });
          if (changed) {
            tc.function.arguments = JSON.stringify(args);
          }
        } catch (e) {}
      });

      messages.push(responseMessage);

      const executedSignatures = new Set();
      for (const toolCall of responseMessage.tool_calls) {
        const toolName = toolCall.function.name;
        const toolArgsRaw = toolCall.function.arguments;
        
        // Deduplicate identical tool calls in the same iteration
        const signature = `${toolName}:${toolArgsRaw}`;
        if (executedSignatures.has(signature)) {
          console.log(`[${reqId}] Suppressing duplicate tool execution in same iteration: ${signature}`);
          continue;
        }
        executedSignatures.add(signature);

        const toolArgs = JSON.parse(toolArgsRaw);

        diagnostics.toolsExecuted++;
        diagnostics.toolNamesExecuted.push(toolName);

        console.log(`[${reqId}] [TOOL-CALL-${callCount}] Executing tool: ${toolName} with args:`, toolArgs);
        callCount++;

        const intentMock = {
          intent: toolName,
          tool: toolName,
          parameters: toolArgs,
          profile_update: toolName === "update_profile" ? toolArgs : undefined
        };
        // Keep tracking the final intent, later tools override earlier ones (e.g. reroute overrides create_trip)
        finalIntent = toolName;

        try {
          const result = await executeTool(intentMock, user_id, context);
          toolResultData = result;

          const trimmedResult = { ...result };
          if (trimmedResult.itinerary) {
            if (Array.isArray(trimmedResult.itinerary) && trimmedResult.itinerary.length > 0) {
              trimmedResult.itinerary = `[Itinerary generated: ${trimmedResult.itinerary.length} days. Full details omitted to save tokens.]`;
            } else if (trimmedResult.itinerary.days && Array.isArray(trimmedResult.itinerary.days)) {
              trimmedResult.itinerary = `[Itinerary generated: ${trimmedResult.itinerary.days.length} days. Full details omitted to save tokens.]`;
            }
          }
          if (trimmedResult.days && Array.isArray(trimmedResult.days) && trimmedResult.days.length > 0) {
            trimmedResult.days = `[Itinerary days generated: ${trimmedResult.days.length}. Full details omitted.]`;
          }
          delete trimmedResult.id;
          delete trimmedResult.user_id;
          delete trimmedResult.updated_at;

          messages.push({
            tool_call_id: toolCall.id,
            role: "tool",
            name: toolName,
            content: JSON.stringify(trimmedResult || { status: "success" })
          });
        } catch (err) {
          messages.push({
            tool_call_id: toolCall.id,
            role: "tool",
            name: toolName,
            content: JSON.stringify({ error: err.message })
          });
        }
      }
      // If we hit MAX_ITERATIONS, we naturally stop the loop after tool execution,
      // preventing an infinite sequence of API calls.
      if (iteration >= MAX_ITERATIONS) {
         finalReply = "I have planned as much as possible for now. Please let me know if you need more details!";
         break;
      }
    } else {
      let content = responseMessage.content || "";
      const langMatch = content.match(/^\[LANG:\s*([a-zA-Z-]+)\]\s*/i);
      if (langMatch) {
        languageCode = langMatch[1];
        content = content.replace(langMatch[0], "").trim();
      }
      finalReply = content;
      break;
    }
  }

  diagnostics.iterations = iteration;
  console.log(`[${reqId}] --- TOKEN DIAGNOSTICS ---`);
  console.log(JSON.stringify(diagnostics, null, 2));

  return {
    reply: finalReply,
    languageCode,
    toolResult: toolResultData,
    intent: finalIntent
  };
}

module.exports = { runAgent };
