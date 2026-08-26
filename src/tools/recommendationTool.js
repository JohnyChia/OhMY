const recommendationService = require("../services/recommendationService");

async function get(params) {
  const destination = params.destination || "";
  const category =
    params.category ||
    (Array.isArray(params.interest) && params.interest.length > 0
      ? params.interest[0]
      : "general");

  let excluded = params.excluded_locations || [];
  if (typeof excluded === "string") {
    excluded = [excluded];
  }

  const data = await recommendationService.getRecommendations(destination, category, {}, excluded);
  return data;
}

module.exports = {
  get
};