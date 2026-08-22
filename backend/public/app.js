const state = {
  map: null,
  marker: null,
  userMarker: null,
  nearbyMarkers: [],
  boundaryLayers: [],
  boundaryFallback: null,
  mapId: null,
  selectedDestinationId: null,
};

const elements = {
  form: document.querySelector("#search-form"),
  input: document.querySelector("#search-input"),
  results: document.querySelector("#search-results"),
  status: document.querySelector("#map-status"),
  empty: document.querySelector("#empty-state"),
  loading: document.querySelector("#loading-state"),
  details: document.querySelector("#place-details"),
  nearbyButton: document.querySelector("#nearby-button"),
  destinationNearbyButton: document.querySelector("#destination-nearby-button"),
};

function loadGoogleMaps(apiKey, mapId) {
  return new Promise((resolve, reject) => {
    window.initializeCultureRouteMap = () => {
      state.mapId = mapId;
      const mapOptions = {
        center: { lat: 3.139, lng: 101.6869 },
        zoom: 12,
        mapTypeControl: false,
        streetViewControl: false,
        fullscreenControl: false,
      };

      if (mapId) {
        mapOptions.mapId = mapId;
      } else {
        mapOptions.styles = [
          { featureType: "poi", elementType: "labels", stylers: [{ visibility: "off" }] },
          { featureType: "road", elementType: "geometry", stylers: [{ color: "#ffffff" }] },
          { featureType: "landscape", elementType: "geometry", stylers: [{ color: "#e7f0ea" }] },
          { featureType: "water", elementType: "geometry", stylers: [{ color: "#bfd9ee" }] },
        ];
      }

      state.map = new google.maps.Map(
        document.querySelector("#map"),
        mapOptions,
      );
      resolve();
    };

    const script = document.createElement("script");
    script.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(apiKey)}&v=beta&callback=initializeCultureRouteMap`;
    script.async = true;
    script.defer = true;
    script.onerror = () => reject(new Error("Google Maps could not be loaded."));
    document.head.append(script);
  });
}

async function initializeMap() {
  try {
    const response = await fetch("/api/config/maps");
    const config = await response.json();
    if (!response.ok) throw new Error(config.error);
    await loadGoogleMaps(config.apiKey, config.mapId);
  } catch (error) {
    elements.status.textContent = error.message;
  }
}

function setView(view) {
  elements.empty.hidden = view !== "empty";
  elements.loading.hidden = view !== "loading";
  elements.details.hidden = view !== "details";
}

function createResultButton(place) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "result-item";

  const topLine = document.createElement("span");
  topLine.className = "result-title";

  const name = document.createElement("strong");
  name.textContent = place.displayName?.text || "Unnamed attraction";

  const badge = document.createElement("i");
  badge.className = place.isArea ? "result-badge area" : "result-badge place";
  badge.textContent = place.isArea ? "Area" : "Place";

  const address = document.createElement("span");
  address.className = "result-address";
  address.textContent = place.formattedAddress || "Address unavailable";

  topLine.append(name, badge);
  button.append(topLine, address);
  button.addEventListener(
    "click",
    () => place.isArea
      ? focusArea(place)
      : analysePlace(place.id)
  );

  return button;
}

function appendResultGroup(title, places) {
  if (places.length === 0) return;

  const heading = document.createElement("p");
  heading.className = "result-group-heading";
  heading.textContent = title;
  elements.results.append(heading);

  for (const place of places) {
    elements.results.append(createResultButton(place));
  }
}

function renderResults(places) {
  elements.results.replaceChildren();

  const areas = places.filter(place => place.isArea);
  const attractions = places.filter(place => !place.isArea);

  appendResultGroup("Areas", areas);
  appendResultGroup("Places in this search", attractions);

  elements.results.hidden = places.length === 0;
}

function clearAreaBoundary() {
  state.boundaryFallback?.setMap(null);
  state.boundaryFallback = null;

  for (const layer of state.boundaryLayers) {
    layer.style = null;
  }
  state.boundaryLayers = [];
}

function viewportBounds(viewport) {
  if (!viewport?.low || !viewport?.high) return null;

  return {
    south: viewport.low.latitude,
    west: viewport.low.longitude,
    north: viewport.high.latitude,
    east: viewport.high.longitude,
  };
}

function highlightExactBoundary(place) {
  if (!state.mapId || typeof state.map.getFeatureLayer !== "function") {
    return false;
  }

  let matchFound = false;
  const featureTypes = [
    "LOCALITY",
    "ADMINISTRATIVE_AREA_LEVEL_2",
    "ADMINISTRATIVE_AREA_LEVEL_1",
    "POSTAL_CODE",
  ];

  for (const featureType of featureTypes) {
    try {
      const layer = state.map.getFeatureLayer(featureType);
      layer.style = ({ feature }) => {
        if (feature.placeId !== place.id) return {};
        matchFound = true;
        state.boundaryFallback?.setMap(null);
        return {
          strokeColor: "#e53935",
          strokeOpacity: 1,
          strokeWeight: 3,
          fillColor: "#e53935",
          fillOpacity: 0.08,
        };
      };
      state.boundaryLayers.push(layer);
    } catch (_) {
      // This boundary type may not be available for the configured map.
    }
  }

  return matchFound;
}

function focusArea(place) {
  if (!state.map || !place.location) return;

  elements.results.hidden = true;
  state.marker?.setMap(null);
  state.marker = null;
  clearAreaBoundary();

  const bounds = viewportBounds(place.viewport);
  const position = {
    lat: place.location.latitude,
    lng: place.location.longitude,
  };

  if (bounds) {
    state.map.fitBounds(bounds, 42);
    state.boundaryFallback = new google.maps.Rectangle({
      map: state.map,
      bounds,
      clickable: false,
      strokeColor: "#e53935",
      strokeOpacity: 0.9,
      strokeWeight: 2,
      fillColor: "#e53935",
      fillOpacity: 0.04,
    });
  } else {
    state.map.setCenter(position);
    state.map.setZoom(13);
  }

  highlightExactBoundary(place);
  setView("empty");
  elements.status.textContent = `${place.displayName?.text || "Area"} selected · choose a place from the search results`;
}

function renderTags(containerId, tags) {
  const container = document.querySelector(`#${containerId}`);
  container.replaceChildren();

  if (tags.length === 0) {
    const empty = document.createElement("span");
    empty.className = "empty-tag";
    empty.textContent = "No tags assigned";
    container.append(empty);
    return;
  }

  for (const tagName of tags) {
    const tag = document.createElement("span");
    tag.className = "tag";
    tag.textContent = tagName;
    container.append(tag);
  }
}

function clearNearbyMarkers() {
  state.userMarker?.setMap(null);
  state.userMarker = null;
  for (const marker of state.nearbyMarkers) {
    marker.setMap(null);
  }
  state.nearbyMarkers = [];
}

function renderEvidence(analysis) {
  const container = document.querySelector("#tag-evidence");
  container.replaceChildren();
  const tags = [...analysis.generalTags, ...analysis.culturalTags];

  for (const tagName of tags) {
    const stat = analysis.statistics[tagName];
    const row = document.createElement("div");
    row.className = "evidence-item";
    row.innerHTML = `
      <strong></strong>
      <span></span>
      <div class="evidence-bar"><div class="evidence-fill"></div></div>
    `;
    row.querySelector("strong").textContent = tagName;
    row.querySelector("span").textContent = `${stat.supportingReviews}/${analysis.reviewCount} reviews · score ${stat.averageScore}`;
    row.querySelector(".evidence-fill").style.width = `${Math.min(100, stat.supportPercentage * 100)}%`;
    container.append(row);
  }
}

function renderPlace(data, preserveNearbyMarkers = false) {
  const { place, analysis, performance } = data;
  document.querySelector("#place-name").textContent = place.displayName?.text || "Selected attraction";
  document.querySelector("#place-address").textContent = place.formattedAddress || "";
  document.querySelector("#place-rating").textContent = place.rating ?? "—";
  document.querySelector("#review-count").textContent = analysis.reviewCount;
  document.querySelector("#tagging-time").textContent = `${performance.taggingMs.toFixed(3)} ms`;
  document.querySelector("#maps-link").href = place.googleMapsUri || "#";

  if (!preserveNearbyMarkers && !data.ranking) {
    state.selectedDestinationId = place.id;
    elements.destinationNearbyButton.hidden = false;
  }

  const distanceMeta = document.querySelector("#distance-meta");
  if (Number.isFinite(place.distanceKm)) {
    document.querySelector("#place-distance").textContent = place.distanceKm.toFixed(2);
    distanceMeta.hidden = false;
  } else {
    distanceMeta.hidden = true;
  }

  const rankingMeta = document.querySelector("#ranking-meta");
  if (data.ranking && Number.isFinite(data.rank)) {
    document.querySelector("#place-rank").textContent = `Rank #${data.rank}`;
    document.querySelector("#place-similarity").textContent = data.ranking.similarityPercentage.toFixed(1);
    rankingMeta.hidden = false;
  } else {
    rankingMeta.hidden = true;
  }

  renderTags("general-tags", analysis.generalTags);
  renderTags("cultural-tags", analysis.culturalTags);
  renderTags("matched-preferences", data.matchedPreferences || []);
  renderEvidence(analysis);

  const position = {
    lat: place.location.latitude,
    lng: place.location.longitude,
  };

  if (state.map) {
    clearAreaBoundary();
    if (!preserveNearbyMarkers) {
      clearNearbyMarkers();
      state.marker?.setMap(null);
      state.marker = new google.maps.Marker({
        map: state.map,
        position,
        title: place.displayName?.text,
        animation: google.maps.Animation.DROP,
      });
    }
    state.map.panTo(position);
    if (!preserveNearbyMarkers) state.map.setZoom(15);
  }

  elements.status.textContent = preserveNearbyMarkers
    ? `${(data.matchedPreferences || []).length} preference matches · ${place.distanceKm.toFixed(2)} km away`
    : `${analysis.reviewCount} reviews analysed · ${analysis.generalTags.length + analysis.culturalTags.length} tags assigned`;
  setView("details");
}

function getCurrentPosition() {
  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) {
      reject(new Error("This browser does not support location access."));
      return;
    }

    navigator.geolocation.getCurrentPosition(
      resolve,
      error => {
        const messages = {
          1: "Location permission was denied.",
          2: "Your current location is unavailable.",
          3: "Getting your location timed out.",
        };
        reject(new Error(messages[error.code] || "Unable to get your location."));
      },
      {
        enableHighAccuracy: true,
        timeout: 12_000,
        maximumAge: 60_000,
      },
    );
  });
}

