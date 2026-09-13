const test = require('node:test');
const assert = require('node:assert/strict');
const { explicitNavigationRequest } = require('./explicitNavigationService');

for (const [input, destination] of [
  ['go to Setapak Central', 'Setapak Central'],
  ['go Penang now', 'Penang'],
  ['Take me to Johor', 'Johor'],
  ['Can we go to Setapak Central?', 'Setapak Central'],
  ["Let's go to Penang", 'Penang'],
  ['I want to go to Shah Alam', 'Shah Alam'],
  ['Start a trip to Subang Jaya', 'Subang Jaya'],
  ['Bawa saya ke Setia Alam', 'Setia Alam'],
  ['Boleh bawa saya ke Johor?', 'Johor'],
  ['Jom pergi ke Penang', 'Penang'],
  ['Saya nak pergi ke Penang sekarang', 'Penang'],
  ['我要去槟城', '槟城'],
]) {
  test(`recognises explicit navigation: ${input}`, () => {
    assert.equal(explicitNavigationRequest(input)?.destination, destination);
  });
}

for (const input of [
  'Where should I go in Penang?',
  'Recommend places to go in Johor',
  'What is the weather in Setapak?',
  'go to',
  "don't go to Penang",
  'go to Penang or Johor',
  'go to Penang not now',
  'How do I start a trip to Penang?',
]) {
  test(`does not turn a non-navigation request into a trip: ${input}`, () => {
    assert.equal(explicitNavigationRequest(input), null);
  });
}
