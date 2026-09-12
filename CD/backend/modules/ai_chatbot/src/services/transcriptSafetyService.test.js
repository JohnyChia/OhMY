const test = require('node:test');
const assert = require('node:assert/strict');
const { preserveTranscriptMeaning } = require('./transcriptSafetyService');

const cases = [
  ['I want to find a cheap restaurant near KLCC tonight.', 'I want to find a cheap restaurant near KLCC tonight.'],
  ['Boleh tolong cari restoran murah dekat KLCC?', 'Boleh tolong cari restoran murah dekat KLCC?'],
  ['我今晚想去 KLCC 吃东西。', '我今晚想去 KLCC 吃东西。'],
  ['Can you find somewhere nice to makan near KLCC?', 'Can you find somewhere nice to makan near KLCC?'],
  ['Boleh cari one nice restaurant dekat Penang?', 'Boleh cari one nice restaurant dekat Penang?'],
  ['i wan cheap food near klcc tonight', 'I want cheap food near KLCC tonight.'],
  ['Find a hotel under RM200 tonight.', 'Find a hotel under RM200 tonight.'],
  ['Find something for Saturday at 8 pm.', 'Find something for Saturday at 8 pm.'],
  ['Find food near KLCC.', 'Find food near KLCC.'],
  ['Where can I eat?', 'Where can I eat?'],
];

for (const [raw, corrected] of cases) {
  test(`preserves canonical meaning: ${raw}`, () => {
    assert.equal(preserveTranscriptMeaning(raw, corrected).text, corrected);
  });
}

test('rejects a materially changed destination', () => {
  const result = preserveTranscriptMeaning('Find food near Penang.', 'Find food near Kuala Lumpur.');
  assert.equal(result.text, 'Find food near Penang.');
  assert.equal(result.accepted, false);
});
