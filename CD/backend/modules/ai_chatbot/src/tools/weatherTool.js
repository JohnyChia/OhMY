const weatherLabels = {
  0: "Clear", 1: "Mostly clear", 2: "Partly cloudy", 3: "Overcast",
  45: "Foggy", 48: "Foggy", 51: "Light drizzle", 53: "Drizzle",
  55: "Heavy drizzle", 61: "Light rain", 63: "Rain", 65: "Heavy rain",
  71: "Light snow", 73: "Snow", 75: "Heavy snow", 80: "Rain showers",
  81: "Rain showers", 82: "Heavy rain showers", 95: "Thunderstorm",
  96: "Thunderstorm with hail", 99: "Thunderstorm with hail"
};
const { getWeatherOverview } = require('../../../weather_traffic/weather-service');

function normalizeMalaysiaLocation(value) {
  // Keep user/provider text intact. Google/Open-Meteo perform geographic
  // resolution, so application code never substitutes a named destination.
  return String(value || '').trim();
}

function requestedLocationLabel(displayLocation, providerLocation) {
  return String(displayLocation || '').trim() || String(providerLocation || '').trim();
}

function isMalaysiaGeocodeResult(place) {
  return Array.isArray(place?.address_components) && place.address_components
    .some((component) =>
      Array.isArray(component.types) &&
      component.types.includes('country') &&
      String(component.short_name || '').toUpperCase() === 'MY');
}

async function getGoogleWeatherForLocation(location, travelDate, displayLocation) {
  const key = process.env.GOOGLE_WEATHER_API_KEY || process.env.GOOGLE_PLACES_API_KEY;
  if (!key) throw new Error('Google Weather API is not configured.');

  const geocodeUrl = new URL('https://maps.googleapis.com/maps/api/geocode/json');
  geocodeUrl.searchParams.set('address', location);
  geocodeUrl.searchParams.set('region', 'my');
  geocodeUrl.searchParams.set('key', key);
  const geocodeResponse = await fetch(geocodeUrl, { signal: AbortSignal.timeout(8000) });
  const geocode = await geocodeResponse.json();
  const place = geocode.results?.[0];
  const coordinates = place?.geometry?.location;
  if (!geocodeResponse.ok || geocode.status !== 'OK' || !coordinates) {
    throw new Error(`Google geocoding could not verify ${location}.`);
  }
  if (!isMalaysiaGeocodeResult(place)) {
    const error = new Error('Nova only supports weather and travel within Malaysia.');
    error.code = 'OUT_OF_SCOPE';
    throw error;
  }

  const overview = await getWeatherOverview(coordinates.lat, coordinates.lng);
  const current = overview.current;
  if (typeof current?.temperatureC !== 'number') {
    throw new Error('Google Weather API returned no current conditions.');
  }
  return {
    success: true,
    // Preserve the location requested by the user in the public response.
    // Reverse-geocoded locality names are provider metadata and must not turn
    // a region-level request into a nearby provider locality.
    location: requestedLocationLabel(displayLocation, overview.locationName || location),
    display_location: displayLocation,
    canonical_location: overview.locationName || location,
    date: travelDate,
    weather: `${current.temperatureC}°C - ${current.description}`,
    observed_at: String(current.timestamp || ''),
    provider: overview.provider || 'Google Weather API',
  };
}

async function get(params) {
  const displayLocation = String(
    params.destination || params.location || params.place || '',
  ).trim();
  const requestedLocation = normalizeMalaysiaLocation(displayLocation);
  const travelDate = String(params.travel_date || "today");
  if (!requestedLocation) return { success: false, unavailable: true, error: "A destination is needed for weather." };

  let googleOutOfScope = false;
  try {
    // Reuse the live Google Weather service owned by the existing Weather /
    // Start Trip backend. This is the authoritative path for Nova weather.
    return await getGoogleWeatherForLocation(
      requestedLocation,
      travelDate,
      displayLocation,
    );
  } catch (googleError) {
    if (googleError?.code === 'OUT_OF_SCOPE') {
      // A region-biased Google result can still choose a foreign namesake for
      // noisy speech. Continue to the Malaysia-filtered provider before
      // concluding that the user's request is outside the supported country.
      googleOutOfScope = true;
    } else {
      console.warn('Google Weather provider unavailable:', googleError.message);
    }
  }

  try {
    const geocodeUrl = new URL("https://geocoding-api.open-meteo.com/v1/search");
    geocodeUrl.searchParams.set("name", requestedLocation);
    geocodeUrl.searchParams.set("count", "10");
    const geocodeResponse = await fetch(geocodeUrl, { signal: AbortSignal.timeout(8000) });
    if (!geocodeResponse.ok) throw new Error(`Geocoding returned ${geocodeResponse.status}`);
    const geocode = await geocodeResponse.json();
    const place = (geocode.results || []).find((candidate) => String(candidate.country_code || "").toUpperCase() === "MY");
    if (!place) {
      return {
        success: false,
        unavailable: true,
        code: googleOutOfScope ? 'OUT_OF_SCOPE' : 'LOCATION_UNVERIFIED',
        scope_unverified: googleOutOfScope,
        error: googleOutOfScope
          ? `The destination ${requestedLocation} is outside Malaysia.`
          : `I could not verify weather for ${requestedLocation}.`,
      };
    }

    const forecastUrl = new URL("https://api.open-meteo.com/v1/forecast");
    forecastUrl.searchParams.set("latitude", String(place.latitude));
    forecastUrl.searchParams.set("longitude", String(place.longitude));
    forecastUrl.searchParams.set("current_weather", "true");
    const forecastResponse = await fetch(forecastUrl, { signal: AbortSignal.timeout(8000) });
    if (!forecastResponse.ok) throw new Error(`Forecast returned ${forecastResponse.status}`);
    const forecast = await forecastResponse.json();
    const current = forecast.current_weather;
    if (!current || typeof current.temperature !== "number") throw new Error("Weather data missing.");

    return {
      success: true,
      location: requestedLocationLabel(displayLocation, place.name),
      display_location: displayLocation,
      canonical_location: place.name,
      date: travelDate,
      weather: `${current.temperature}°C - ${weatherLabels[current.weathercode] || "Unknown conditions"}`,
      observed_at: current.time
    };
  } catch (error) {
    console.warn("Weather provider unavailable:", error.message);
    return { success: false, unavailable: true, error: `Weather is unavailable for ${requestedLocation} right now.` };
  }
}

module.exports = {
  get,
  normalizeMalaysiaLocation,
  requestedLocationLabel,
  isMalaysiaGeocodeResult,
  getGoogleWeatherForLocation,
};
