const test = require('node:test');
const assert = require('node:assert/strict');
const { recommendationReply } = require('./recommendationPresentation');
test('recommendation speech never lists or invents places', () => {
  const result = { success: true, recommendations: [{ name: 'Verified Place' }] };
  for (const language of ['en', 'ms', 'zh-CN']) {
    const reply = recommendationReply(result, language);
    assert.ok(reply);
    assert.doesNotMatch(reply, /Verified Place|\{\}|undefined/);
  }
});
test('empty results and failures still need an explanatory response', () => {
  assert.equal(recommendationReply({ recommendations: [] }), null);
  assert.equal(recommendationReply({ success: false, recommendations: [{}] }), null);
});
