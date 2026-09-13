const test = require('node:test');
const assert = require('node:assert/strict');

const { canonicalItem, firstHttpsUrl, relevant } = require('./savedTravelItemService');

test('recovers an HTTPS travel link from the semantically approved save turn', () => {
  assert.equal(
    firstHttpsUrl('Please keep this for my trip https://example.com/place?x=1.'),
    'https://example.com/place?x=1',
  );
});

test('uses the current message link when save tool parameters omit source_url', () => {
  const item = canonicalItem(
    { title: 'Weekend place' },
    { current_message: 'store this https://example.com/weekend' },
  );
  assert.equal(item.source_type, 'link');
  assert.equal(item.source_url, 'https://example.com/weekend');
});

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

test('recalls a saved location and its travel tags from a later trip question', () => {
  const items = [
    {
      id: 'saved-kl',
      title: 'Temple of Fine Arts KL',
      summary: 'Performing arts venue in Kuala Lumpur.',
      location_hint: 'Temple of Fine Arts KL',
      travel_tags: ['Cultural Experience'],
    },
    {
      id: 'saved-penang',
      title: 'Penang Hill',
      summary: 'Hill destination in Penang.',
      location_hint: 'Penang Hill',
      travel_tags: ['Nature'],
    },
  ];

  assert.deepEqual(
    relevant(items, 'KL 那个 saved place 附近有 similar cultural places 吗？'),
    [items[0]],
  );
});
