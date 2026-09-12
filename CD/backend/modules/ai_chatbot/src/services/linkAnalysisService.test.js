const test = require('node:test');
const assert = require('node:assert/strict');

const { isPrivateAddress, htmlText } = require('./linkAnalysisService');

test('blocks loopback and private network addresses', () => {
  assert.equal(isPrivateAddress('127.0.0.1'), true);
  assert.equal(isPrivateAddress('10.1.2.3'), true);
  assert.equal(isPrivateAddress('172.20.1.1'), true);
  assert.equal(isPrivateAddress('192.168.1.1'), true);
  assert.equal(isPrivateAddress('::1'), true);
  assert.equal(isPrivateAddress('8.8.8.8'), false);
});

test('extracts readable HTML without executable content', () => {
  const text = htmlText('<title>Trip</title><script>ignore()</script><p>Visit &amp; eat</p>');
  assert.equal(text, 'Trip Visit & eat');
});
