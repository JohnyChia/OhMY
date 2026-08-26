const openai = require("../config/openai");

async function get(params) {
  const location = params.destination || params.location || params.place || "Destination";
  const travelDate = params.travel_date || "tomorrow";

  let weatherDesc = "29°C - Partly cloudy with light tropical breeze";

  try {
    const url = "https://api.open-meteo.com/v1/forecast?latitude=3.1390&longitude=101.6869&current_weather=true";
    const response = await fetch(url);
    if (response.ok) {
      const data = await response.json();
      const currentTemp = data.current_weather.temperature;
      const weatherCode = data.current_weather.weathercode;

      let condition = "Clear";
      if (weatherCode > 50) condition = "Raining";
      else if (weatherCode > 80) condition = "Heavy Rain";

      weatherDesc = `${currentTemp}°C - ${condition}`;
    }
  } catch (err) {
    console.log("Weather API fallback:", err.message);
  }

  return {
    location: location,
    date: travelDate,
    weather: weatherDesc
  };
}

module.exports = {
  get
};
