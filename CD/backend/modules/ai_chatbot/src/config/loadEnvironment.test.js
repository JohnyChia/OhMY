const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { environmentPaths, loadEnvironment } = require('./loadEnvironment');

test('Nova startup loads the shared backend environment when module .env is absent', () => {
  const moduleRoot = path.resolve(__dirname, '..', '..');
  assert.deepEqual(environmentPaths(moduleRoot), [
    path.join(moduleRoot, '.env'),
    path.resolve(moduleRoot, '..', '..', '.env'),
  ]);
});

test('shared backend PORT does not override the chatbot port', () => {
  const originalPort = process.env.PORT;
  delete process.env.PORT;
  try {
    loadEnvironment(path.resolve(__dirname, '..', '..'));
    assert.equal(process.env.PORT, undefined);
    assert.ok(process.env.SUPABASE_URL);
    assert.ok(process.env.SUPABASE_SERVICE_ROLE_KEY);
  } finally {
    if (originalPort === undefined) delete process.env.PORT;
    else process.env.PORT = originalPort;
  }
});
