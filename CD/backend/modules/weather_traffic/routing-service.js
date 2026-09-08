const GOOGLE_ROUTES_URL = "https://routes.googleapis.com/directions/v2:computeRoutes";

function apiKey() {
    const key = process.env.GOOGLE_ROUTES_API_KEY || process.env.GOOGLE_PLACES_API_KEY;
    if (!key) throw new Error("GOOGLE_ROUTES_API_KEY or GOOGLE_PLACES_API_KEY is not configured.");
    return key;
}

function coordinate(value, minimum, maximum, name) {
    const number = Number(value);
    if (!Number.isFinite(number) || number < minimum || number > maximum) {
        throw new Error(`Invalid ${name}.`);
    }
    return number;
}

function seconds(value) {
    return Number.parseFloat(String(value || "0s").replace("s", "")) || 0;
}

async function computeDrivingRoutes(input) {
    const startLat = coordinate(input.startLat, -90, 90, "start latitude");
    const startLon = coordinate(input.startLon, -180, 180, "start longitude");
    const endLat = coordinate(input.endLat, -90, 90, "destination latitude");
    const endLon = coordinate(input.endLon, -180, 180, "destination longitude");
    const response = await fetch(GOOGLE_ROUTES_URL, {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": apiKey(),
            "X-Goog-FieldMask": [
                "routes.duration",
                "routes.staticDuration",
                "routes.distanceMeters",
                "routes.polyline.encodedPolyline",
                "routes.legs.steps.distanceMeters",
                "routes.legs.steps.navigationInstruction",
                "routes.legs.steps.startLocation",
                "routes.legs.steps.endLocation"
            ].join(",")
        },
        body: JSON.stringify({
            origin: { location: { latLng: { latitude: startLat, longitude: startLon } } },
            destination: { location: { latLng: { latitude: endLat, longitude: endLon } } },
            travelMode: "DRIVE",
            languageCode: "en",
            units: "METRIC",
            routingPreference: "TRAFFIC_AWARE_OPTIMAL",
            polylineQuality: "HIGH_QUALITY",
            polylineEncoding: "ENCODED_POLYLINE",
            computeAlternativeRoutes: true
        })
    });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error?.message || `Google Routes failed (${response.status}).`);
    const routes = (data.routes || []).map((route, index) => {
        const durationSeconds = seconds(route.duration);
        const staticSeconds = seconds(route.staticDuration);
        const ratio = staticSeconds > 0 ? durationSeconds / staticSeconds : 1;
        const traffic = ratio >= 1.5 ? "Heavy traffic" : ratio >= 1.15 ? "Moderate traffic" : ratio >= 1.05 ? "Light traffic" : "Normal traffic";
        const distanceMeters = Number(route.distanceMeters || 0);
        const steps = (route.legs || []).flatMap((leg) =>
            (leg.steps || []).map((step) => ({
                instruction: step.navigationInstruction?.instructions || "Continue on the route",
                maneuver: step.navigationInstruction?.maneuver || "STRAIGHT",
                distanceMeters: Number(step.distanceMeters || 0),
                start: {
                    lat: step.startLocation?.latLng?.latitude ?? null,
                    lon: step.startLocation?.latLng?.longitude ?? null
                },
                end: {
                    lat: step.endLocation?.latLng?.latitude ?? null,
                    lon: step.endLocation?.latLng?.longitude ?? null
                }
            })).filter((step) => step.start.lat != null && step.end.lat != null)
        );
        return {
            routeIndex: index,
            durationMinutes: Math.max(1, Math.round(durationSeconds / 60)),
            distanceKm: Number((distanceMeters / 1000).toFixed(2)),
            traffic,
            geometry: route.polyline?.encodedPolyline || "",
            steps
        };
    }).filter((route) => route.geometry);
    if (!routes.length) throw new Error("No driving route found.");
    return { start: { lat: startLat, lon: startLon }, destination: { lat: endLat, lon: endLon }, routes };
}

module.exports = { computeDrivingRoutes };
