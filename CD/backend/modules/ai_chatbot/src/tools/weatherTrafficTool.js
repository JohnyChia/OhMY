const weatherTool = require("./weatherTool");

async function checkWeatherAndTraffic(location, date = null) {
  const weather = await weatherTool.get({ destination: location, travel_date: date || "today" });
  return {
    success: weather.success === true,
    location,
    weather,
    traffic: {
      unavailable: true,
      error: "Verified live traffic is unavailable right now."
    }
  };
}

module.exports = {
  checkWeatherAndTraffic
};
