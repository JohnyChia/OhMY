const openai = require("../config/openai");

async function generateResponse(intent, toolResult, language) {
  try {
    const lang = (language && language.language) ? language.language : "english";
    const style = (language && language.style) ? language.style : "casual";

    async function localize(englishText) {
      if (lang.toLowerCase() === "english" || !openai.isConfigured) return englishText;
      try {
        const result = await openai.chat.completions.create({
          model: process.env.GROQ_MODEL,
          temperature: 0.3,
          messages: [
            { role: "system", content: `You are an expert translator. Translate the given text into natural ${lang} with a ${style} tone. Match Malaysian conversational style (e.g., use 'lah' if Malay/Manglish).
IMPORTANT: Translate Malaysian states correctly: Johor=柔佛, Kedah=吉打, Penang=槟城, Perak=霹雳, Pahang=彭亨, Melaka=马六甲, Sabah=沙巴, Sarawak=砂拉越, Selangor=雪兰莪, Negeri Sembilan=森美兰, Kelantan=吉兰丹, Terengganu=登嘉楼, Perlis=玻璃市.
ABSOLUTELY FORBIDDEN: Do not write Chinese characters for ANY city or location names. You MUST output them exactly as in the English source. (e.g. output 'Bukit Jalil', NOT '布Kit Jalil').
Return ONLY the translated text. Do NOT add conversational responses, questions, or extra information. Just translate.` },
            { role: "user", content: englishText }
          ]
        });
        return result.choices[0].message.content.trim() || englishText;
      } catch (e) {
        return englishText;
      }
    }

    if (intent && intent.need_clarification) {
      const missing = intent.missing_fields || [];
      let msg = "";
      if (missing.includes("destination")) msg += "Where would you like to travel? ";
      if (missing.includes("duration")) msg += "How many days will your trip be? ";
      if (missing.includes("interest")) msg += "What activities are you interested in? ";
      const fallback = msg.trim() || "Could you please specify your destination and trip duration?";
      return await localize(fallback);
    }

    const intentType = intent ? intent.intent : "general_chat";

    if (intentType === "weather_check" || (toolResult && toolResult.weather)) {
      const loc = (toolResult && toolResult.location) || (intent.parameters && intent.parameters.destination) || "your destination";
      try {
        const result = await openai.chat.completions.create({
          model: process.env.GROQ_MODEL,
          temperature: 0.5,
          messages: [
            {
              role: "system",
              content: `You are Siri, an AI assistant. Provide a brief natural weather forecast for ${loc}. Mention typical temperature and conditions in ${lang}. Tone: ${style}. Adapt to the user's slang/vocabulary.`
            },
            { role: "user", content: `Weather request for ${loc}` }
          ]
        });
        const aiReply = result.choices[0].message.content.trim();
        if (aiReply) return aiReply;
      } catch (e) {
        console.log("Weather AI error:", e.message);
      }
      return await localize(`The forecast for ${loc} shows pleasant conditions with temperatures around 28°C.`);
    }

    if (intentType === "recommend_place") {
      const dest = (toolResult && toolResult.destination) || (intent.parameters && intent.parameters.destination) || "your trip";
      try {
        const result = await openai.chat.completions.create({
          model: process.env.GROQ_MODEL,
          temperature: 0.5,
          messages: [
            {
              role: "system",
              content: `You are Siri, an AI travel assistant. Briefly present the recommended places provided in the user's data naturally in ${lang} (${style} tone). Ensure strict geographical accuracy within Malaysia. DO NOT hallucinate or guess which state a city/town belongs to. If you are not 100% certain, do not mention the state.`
            },
            { role: "user", content: `Destination: ${dest}. Recommendations data: ${JSON.stringify(toolResult)}` }
          ]
        });
        const aiReply = result.choices[0].message.content.trim();
        if (aiReply) return aiReply;
      } catch (e) {
        console.log("Recommend AI error:", e.message);
      }
      const cat = (toolResult && toolResult.category) || "popular spots";
      return await localize(`Here are top recommended ${cat} to visit in ${dest}:`);
    }

    if (intentType === "update_profile") {
      return await localize("Got it! I've saved your travel preferences for future recommendations.");
    }

    if (intentType === "reroute_trip" || intentType === "traffic_check") {
      return await localize("I have found the latest traffic route updates for you.");
    }

    if (toolResult && Array.isArray(toolResult.days)) {
      const dest = (intent.parameters && intent.parameters.destination) || "your destination";
      return await localize(`I've created a ${toolResult.days.length}-day itinerary for ${dest}! Please check the timeline below for the full details.`);
    }

    if (!openai.isConfigured) {
      return await localize("I can help plan a trip, check weather, recommend places, or update your travel preferences.");
    }
    const result = await openai.chat.completions.create({
      model: process.env.GROQ_MODEL,
      temperature: 0.7,
      messages: [
        {
          role: "system",
          content: `You are Siri, a friendly AI travel assistant. Respond naturally in ${lang} (${style} tone) in 2-3 concise sentences. You MUST be geographically accurate about Malaysia.
CRITICAL RULES:
1. ABSOLUTELY FORBIDDEN: Do not write Chinese characters for ANY city, town, or place names. Always keep them in their original English/Malay text (e.g., output "Bukit Jalil", NEVER "布Kit Jalil").
2. DO NOT mention the state a city belongs to unless you are absolutely, officially 100% certain (e.g. Bukit Jalil is in Kuala Lumpur, NOT Selangor). If unsure, DO NOT mention the state at all.
3. Voice up and match the user's vocabulary.`
        },
        { role: "user", content: JSON.stringify({ intent, toolResult }) }
      ]
    });

    const content = result.choices[0].message.content.trim();
    return content || await localize("How else can I assist you with your travel plans?");
  } catch (error) {
    console.error("Response Generation Error:", error.message);
    return "I'm here to help with your trip planning, weather updates, and recommendations!";
  }
}

module.exports = {
  generateResponse
};
