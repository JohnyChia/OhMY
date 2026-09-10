import assert from 'node:assert/strict';
import test from 'node:test';
import { detectLocationTags, reviewPostText, type ReviewInput, type TagRow } from '../src/nlp.js';

const base: ReviewInput = {
  title: 'Morning at Kwai Chai Hong',
  description: 'Kwai Chai Hong in Kuala Lumpur has colourful heritage lanes before breakfast.',
  destination: 'Kuala Lumpur',
  attraction: 'Kwai Chai Hong',
  blockedTerms: [{ term: 'fucking' }, { term: '傻逼' }],
  allowList: ['scunthorpe'],
  aliases: [{ canonical_location: 'Kuala Lumpur', alias: 'KL' }],
};

test('approves meaningful location-related text', () => {
  assert.equal(reviewPostText(base).approved, true);
});

test('rejects deliberately separated profanity', () => {
  const result = reviewPostText({ ...base, description: 'Kuala Lumpur was f u c k i n g unpleasant today.' });
  assert.equal(result.code, 'INAPPROPRIATE_LANGUAGE');
});

test('rejects leetspeak profanity', () => {
  const result = reviewPostText({
    ...base,
    description: 'Kwai Chai Hong in Kuala Lumpur was f@cking disappointing.',
  });
  assert.equal(result.code, 'INAPPROPRIATE_LANGUAGE');
});

test('rejects short content', () => {
  assert.equal(
    reviewPostText({ ...base, title: 'KL' }).code,
    'INVALID_LENGTH',
  );
});

test('rejects every link format in title and description', () => {
  assert.equal(
    reviewPostText({
      ...base,
      description: 'See Kuala Lumpur at https://example.com for more information.',
    }).code,
    'LINK_NOT_ALLOWED',
  );
  assert.equal(
    reviewPostText({ ...base, title: 'Visit www.example.com today' }).code,
    'LINK_NOT_ALLOWED',
  );
  assert.equal(
    reviewPostText({
      ...base,
      description: 'Read example.com/guide before visiting Kuala Lumpur.',
    }).code,
    'LINK_NOT_ALLOWED',
  );
});

test('rejects multilingual profanity', () => {
  const result = reviewPostText({ ...base, description: 'Kwai Chai Hong 真是傻逼而且令人失望。' });
  assert.equal(result.code, 'INAPPROPRIATE_LANGUAGE');
});

test('does not reject allow-listed words', () => {
  const result = reviewPostText({ ...base, description: 'A visitor from Scunthorpe enjoyed Kuala Lumpur today.' });
  assert.equal(result.approved, true);
});

test('rejects unrelated and repetitive text', () => {
  assert.equal(
    reviewPostText({ ...base, title: 'Langkawi beach', description: 'A quiet beach with clear water and soft sand.' }).code,
    'LOCATION_MISMATCH',
  );
  assert.equal(
    reviewPostText({ ...base, description: 'place place place place place place place place' }).code,
    'LOW_QUALITY_TEXT',
  );
});

const tags: TagRow[] = [
  { id: 13, name: 'Heritage', tag_type: 'cultural' },
  { id: 5, name: 'Landmark', tag_type: 'general' },
  { id: 20, name: 'Local Cuisine', tag_type: 'cultural' },
  { id: 21, name: 'Cultural Experience', tag_type: 'cultural' },
];

test('tag detection uses location and place types, never post text', () => {
  const detected = detectLocationTags({
    destination: 'Kuala Lumpur',
    attraction: 'Kwai Chai Hong',
    placeTypes: ['historical_landmark'],
    tags,
    rules: [
      { tag_id: 13, location_pattern: 'Kwai Chai Hong', weight: 5 },
      { tag_id: 5, place_type: 'historical_landmark', weight: 4 },
    ],
    fallbackTagName: 'Cultural Experience',
  });
  assert.deepEqual(detected.map((tag) => tag.id), [13, 5]);
});

test('unknown locations use the database-configured fallback', () => {
  const detected = detectLocationTags({
    destination: 'Unknown', attraction: 'Unknown', placeTypes: [], tags, rules: [],
    fallbackTagName: 'Cultural Experience',
  });
  assert.deepEqual(detected.map((tag) => tag.id), [21]);
});

test('identical text cannot influence location-only tags', () => {
  const rules = [
    { tag_id: 13, location_pattern: 'Kwai Chai Hong', weight: 5 },
    { tag_id: 20, location_pattern: 'Jalan Alor', weight: 5 },
  ];
  const heritage = detectLocationTags({
    destination: 'Kuala Lumpur', attraction: 'Kwai Chai Hong', placeTypes: [], tags, rules,
    fallbackTagName: 'Cultural Experience',
  });
  const food = detectLocationTags({
    destination: 'Kuala Lumpur', attraction: 'Jalan Alor', placeTypes: [], tags, rules,
    fallbackTagName: 'Cultural Experience',
  });
  assert.deepEqual(heritage.map((tag) => tag.id), [13]);
  assert.deepEqual(food.map((tag) => tag.id), [20]);
});
