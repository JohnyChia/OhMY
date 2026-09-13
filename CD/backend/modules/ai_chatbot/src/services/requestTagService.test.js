const test = require('node:test');
const assert = require('node:assert/strict');
const { requestTags, matchesRequest } = require('./requestTagService');

test('does not turn an excluded activity into a requested activity', () => {
  assert.equal(requestTags('no museums').length, 0);
  assert.equal(requestTags('avoid hotels').length, 0);
});

test('fast food matches McDonalds by provider category, not literal name', () => {
  const tags = requestTags('fast food near me');
  assert.equal(tags[0].tag, 'fast_food');
  assert.equal(matchesRequest({ displayName: { text: 'McDonalds Danau Kota DT' },
    types: ['fast_food_restaurant', 'restaurant'] }, tags), true);
});

test('Chinese cuisine does not match a Chinese temple', () => {
  assert.equal(matchesRequest({ displayName: { text: 'Chinese Temple' },
    types: ['place_of_worship'] }, requestTags('Chinese cuisine')), false);
});

test('generic personalized recommendations do not create request tags', () => {
  assert.deepEqual(requestTags('recommend something for me'), []);
});