function renderNearbyPlaces(response) {
  if (!state.map) return;

  clearAreaBoundary();
  clearNearbyMarkers();
  state.marker?.setMap(null);
  state.marker = null;

  const bounds = new google.maps.LatLngBounds();
  const origin = {
    lat: response.origin.latitude,
    lng: response.origin.longitude,
  };

  state.userMarker = new google.maps.Marker({
    map: state.map,
    position: origin,
    title: "Your current location",
    zIndex: 1000,
    icon: {
      path: google.maps.SymbolPath.CIRCLE,
      scale: 9,
      fillColor: "#3266cc",
      fillOpacity: 1,
      strokeColor: "#ffffff",
      strokeWeight: 3,
    },
  });
  bounds.extend(origin);

  for (const item of response.taggedPlaces) {
    const position = {
      lat: item.place.location.latitude,
      lng: item.place.location.longitude,
    };
    const matched = item.matchedPreferences.length > 0;
    const topRecommendation = matched && item.rank <= 5;
    const marker = new google.maps.Marker({
      map: state.map,
      position,
      title: matched
        ? `#${item.rank} ${item.place.displayName?.text || "Place"} · ${item.ranking.similarityPercentage}% match`
        : `${item.place.displayName?.text || "Place"} · no preference match`,
      zIndex: topRecommendation ? 200 : matched ? 100 : 10,
      icon: {
        path: google.maps.SymbolPath.CIRCLE,
        scale: topRecommendation ? 12 : matched ? 9 : 7,
        fillColor: topRecommendation ? "#d92723" : matched ? "#f28b3c" : "#78909c",
        fillOpacity: matched ? 1 : 0.75,
        strokeColor: "#ffffff",
        strokeWeight: 2,
      },
    });
    marker.addListener("click", () => renderPlace(item, true));
    state.nearbyMarkers.push(marker);
    bounds.extend(position);
  }

  state.map.fitBounds(bounds, 60);
  elements.status.textContent = `${response.matchedCount} matched · ${response.taggedCount} tagged · ${response.candidateCount} candidates`;

  const firstMatch = response.matchedPlaces[0];
  if (firstMatch) {
    renderPlace(firstMatch, true);
  } else {
    setView("empty");
  }
}

