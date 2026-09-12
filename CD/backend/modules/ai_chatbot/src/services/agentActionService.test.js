const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildPrimaryAction,
  validatePrimaryAction,
} = require("./agentActionService");

test("builds a typed journey handoff only with owner-safe parameters", () => {
  const action = buildPrimaryAction({
    intent: "create_trip",
    toolResult: { success: true },
    tripState: {
      destination: "Penang",
      interest: ["Local Cuisine"],
      budget: "RM300",
      duration: 2,
    },
    profile: {},
    routing: { intent: 'trip_planning', allowMap: false },
  });

  assert.deepEqual(action, {
    type: "start_journey",
    target: "trip",
    parameters: {
      destination: "Penang",
      interests: ["Local Cuisine"],
      budget: "RM300",
      duration: 2,
    },
    requires_confirmation: false,
  });
});

test("rejects an action with unexpected or incomplete owner parameters", () => {
  assert.equal(
    validatePrimaryAction({
      type: "start_journey",
      target: "trip",
      parameters: {
        destination: "Penang",
        interests: [],
        budget: "",
        duration: 2,
        unexpected: true,
      },
      requires_confirmation: false,
    }),
    null,
  );

  assert.equal(
    validatePrimaryAction({
      type: "weather_display",
      target: "weather",
      parameters: { location: "Penang", date: "today", weather: "" },
      requires_confirmation: false,
    }),
    null,
  );
});

test("rejects a Travel Group handoff from the solo-only Nova contract", () => {
  assert.equal(
    validatePrimaryAction({
      type: "start_journey",
      target: "trip",
      parameters: {
        destination: "Sabah",
        interests: [],
        budget: "",
        duration: null,
        trip_mode: "group",
      },
      requires_confirmation: false,
    }),
    null,
  );
});

test('never turns a weather-classified request into navigation', () => {
  const action = buildPrimaryAction({
    intent: 'create_trip',
    toolResult: { success: true, destination: 'Provider location' },
    tripState: { destination: 'Provider location', interest: [] },
    profile: {},
    routing: { intent: 'weather', allowMap: false },
  });
  assert.equal(action, null);
});

test('recommendations do not automatically open the map', () => {
  const action = buildPrimaryAction({
    intent: 'recommendation',
    toolResult: { success: true, destination: 'Provider location' },
    tripState: { destination: '', interest: [] },
    profile: {},
    routing: { intent: 'recommendation', allowMap: false },
  });
  assert.equal(action, null);
});

test('map display requires an explicit map routing decision', () => {
  const base = {
    intent: 'show_location',
    toolResult: { success: true, destination: 'Provider location' },
    tripState: { interest: [] },
    profile: {},
  };
  assert.equal(buildPrimaryAction({ ...base, routing: { intent: 'weather', allowMap: false } }), null);
  assert.equal(
    buildPrimaryAction({ ...base, routing: { intent: 'map', allowMap: true } })?.type,
    'show_place_results',
  );
});
