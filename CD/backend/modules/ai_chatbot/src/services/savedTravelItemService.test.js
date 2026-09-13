const test = require('node:test');
const assert = require('node:assert/strict');

const { canonicalItem } = require('./savedTravelItemService');

test('builds a private saved item from the current verified attachment', () => {
  const item = canonicalItem(
    { title: 'Remember this landmark' },
    {
      attachment: {
        name: 'landmark.jpg',
        analysisStatus: 'ready',
        analysis: {
          type: 'image',
          locationHint: 'Sultan Abdul Samad Building',
          travelTags: ['Historical Landmark'],
          visualContext: 'A verified historic landmark facade.',
        },
      },
    },
  );

  assert.equal(item.source_type, 'image');
  assert.equal(item.location_hint, 'Sultan Abdul Samad Building');
  assert.deepEqual(item.travel_tags, ['Historical Landmark']);
  assert.equal(item.metadata.verified_analysis, true);
  assert.equal(item.metadata.original_binary_saved, false);
  assert.match(item.content_hash, /^[a-f0-9]{64}$/);
});

test('accepts HTTPS links and rejects unsafe URL schemes', () => {
  assert.equal(
    canonicalItem({ source_url: 'https://example.com/travel' }).source_url,
    'https://example.com/travel',
  );
  assert.equal(
    canonicalItem({ source_url: 'file:///etc/passwd' }).source_url,
    null,
  );
});

test('stores an explicitly requested message without requiring a place or attachment', () => {
  const item = canonicalItem({
    source_type: 'message',
    title: 'Saved message',
    summary: 'I prefer quiet museums and a modest budget.',
  });

  assert.equal(item.source_type, 'message');
  assert.equal(item.title, 'Saved message');
  assert.match(item.summary, /quiet museums/);
});
