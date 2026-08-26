const state = {
  map: null,
  marker: null,
  userMarker: null,
  nearbyMarkers: [],
  boundaryLayers: [],
  boundaryFallback: null,
  mapId: null,
  selectedDestinationId: null,
  selectedRecommendation: null,
  selectedPreview: null,
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
  recommendationDrawer: document.querySelector("#recommendation-drawer"),
  recommendationTrack: document.querySelector("#recommendation-track"),
  recommendationTitle: document.querySelector("#recommendation-title"),
  detailPage: document.querySelector("#place-detail-page"),
  selectionPreview: document.querySelector("#selection-preview"),
};

function placePhotoUrl(photo) {
  return photo?.name
    ? `/api/places/photo?name=${encodeURIComponent(photo.name)}`
    : null;
}

function allAssignedTags(item) {
  return [
    ...(item.analysis?.generalTags || []),
    ...(item.analysis?.culturalTags || []),
  ];
}

function placeDescription(place) {
  if (place.description) return place.description;
  if (place.primaryTypeDisplayName) {
    return `${place.primaryTypeDisplayName} located at ${place.formattedAddress || "this destination"}.`;
  }
  return "Description unavailable.";
}

function displayDistance(place) {
  const distance = Number.isFinite(place.routeDistanceKm)
    ? place.routeDistanceKm
    : place.distanceKm;
  return Number.isFinite(distance) ? `${distance.toFixed(1)} km` : "Unavailable";
}

function displayEta(place) {
  return Number.isFinite(place.etaMinutes)
    ? `${place.etaEstimated ? "~" : ""}${place.etaMinutes} min`
    : "Unavailable";
}

function createPhotoFallback() {
  const fallback = document.createElement("div");
  fallback.className = "photo-unavailable";
  const icon = document.createElement("span");
  icon.className = "material-icon";
  icon.textContent = "image_not_supported";
  const label = document.createElement("span");
  label.textContent = "Picture unavailable";
  fallback.append(icon, label);
  return fallback;
}

function straightLineDistanceKm(origin, destination) {
  const toRadians = value => value * Math.PI / 180;
  const earthRadiusKm = 6371;
  const latitudeDelta = toRadians(destination.latitude - origin.latitude);
  const longitudeDelta = toRadians(destination.longitude - origin.longitude);
  const value = Math.sin(latitudeDelta / 2) ** 2
    + Math.cos(toRadians(origin.latitude))
      * Math.cos(toRadians(destination.latitude))
      * Math.sin(longitudeDelta / 2) ** 2;
  return earthRadiusKm * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value));
}

function showSelectionPreview(item) {
  state.selectedPreview = item;
  const place = item.place;
  document.querySelector("#selection-preview-name").textContent =
    place.displayName?.text || "Selected place";
  document.querySelector("#selection-preview-description").textContent =
    placeDescription(place);
  document.querySelector("#selection-preview-eta").textContent = displayEta(place);
  document.querySelector("#selection-preview-distance").textContent = displayDistance(place);
  const tagsContainer = document.querySelector("#selection-preview-tags");
  const assignedTags = allAssignedTags(item);
  tagsContainer.replaceChildren();
  if (assignedTags.length === 0) {
    const empty = document.createElement("span");
    empty.className = "no-preview-tags";
    empty.textContent = "No tags assigned";
    tagsContainer.append(empty);
  } else {
    [...assignedTags.slice(0, 5), ...(assignedTags.length > 5 ? ["…"] : [])]
      .forEach(tagName => {
        const tag = document.createElement("span");
        tag.textContent = tagName;
        tagsContainer.append(tag);
      });
  }
  const bookmark = document.querySelector("#selection-preview-bookmark");
  bookmark.setAttribute("aria-pressed", "false");
  bookmark.querySelector(".material-icon").textContent = "bookmark_border";
  elements.selectionPreview.hidden = false;
  document.body.classList.add("selection-preview-open");
}

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
        clickableIcons: true,
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
      state.map.addListener("click", event => {
        if (!event.placeId) return;
        event.stop();
        previewMapPlace(event.placeId);
      });
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
      state.marker.addListener("click", () => showSelectionPreview(data));
    }
    state.map.panTo(position);
    if (!preserveNearbyMarkers) state.map.setZoom(15);
  }

  elements.status.textContent = preserveNearbyMarkers
    ? `${(data.matchedPreferences || []).length} preference matches · ${place.distanceKm.toFixed(2)} km away`
    : `${analysis.reviewCount} reviews analysed · ${analysis.generalTags.length + analysis.culturalTags.length} tags assigned`;
  setView("details");

  if (!preserveNearbyMarkers) {
    showSelectionPreview(data);
  }
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

