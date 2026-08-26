const GOOGLE_WEATHER_BASE_URL = "https://weather.googleapis.com/v1";
const GOOGLE_GEOCODING_URL = "https://maps.googleapis.com/maps/api/geocode/json";
const CACHE_TTL_MS = 5 * 60 * 1000;
const cache = new Map();

function apiKey() {
    const key = process.env.GOOGLE_WEATHER_API_KEY || process.env.GOOGLE_PLACES_API_KEY;
    if (!key) throw new Error("GOOGLE_WEATHER_API_KEY or GOOGLE_PLACES_API_KEY is not configured.");
    return key;
}

function validateCoordinate(value, minimum, maximum, name) {
    const number = Number(value);
    if (!Number.isFinite(number) || number < minimum || number > maximum) throw new Error(`Invalid ${name}.`);
    return number;
}

async function fetchGoogleWeather(resource, latitude, longitude, extra = {}) {
    const url = new URL(`${GOOGLE_WEATHER_BASE_URL}/${resource}:lookup`);
    url.searchParams.set("key", apiKey());
    url.searchParams.set("location.latitude", latitude);
    url.searchParams.set("location.longitude", longitude);
    url.searchParams.set("unitsSystem", "METRIC");
    url.searchParams.set("languageCode", "en");
    for (const [name, value] of Object.entries(extra)) url.searchParams.set(name, value);
    const response = await fetch(url);
    const data = await response.json();
    if (!response.ok) throw new Error(data.error?.message || `Google Weather API failed (${response.status}).`);
    return data;
}

async function lookupArea(latitude, longitude) {
    const url = new URL(GOOGLE_GEOCODING_URL);
    url.searchParams.set("latlng", `${latitude},${longitude}`);
    url.searchParams.set("key", apiKey());
    url.searchParams.set("language", "en");
    try {
        const response = await fetch(url);
        const data = await response.json();
        if (!response.ok || data.status !== "OK") return null;
        const components = data.results?.[0]?.address_components || [];
        for (const type of ["locality", "administrative_area_level_2", "administrative_area_level_1"]) {
            const component = components.find((item) => item.types?.includes(type));
            if (component?.long_name) return component.long_name;
        }
        return data.results?.[0]?.formatted_address || null;
    } catch {
        return null;
    }
}

function timestamp(value) {
    const milliseconds = Date.parse(value || "");
    return Number.isFinite(milliseconds) ? Math.floor(milliseconds / 1000) : 0;
}

function displayTimestamp(displayDateTime, fallback) {
    if (!displayDateTime) return timestamp(fallback);
    return Math.floor(Date.UTC(
        displayDateTime.year,
        (displayDateTime.month || 1) - 1,
        displayDateTime.day || 1,
        displayDateTime.hours || 0,
        displayDateTime.minutes || 0
    ) / 1000);
}

function weatherEntry(entry, timeField) {
    const condition = entry.weatherCondition || {};
    return {
        timestamp: timestamp(timeField),
        temperatureC: entry.temperature?.degrees ?? null,
        feelsLikeC: entry.feelsLikeTemperature?.degrees ?? null,
        condition: condition.type || "UNAVAILABLE",
        description: condition.description?.text || "Unavailable",
        iconCode: condition.iconBaseUri || null,
        rainProbability: entry.precipitation?.probability?.percent ?? 0,
        humidity: entry.relativeHumidity ?? null,
        windSpeedMetresPerSecond: entry.wind?.speed?.value == null
            ? null
            : entry.wind.speed.value / 3.6
    };
}

async function getWeatherOverview(latitudeValue, longitudeValue) {
    const latitude = validateCoordinate(latitudeValue, -90, 90, "latitude");
    const longitude = validateCoordinate(longitudeValue, -180, 180, "longitude");
    const cacheKey = `${latitude.toFixed(3)},${longitude.toFixed(3)}`;
    const cached = cache.get(cacheKey);
    if (cached && Date.now() - cached.createdAt < CACHE_TTL_MS) return cached.value;

    const [current, forecast, areaName] = await Promise.all([
        fetchGoogleWeather("currentConditions", latitude, longitude),
        fetchGoogleWeather("forecast/hours", latitude, longitude, { hours: 8, pageSize: 8 }),
        lookupArea(latitude, longitude)
    ]);
    const value = {
        locationName: areaName || "Current area",
        countryCode: null,
        latitude,
        longitude,
        current: weatherEntry(current, current.currentTime),
        hourly: (forecast.forecastHours || []).slice(0, 8).map((entry) => ({
            ...weatherEntry(entry, entry.interval?.startTime),
            timestamp: displayTimestamp(entry.displayDateTime, entry.interval?.startTime)
        })),
        timezoneOffsetSeconds: 0,
        timeZoneId: forecast.timeZone?.id || current.timeZone?.id || null,
        provider: "Google Weather API"
    };
    cache.set(cacheKey, { createdAt: Date.now(), value });
    return value;
}

module.exports = { getWeatherOverview };
