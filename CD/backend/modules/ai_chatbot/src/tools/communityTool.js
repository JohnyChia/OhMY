const { discoverCommunity } = require("../services/communityService");

async function get(params) {
  return discoverCommunity(params.query || params.destination || "");
}

module.exports = { get };
