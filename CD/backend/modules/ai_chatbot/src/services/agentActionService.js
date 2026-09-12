/**
 * Converts completed agent work into a small, UI-safe handoff contract.
 * The mobile shell can use this to open a module or prefill a screen without
 * coupling the chatbot to that module's Dart implementation.
 */
function buildAgentActions({ intent, toolResult, tripState, profile }) {
  const actions = [];
  const state = tripState || {};
  const isUnavailable = !toolResult || toolResult.success === false || toolResult.unavailable;

  if (!isUnavailable && ["create_trip", "update_trip", "generate_itinerary", "recommendation", "show_location", "show_attachment_location"].includes(intent)) {
    actions.push({
      type: "open_preference_recommender",
      title: "View personalised recommendations",
      auto_applied: ["create_trip", "update_trip"].includes(intent),
      prefill: {
        destination: ['show_location', 'show_attachment_location'].includes(intent)
          ? toolResult?.destination || ''
          : state.destination || toolResult?.destination || "",
        interests: state.interest || [],
        budget: state.budget || "",
        duration: state.duration || null
      }
    });
  }

  if (!isUnavailable && intent === "discover_community") {
    actions.push({
      type: "open_community_discovery",
      title: "See traveller community posts",
      auto_applied: false,
      prefill: {
        query: toolResult?.query || state.destination || "",
        posts: toolResult?.posts || []
      }
    });
  }

  if (!isUnavailable && intent === "update_profile") {
    actions.push({
      type: "open_user_profile",
      title: "Travel preferences updated",
      auto_applied: true,
      prefill: {
        favorite_categories: profile?.favorite_categories || [],
        travel_style: profile?.travel_style || "",
        budget_preference: profile?.budget_preference || ""
      }
    });
  }

  return actions;
}

function buildPrimaryAction({ intent, toolResult, tripState, profile, routing }) {
  // Actions are an allowlisted contract, not a projection of model prose. Do
  // not hand off an unavailable provider result as a successful navigation.
  if (!toolResult || toolResult.success === false || toolResult.unavailable) {
    return null;
  }
  const expectedSemanticIntents = {
    create_trip: ['navigation', 'trip_planning'],
    update_trip: ['trip_update'],
    generate_itinerary: ['itinerary'],
    show_location: ['map'],
    show_attachment_location: ['attachment_location'],
    recommendation: ['recommendation'],
    reroute: ['reroute'],
    weather: ['weather'],
    discover_community: ['community'],
    update_profile: ['profile_update'],
  };
  const permittedIntents = expectedSemanticIntents[intent];
  if (!permittedIntents || !routing || !permittedIntents.includes(routing.intent)) {
    return null;
  }
  const state = tripState || {};
  const journeyParameters = {
    destination: ['show_location', 'show_attachment_location'].includes(intent)
      ? toolResult?.destination || ''
      : state.destination || toolResult?.destination || "",
    interests: state.interest || [],
    budget: state.budget || "",
    duration: state.duration || null,
  };
  // Nova-owned journeys are deliberately solo-only. The independent Travel
  // Group module is never a destination of this action contract.
  if (toolResult?.trip_mode === 'solo') {
    journeyParameters.trip_mode = toolResult.trip_mode;
  }

  switch (intent) {
    case "create_trip":
    case "update_trip":
    case "generate_itinerary":
      return validatePrimaryAction({ type: "start_journey", target: "trip", parameters: journeyParameters, requires_confirmation: false });
    case "show_location":
      if (routing.allowMap !== true) return null;
      return validatePrimaryAction({ type: "show_place_results", target: "map", parameters: journeyParameters, requires_confirmation: false });
    case "show_attachment_location":
      return validatePrimaryAction({ type: "show_place_results", target: "map", parameters: journeyParameters, requires_confirmation: false });
    case "recommendation":
      return null;
    case "reroute":
      return validatePrimaryAction({ type: "show_place_results", target: "map", parameters: journeyParameters, requires_confirmation: true });
    case "weather":
      // Weather is already rendered inside Nova. There is no independent
      // weather owner screen, so emitting a handoff would be a false action.
      return null;
    case "discover_community":
      return validatePrimaryAction({ type: "community_results", target: "community", parameters: { query: toolResult?.query || "" }, requires_confirmation: false });
    case "update_profile":
      return validatePrimaryAction({
        type: "preferences_updated",
        target: "profile",
        parameters: {
          favorite_categories: profile?.favorite_categories || [],
          travel_style: profile?.travel_style || "",
          budget_preference: profile?.budget_preference || ""
        },
        requires_confirmation: false
      });
    default:
      return null;
  }
}

function validatePrimaryAction(action) {
  if (action == null) return null;
  const allowed = {
    start_journey: "trip",
    show_place_results: "map",
    weather_display: "weather",
    community_results: "community",
    preferences_updated: "profile"
  };
  if (allowed[action.type] !== action.target) return null;
  if (typeof action.requires_confirmation !== "boolean") return null;
  if (!action.parameters || typeof action.parameters !== "object" || Array.isArray(action.parameters)) {
    return null;
  }
  const parameters = action.parameters;
  const hasOnly = (keys) => Object.keys(parameters).every((key) => keys.includes(key));
  const validString = (value, { required = false, max = 160 } = {}) =>
    typeof value === "string" && value.length <= max && (!required || value.trim().length > 0);
  const validStringList = (value, maxItems = 24, itemMax = 80) =>
    Array.isArray(value) && value.length <= maxItems && value.every((item) => validString(item, { max: itemMax }));

  switch (action.type) {
    case "start_journey":
    case "show_place_results":
      if (!hasOnly(["destination", "interests", "budget", "duration", "trip_mode"]) ||
          !validString(parameters.destination, { required: true }) ||
          !validStringList(parameters.interests) ||
          !validString(parameters.budget, { max: 80 }) ||
          !(parameters.duration === null ||
            (typeof parameters.duration === "number" &&
              Number.isFinite(parameters.duration) &&
              parameters.duration > 0 && parameters.duration <= 365)) ||
          !(parameters.trip_mode === undefined ||
            parameters.trip_mode === 'solo')) {
        return null;
      }
      break;
    case "weather_display":
      if (!hasOnly(["location", "date", "weather", "observed_at"]) ||
          !validString(parameters.location, { required: true }) ||
          !validString(parameters.date, { required: true }) ||
          !validString(parameters.weather, { required: true }) ||
          !validString(parameters.observed_at, { required: true })) {
        return null;
      }
      break;
    case "community_results":
      if (!hasOnly(["query"]) || !validString(parameters.query, { required: true })) return null;
      break;
    case "preferences_updated":
      if (!hasOnly(["favorite_categories", "travel_style", "budget_preference"]) ||
          !validStringList(parameters.favorite_categories) ||
          !validString(parameters.travel_style, { max: 120 }) ||
          !validString(parameters.budget_preference, { max: 120 })) {
        return null;
      }
      break;
    default:
      return null;
  }
  return { ...action, parameters: { ...parameters } };
}

module.exports = { buildAgentActions, buildPrimaryAction, validatePrimaryAction };
