const openai = require("../config/openai");

async function getRecommendations(destination, category, userProfile = {}, excludedLocations = []) {
  try {
    const excludeInstruction = excludedLocations.length > 0
      ? `\nCRITICAL: DO NOT recommend anything in, related to, or categorized under the following locations or themes: ${excludedLocations.join(", ")}.`
      : "";

    const result = await openai.chat.completions.create({
      model: process.env.GROQ_MODEL,
      temperature: 0.5,
      response_format: { type: "json_object" },
      messages: [
        {
          role: "system",
          content: `You are a localized travel recommendation engine. Ensure strict geographical accuracy within Malaysia. DO NOT hallucinate or guess which state a city/town belongs to. If you are not 100% certain, do not mention the state.${excludeInstruction}
Return JSON ONLY in format:
{
  "destination": "${destination}",
  "category": "${category}",
  "recommendations": [
    {
      "name": "Attraction Name",
      "description": "Short explanation",
      "rating": 4.8,
      "tag": "Must Visit"
    }
  ]
}`
        },
        {
          role: "user",
          content: `Recommend 4 top places in Malaysia matching category: ${category}. Preferred destination area (if any): ${destination}. Traveler preferences: ${JSON.stringify(userProfile)}`
        }
      ]
    });

    return JSON.parse(result.choices[0].message.content);
  } catch (error) {
    console.log("Recommendation service fallback:", error.message);
    return {
      destination,
      category,
      recommendations: [
        { name: `${category || "Top"} Spot in ${destination}`, description: "Popular local attraction.", rating: 4.8, tag: "Popular" },
        { name: `Cultural Heritage Center`, description: "Explore the local heritage and arts.", rating: 4.7, tag: "Culture" },
        { name: `Scenic Viewpoint`, description: "Breathtaking panoramic view of the area.", rating: 4.9, tag: "Nature" },
        { name: `Famous Local Eatery`, description: "Authentic local food experience.", rating: 4.6, tag: "Foodie" }
      ]
    };
  }
}

module.exports = {
  getRecommendations
};