async function loadNearbyRecommendations(mode = "preferences") {
  if (mode === "destination" && !state.selectedDestinationId) {
    elements.status.textContent = "Search and select a destination first.";
    return;
  }

  elements.nearbyButton.disabled = true;
  elements.destinationNearbyButton.disabled = true;
  elements.results.hidden = true;
  setView("loading");
  elements.status.textContent = "Getting your current location…";

  try {
    const currentPosition = await getCurrentPosition();
    elements.status.textContent = "Discovering and tagging nearby places…";

    const response = await fetch("/api/recommendations/nearby-tagged", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        latitude: currentPosition.coords.latitude,
        longitude: currentPosition.coords.longitude,
        mode,
        ...(mode === "destination"
          ? { destinationPlaceId: state.selectedDestinationId }
          : {
              preferences: [
                "Museum",
                "Heritage",
                "Cultural Learning",
                "Nature",
                "Religious Heritage",
              ],
            }),
      }),
    });
    const data = await response.json();
    if (!response.ok) {
      throw new Error(data.error || "Nearby tagging failed.");
    }
    renderNearbyPlaces(data);
  } catch (error) {
    setView("empty");
    elements.status.textContent = error.message;
  } finally {
    elements.nearbyButton.disabled = false;
    elements.destinationNearbyButton.disabled = false;
  }
}

async function analysePlace(placeId) {
  elements.results.hidden = true;
  setView("loading");

  try {
    const response = await fetch("/api/places/analyze", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ placeId }),
    });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || "Place analysis failed.");
    renderPlace(data);
  } catch (error) {
    setView("empty");
    elements.status.textContent = error.message;
  }
}

elements.form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const query = elements.input.value.trim();
  if (!query) return;

  elements.status.textContent = "Searching Google Places…";
  elements.results.hidden = true;

  try {
    const response = await fetch("/api/places/search", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query }),
    });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || "Search failed.");
    renderResults(data.places || []);
    const area = data.places?.find(place => place.isArea);
    if (area) focusArea(area);
    elements.results.hidden = !(data.places?.length);
    elements.status.textContent = data.places?.length
      ? `${data.places.length} area and place results found.`
      : "No places found.";
  } catch (error) {
    elements.status.textContent = error.message;
  }
});

elements.nearbyButton.addEventListener(
  "click",
  () => loadNearbyRecommendations("preferences"),
);
elements.destinationNearbyButton.addEventListener(
  "click",
  () => loadNearbyRecommendations("destination"),
);

initializeMap();