function selectRecommendation(item) {
  elements.recommendationDrawer.hidden = false;
  document.body.classList.add("recommendations-open");
  renderPlace(item, true);
  const card = elements.recommendationTrack.querySelector(
    `[data-place-id="${CSS.escape(item.place.id)}"]`,
  );
  card?.scrollIntoView({
    behavior: "smooth",
    inline: "center",
    block: "nearest",
  });
  elements.recommendationTrack
    .querySelectorAll(".recommendation-card")
    .forEach(element => element.classList.toggle("selected", element === card));
}

function renderRecommendationCarousel(response) {
  elements.recommendationTrack.replaceChildren();
  elements.recommendationTitle.textContent = response.mode === "destination"
    ? `Similar to ${response.reference?.destination?.name || "your destination"}`
    : "Based on your preferences";

  for (const item of response.matchedPlaces) {
    const card = document.createElement("article");
    card.className = "recommendation-card";
    card.dataset.placeId = item.place.id;
    card.tabIndex = 0;
    card.setAttribute("role", "button");
    card.setAttribute("aria-label", `Open rank ${item.rank}, ${item.place.displayName?.text || "place"}`);

    const imageShell = document.createElement("div");
    imageShell.className = "recommendation-image-shell";
    const photoUrl = placePhotoUrl(item.place.photo);
    const fallback = createPhotoFallback();

    if (photoUrl) {
      const image = document.createElement("img");
      image.src = photoUrl;
      image.alt = `${item.place.displayName?.text || "Place"} location`;
      image.loading = "lazy";
      fallback.hidden = true;
      image.addEventListener("error", () => {
        image.hidden = true;
        fallback.hidden = false;
      });
      imageShell.append(image);

      const attribution = item.place.photo?.authorAttributions?.[0];
      if (attribution?.displayName) {
        const credit = document.createElement("span");
        credit.className = "card-photo-credit";
        credit.textContent = `Photo: ${attribution.displayName}`;
        imageShell.append(credit);
      }
    }

    imageShell.append(fallback);
    const rank = document.createElement("span");
    rank.className = "rank-badge";
    rank.textContent = `#${item.rank}`;
    imageShell.append(rank);

    const body = document.createElement("div");
    body.className = "recommendation-card-body";
    const name = document.createElement("h3");
    name.textContent = item.place.displayName?.text || "Unknown place";
    const description = document.createElement("p");
    description.className = "recommendation-description";
    description.textContent = placeDescription(item.place);
    const route = document.createElement("div");
    route.className = "recommendation-route";
    const eta = document.createElement("span");
    eta.textContent = displayEta(item.place);
    const separator = document.createElement("i");
    const distance = document.createElement("span");
    distance.textContent = displayDistance(item.place);
    route.append(eta, separator, distance);

    const tags = allAssignedTags(item);
    const tagLine = document.createElement("div");
    tagLine.className = "recommendation-tags";
    tagLine.textContent = [
      ...tags.slice(0, 5),
      ...(tags.length > 5 ? ["…"] : []),
    ].join(" · ");

    const actions = document.createElement("div");
    actions.className = "recommendation-actions";
    const directions = document.createElement("button");
    directions.type = "button";
    directions.className = "recommendation-action";
    directions.title = "Directions";
    directions.setAttribute("aria-label", `Directions to ${name.textContent}`);
    directions.innerHTML = '<span class="material-icon">directions</span><span>Directions</span>';
    directions.addEventListener("click", event => {
      event.stopPropagation();
      if (item.place.googleMapsUri) {
        window.open(item.place.googleMapsUri, "_blank", "noopener,noreferrer");
      }
    });

    const bookmark = document.createElement("button");
    bookmark.type = "button";
    bookmark.className = "recommendation-action";
    bookmark.title = "Bookmark";
    bookmark.setAttribute("aria-label", `Bookmark ${name.textContent}`);
    bookmark.setAttribute("aria-pressed", "false");
    bookmark.innerHTML = '<span class="material-icon">bookmark_border</span><span>Bookmark</span>';
    bookmark.addEventListener("click", event => {
      event.stopPropagation();
      const active = bookmark.getAttribute("aria-pressed") !== "true";
      bookmark.setAttribute("aria-pressed", String(active));
      bookmark.querySelector(".material-icon").textContent = active
        ? "bookmark"
        : "bookmark_border";
    });
    actions.append(directions, bookmark);

    body.append(name, description, route, tagLine, actions);
    card.append(imageShell, body);
    card.addEventListener("click", () => openPlaceDetail(item));
    card.addEventListener("keydown", event => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        openPlaceDetail(item);
      }
    });
    elements.recommendationTrack.append(card);
  }

  const hasRecommendations = response.matchedPlaces.length > 0;
  elements.recommendationDrawer.hidden = !hasRecommendations;
  document.body.classList.toggle("recommendations-open", hasRecommendations);
}

