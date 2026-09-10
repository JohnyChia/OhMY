import assert from 'node:assert/strict';
import test from 'node:test';
import { readServerConfig } from '../src/config.js';

const valid = {
  PORT: '3000',
  SUPABASE_URL: 'https://example.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY: 'private-test-key',
};

test('reads only community server settings', () => {
  const config = readServerConfig({
    ...valid,
    GOOGLE_PLACES_API_KEY: 'places-test-key',
    GROQ_API_KEY_1: 'unused',
    GOOGLE_WEATHER_API_KEY: 'unused',
    ALLOWED_ORIGINS: 'https://one.example, https://two.example',
  });
  assert.equal(config.port, 3000);
  assert.equal(config.googlePlacesApiKey, 'places-test-key');
  assert.deepEqual(config.allowedOrigins, [
    'https://one.example',
    'https://two.example',
  ]);
  assert.equal('groqApiKey' in config, false);
});

test('rejects a publishable key in the service-role slot', () => {
  assert.throws(
    () => readServerConfig({
      ...valid,
      SUPABASE_SERVICE_ROLE_KEY: 'sb_publishable_wrong_boundary',
    }),
    /private server key/,
  );
});

test('rejects missing required values and invalid ports', () => {
  assert.throws(() => readServerConfig({}), /SUPABASE_URL/);
  assert.throws(() => readServerConfig({ ...valid, PORT: '70000' }), /PORT/);
});
