const test = require('node:test');
const assert = require('node:assert/strict');

const requireNovaUser = require('./requireNovaUser');

test('rejects a Nova request without an access token before work begins', async () => {
  let statusCode;
  let payload;
  let calledNext = false;
  const response = {
    status(code) {
      statusCode = code;
      return this;
    },
    json(value) {
      payload = value;
      return this;
    },
  };

  await requireNovaUser(
    { get: () => undefined, body: {} },
    response,
    () => { calledNext = true; },
  );

  assert.equal(statusCode, 401);
  assert.equal(payload.success, false);
  assert.equal(calledNext, false);
});
