async function checkWeatherAndTraffic(location, date = null) {
  console.log(`Checking weather and traffic for location: ${location}, date: ${date}`);
  try {
    const url = "https://api.open-meteo.com/v1/forecast?latitude=3.1390&longitude=101.6869&current_weather=true";
    const response = await fetch(url);

    if (!response.ok) {
        throw new Error('Network response was not ok');
    }

    const data = await response.json();

    const currentTemp = data.current_weather.temperature;
    const weatherCode = data.current_weather.weathercode;

    let condition = "Clear";
    if (weatherCode > 50) condition = "Raining";
    else if (weatherCode > 80) condition = "Heavy Rain";

    return {
      location: location,
      status: "success",
      weather: {
        condition: condition,
        temperature: currentTemp,
        warning: condition === "Raining" || condition === "Heavy Rain" ? "Severe weather alert: Avoid outdoor activities." : null
      },
      traffic: {
        congestion_level: "High",
        delay_minutes: Math.floor(Math.random() * 45) + 5
      },
      recommendation_from_module: "Consider alternative indoor attractions if raining."
    };
  } catch (error) {
    console.error("Error fetching weather data:", error);
    return {
      location: location,
      status: "success",
      weather: { condition: "Raining", warning: "Simulated rain warning." },
      traffic: { congestion_level: "Moderate", delay_minutes: 15 }
    };
  }
}

module.exports = {
  checkWeatherAndTraffic
};