function renderDetailPhotos(place, name) {
  const shell = document.querySelector(".detail-photo-shell");
  const track = document.querySelector("#detail-photo-track");
  const fallback = document.querySelector("#detail-photo-unavailable");
  const indicator = document.querySelector("#detail-photo-indicator");
  const count = document.querySelector("#detail-photo-count");
  const photos = (place.photos?.length ? place.photos : [place.photo])
    .filter(photo => photo?.name)
    .slice(0, 5);

  track.replaceChildren();
  shell.hidden = false;
  track.hidden = photos.length === 0;
  fallback.hidden = photos.length > 0;
  indicator.hidden = photos.length <= 1;
  count.textContent = photos.length ? `1 of ${photos.length}` : "";

  photos.forEach((photo, photoIndex) => {
    const slide = document.createElement("div");
    slide.className = "detail-photo-slide";
    const image = document.createElement("img");
    image.src = placePhotoUrl(photo);
    image.alt = `${name} location photo ${photoIndex + 1}`;
    image.loading = photoIndex === 0 ? "eager" : "lazy";
    image.addEventListener("error", () => {
      slide.remove();
      if (!track.children.length) {
        track.hidden = true;
        shell.hidden = false;
        fallback.hidden = false;
        indicator.hidden = true;
      }
    });
    slide.append(image);

    const attribution = photo.authorAttributions?.[0];
    if (attribution?.displayName) {
      const credit = attribution.uri
        ? document.createElement("a")
        : document.createElement("span");
      credit.className = "detail-photo-credit";
      credit.textContent = `Photo: ${attribution.displayName}`;
      if (attribution.uri) {
        credit.href = attribution.uri;
        credit.target = "_blank";
        credit.rel = "noreferrer";
      }
      slide.append(credit);
    }
    track.append(slide);
  });

  track.onscroll = () => {
    if (photos.length <= 1) return;
    const activeIndex = Math.round(track.scrollLeft / Math.max(track.clientWidth, 1));
    count.textContent = `${Math.min(activeIndex + 1, photos.length)} of ${photos.length}`;
  };
  track.scrollLeft = 0;
}

function openPlaceDetail(item) {
  state.selectedRecommendation = item;
  const place = item.place;
  const name = place.displayName?.text || "Place details";
  document.querySelector("#detail-page-name").textContent = name;
  document.querySelector("#detail-about-name").textContent = name;
  document.querySelector("#detail-description").textContent = placeDescription(place);
  document.querySelector("#detail-full-address").textContent = place.formattedAddress || "Full address unavailable.";
  document.querySelector("#detail-eta").textContent = displayEta(place);
  document.querySelector("#detail-distance").textContent = displayDistance(place);
  document.querySelector("#detail-similarity").textContent = item.ranking
    ? `${item.ranking.similarityPercentage.toFixed(1)}%`
    : "Not ranked";

  renderDetailPhotos(place, name);
  renderTags("detail-tags", allAssignedTags(item));
  const bookmarkButton = document.querySelector("#bookmark-button");
  bookmarkButton.setAttribute("aria-pressed", "false");
  bookmarkButton.querySelector(".material-icon").textContent = "bookmark_border";
  document.querySelector("#detail-action-status").textContent = "";
  elements.detailPage.hidden = false;
  document.body.style.overflow = "hidden";
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
    marker.addListener("click", () => selectRecommendation(item));
    state.nearbyMarkers.push(marker);
    bounds.extend(position);
  }

  state.map.fitBounds(bounds, 60);
  elements.status.textContent = `${response.matchedCount} matched · ${response.taggedCount} tagged · ${response.candidateCount} candidates`;
  renderRecommendationCarousel(response);

  const firstMatch = response.matchedPlaces[0];
  if (firstMatch) {
    selectRecommendation(firstMatch);
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
  elements.selectionPreview.hidden = true;
  document.body.classList.remove("selection-preview-open");
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
    const [response, currentPosition] = await Promise.all([
      fetch("/api/places/analyze", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ placeId }),
      }),
      getCurrentPosition().catch(() => null),
    ]);
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || "Place analysis failed.");
    if (currentPosition && data.place?.location) {
      data.place.distanceKm = straightLineDistanceKm(
        {
          latitude: currentPosition.coords.latitude,
          longitude: currentPosition.coords.longitude,
        },
        data.place.location,
      );
      data.place.etaMinutes = Math.max(2, Math.ceil(data.place.distanceKm * 2));
      data.place.etaEstimated = true;
    }
    renderPlace(data);
  } catch (error) {
    setView("empty");
    elements.status.textContent = error.message;
  }
}

