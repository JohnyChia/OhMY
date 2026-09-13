const test = require('node:test');
const assert = require('node:assert/strict');

const {
  validateClassification,
  parseClassificationResponse,
  INTENT_TO_TOOL,
} = require('./semanticClassifierService');

function classification(overrides = {}) {
  return {
    intent: 'weather',
    language: { primary: 'en', mixed: false, style: 'english' },
    location: { name: 'Provider supplied region', country: 'Malaysia' },
    domain: 'malaysia_travel',
    confidence: 0.98,
    parameters: { travel_date: 'today' },
    draft_response: '',
    ...overrides,
  };
}

test('maps structured semantic intent to an allowlisted tool and preserves location', () => {
  const result = validateClassification(classification());
  assert.equal(result.intent, 'weather');
  assert.equal(result.toolName, 'weather');
  assert.equal(result.parameters.destination, 'Provider supplied region');
  assert.equal(result.allowMap, false);
});

test('derives map permission only from navigation or map intent', () => {
  for (const intent of ['weather', 'recommendation', 'general_travel']) {
    assert.equal(validateClassification(classification({ intent })).allowMap, false);
  }
  assert.equal(validateClassification(classification({ intent: 'navigation' })).allowMap, true);
  assert.equal(validateClassification(classification({ intent: 'map' })).allowMap, true);
});

test('preserves dynamic mixed-language metadata from the current utterance classification', () => {
  const result = validateClassification(classification({
    language: { primary: 'ms', mixed: true, style: 'rojak' },
  }));
  assert.deepEqual(result.language, { primary: 'ms', mixed: true, style: 'rojak' });
});

test('normalizes model recommendation fields into the tool contract', () => {
  const result = validateClassification({
    intent: 'recommendation',
    language: { primary: 'ms', mixed: true, style: 'rojak' },
    location: { name: 'Melaka', country: 'Malaysia' },
    domain: 'malaysia_travel',
    confidence: 0.9,
    parameters: { preference: 'makanan' },
    draft_response: '',
  });

  assert.deepEqual(result.parameters, {
    destination: 'Melaka',
    requirements: ['makanan'],
    excluded_requirements: [],
  });
});

test('rejects malformed, unsupported, or unsafe classifier output', () => {
  assert.equal(validateClassification(null), null);
  assert.equal(validateClassification(classification({ intent: 'arbitrary_action' })), null);
  assert.equal(validateClassification(classification({ confidence: 4 })), null);
  assert.equal(validateClassification(classification({ language: { primary: 'unknown' } })), null);
});

test('does not execute side effects from low-confidence or non-travel classifications', () => {
  const lowConfidence = validateClassification(classification({
    intent: 'navigation',
    confidence: 0.2,
  }));
  assert.equal(lowConfidence.toolName, null);
  assert.equal(lowConfidence.allowMap, false);
  assert.equal(lowConfidence.requiresClarification, true);

  const nonTravel = validateClassification(classification({
    intent: 'navigation',
    domain: 'non_travel',
  }));
  assert.equal(nonTravel.toolName, null);
  assert.equal(nonTravel.allowMap, false);
});

test('parses only the forced semantic-classifier tool result', () => {
  const response = {
    choices: [{ message: { tool_calls: [{
      function: {
        name: 'classify_nova_request',
        arguments: JSON.stringify(classification()),
      },
    }, {
      function: {
        name: 'classify_nova_request',
        arguments: JSON.stringify(classification()),
      },
    }] } }],
  };
  assert.equal(parseClassificationResponse(response).toolName, INTENT_TO_TOOL.weather);
});
