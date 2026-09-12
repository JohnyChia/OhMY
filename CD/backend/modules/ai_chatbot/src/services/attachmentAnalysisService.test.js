const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs/promises');
const os = require('os');
const path = require('path');
const { analyzeAttachment, MAX_FILE_BYTES, protectedFacts, buildNormalizedContext, validateDocumentSemantics } = require('./attachmentAnalysisService');

async function temporaryFile(name, content) {
  const filePath = path.join(os.tmpdir(), `${Date.now()}-${name}`);
  await fs.writeFile(filePath, content);
  return filePath;
}

test('extracts TXT content and preserves factual values', async () => {
  const filePath = await temporaryFile('nova-menu.txt', 'Penang Hill\nRM 30\n12 Sept 2026');
  try {
    const analysis = await analyzeAttachment(
      { path: filePath, size: 32, originalname: 'menu.txt', mimetype: 'text/plain' },
      { documentAnalyzer: async () => ({ travelRelated: true, travelTags: ['Landmark'], locationHint: 'Provider place' }) },
    );
    assert.equal(analysis.type, 'text');
    assert.deepEqual(analysis.travelTags, ['Landmark']);
    assert.match(analysis.extractedText, /Penang Hill/);
    assert.ok(analysis.protectedFacts.includes('RM 30'));
  } finally { await fs.unlink(filePath); }
});

test('rejects a text attachment with no travel taxonomy signal', async () => {
  const filePath = await temporaryFile('nova-notes.txt', 'Buy printer paper and call the bank.');
  try {
    await assert.rejects(
      () => analyzeAttachment(
               { path: filePath, size: 35, originalname: 'notes.txt', mimetype: 'text/plain' },
               { documentAnalyzer: async () => ({ travelRelated: false, travelTags: [], locationHint: '' }) },
      ),
      /travel-related attachments only/i,
    );
  } finally { await fs.unlink(filePath); }
});

test('validates semantic attachment output against canonical travel tags', () => {
  assert.deepEqual(validateDocumentSemantics({
    travelRelated: true,
    confidence: 0.94,
    travelTags: ['Restaurant', 'not-an-allowed-tag', 'Local Cuisine'],
    locationHint: 'Provider place',
    locationConfidence: 'high',
  }), {
    travelRelated: true,
    confidence: 0.94,
    travelTags: ['Restaurant', 'Local Cuisine'],
    locationHint: 'Provider place',
  });
});

test('rejects unsupported file types', async () => {
  const filePath = await temporaryFile('nova.bin', Buffer.from([1, 2, 3]));
  try {
    await assert.rejects(() => analyzeAttachment({ path: filePath, size: 3, originalname: 'unsafe.exe', mimetype: 'application/octet-stream' }));
  } finally { await fs.unlink(filePath); }
});

test('rejects image bytes with a misleading filename or MIME type', async () => {
  const filePath = await temporaryFile('nova-image.bin', Buffer.from([0xff, 0xd8, 0xff, 0x00]));
  try {
    await assert.rejects(
      () => analyzeAttachment({ path: filePath, size: 4, originalname: 'menu.png', mimetype: 'image/png' }),
      /filename does not match/i,
    );
    await assert.rejects(
      () => analyzeAttachment({ path: filePath, size: 4, originalname: 'menu.exe', mimetype: 'application/octet-stream' }),
      /Unsupported image filename/i,
    );
  } finally { await fs.unlink(filePath); }
});

test('rejects oversized upload metadata before extraction', async () => {
  await assert.rejects(() => analyzeAttachment({ path: 'unused', size: MAX_FILE_BYTES + 1, originalname: 'large.txt', mimetype: 'text/plain' }));
});

test('keeps Malaysian prices and place names verbatim in normalized context', () => {
  const factualText = 'Penang Hill\nNasi lemak RM 18\nLaksa RM 25\nSet menu RM 32';
  const facts = protectedFacts(factualText);
  const context = buildNormalizedContext({
    extractedText: factualText,
    visualContext: null,
    protectedFactList: facts,
    uncertainInferences: [],
    image: { width: 1200, height: 800 },
  });
  assert.match(context.factualText, /Penang Hill/);
  assert.deepEqual(context.protectedFacts, ['RM 18', 'RM 25', 'RM 32']);
  assert.match(context.instruction, /Never replace a location/);
});