async function previewMapPlace(placeId) {
  elements.results.hidden = true;
  elements.recommendationDrawer.hidden = true;
  document.body.classList.remove("recommendations-open");
  elements.status.textContent = "Fetching reviews and assigning tags…";

  try {
    const [response, currentPosition] = await Promise.all([
      fetch("/api/places/analyze", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ placeId }),
      }),
      getCurrentPosition().catch(() => null),
    ]);
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || "Place details failed.");

    if (currentPosition && data.place?.location) {
      data.place.distanceKm = straightLineDistanceKm(
        {
          latitude: currentPosition.coords.latitude,
          longitude: currentPosition.coords.longitude,
        },
        data.place.location,
      );
      data.place.etaMinutes = Math.max(2, Math.ceil(data.place.distanceKm * 2));
      data.place.etaEstimated = true;
    }

    const previewItem = data;
    state.selectedDestinationId = data.place.id;
    showSelectionPreview(previewItem);
    elements.status.textContent = `${data.place.displayName?.text || "Place"} selected.`;
  } catch (error) {
    elements.status.textContent = error.message;
  }
}

elements.form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const query = elements.input.value.trim();
  if (!query) return;

  elements.recommendationDrawer.hidden = true;
  elements.selectionPreview.hidden = true;
  document.body.classList.remove("selection-preview-open");
  document.body.classList.remove("recommendations-open");

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

document.querySelector("#close-recommendations").addEventListener("click", () => {
  elements.recommendationDrawer.hidden = true;
  document.body.classList.remove("recommendations-open");
});

elements.selectionPreview.addEventListener("click", () => {
  if (state.selectedPreview) openPlaceDetail(state.selectedPreview);
});

elements.selectionPreview.addEventListener("keydown", event => {
  if ((event.key === "Enter" || event.key === " ") && state.selectedPreview) {
    event.preventDefault();
    openPlaceDetail(state.selectedPreview);
  }
});

document.querySelector("#close-selection-preview").addEventListener("click", event => {
  event.stopPropagation();
  elements.selectionPreview.hidden = true;
  document.body.classList.remove("selection-preview-open");
});

document.querySelector("#selection-preview-directions").addEventListener("click", event => {
  event.stopPropagation();
  const uri = state.selectedPreview?.place?.googleMapsUri;
  if (uri) window.open(uri, "_blank", "noopener,noreferrer");
});

document.querySelector("#selection-preview-bookmark").addEventListener("click", event => {
  event.stopPropagation();
  const button = event.currentTarget;
  const bookmarked = button.getAttribute("aria-pressed") !== "true";
  button.setAttribute("aria-pressed", String(bookmarked));
  button.querySelector(".material-icon").textContent = bookmarked
    ? "bookmark"
    : "bookmark_border";
});

document.querySelector("#detail-back-button").addEventListener("click", () => {
  elements.detailPage.hidden = true;
  document.body.style.overflow = "";
});

document.querySelector("#bookmark-button").addEventListener("click", event => {
  const button = event.currentTarget;
  const bookmarked = button.getAttribute("aria-pressed") !== "true";
  button.setAttribute("aria-pressed", String(bookmarked));
  button.querySelector(".material-icon").textContent = bookmarked
    ? "bookmark"
    : "bookmark_border";
  document.querySelector("#detail-action-status").textContent = bookmarked
    ? "Bookmark selected. Account integration will be connected later."
    : "Bookmark removed.";
});

document.querySelector("#directions-button").addEventListener("click", () => {
  document.querySelector("#detail-action-status").textContent =
    "Directions will be connected in a later integration.";
});

document.querySelector("#traffic-button").addEventListener("click", () => {
  elements.status.textContent =
    "Traffic congestion detection will connect to the traffic module later.";
});

document.querySelector("#weather-button").addEventListener("click", () => {
  elements.status.textContent =
    "Weather conditions will connect to the weather module later.";
});

initializeMap();
