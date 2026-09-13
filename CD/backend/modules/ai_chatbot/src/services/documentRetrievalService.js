const tokenConfig = require('../config/tokenConfig');

function tokens(value) {
  return new Set(
    String(value || '').normalize('NFKC').toLocaleLowerCase()
      .match(/[\p{L}\p{N}]{2,}/gu) || [],
  );
}

function chunkDocument(text, options = {}) {
  const source = String(text || '').replace(/\r\n/g, '\n').trim();
  const size = Math.max(300, Number(options.size) || tokenConfig.fileChunkSize);
  const overlap = Math.min(size - 1, Math.max(0, Number(options.overlap) || tokenConfig.fileChunkOverlap));
  const chunks = [];
  for (let start = 0, index = 0; start < source.length; index++) {
    let end = Math.min(source.length, start + size);
    if (end < source.length) {
      const boundary = Math.max(source.lastIndexOf('\n', end), source.lastIndexOf(' ', end));
      if (boundary > start + Math.floor(size * 0.6)) end = boundary;
    }
    chunks.push({ index, start, end, text: source.slice(start, end).trim() });
    if (end >= source.length) break;
    start = Math.max(start + 1, end - overlap);
  }
  return chunks.filter((chunk) => chunk.text);
}

function retrieveDocumentContext(text, query, options = {}) {
  const chunks = chunkDocument(text, options);
  const queryTokens = tokens(query);
  const topK = Math.max(1, Number(options.topK) || tokenConfig.fileTopK);
  const maximum = Math.max(500, Number(options.maxChars) || tokenConfig.fileMaxContextChars);
  const ranked = chunks.map((chunk) => {
    const chunkTokens = tokens(chunk.text);
    let overlap = 0;
    for (const token of queryTokens) if (chunkTokens.has(token)) overlap += 1;
    return { ...chunk, score: overlap / Math.max(1, queryTokens.size) };
  }).sort((a, b) => b.score - a.score || a.index - b.index);
  // With no useful query terms, sample document coverage rather than sending
  // the entire file. This keeps whole-document summaries bounded.
  const selected = ranked[0]?.score > 0
    ? ranked.slice(0, topK)
    : chunks.filter((_, index) => index === 0 || index === chunks.length - 1 || index % Math.max(1, Math.floor(chunks.length / topK)) === 0).slice(0, topK);
  let used = 0;
  const bounded = [];
  for (const chunk of selected.sort((a, b) => a.index - b.index)) {
    const available = maximum - used;
    if (available <= 0) break;
    const value = chunk.text.slice(0, available);
    bounded.push({ index: chunk.index, start: chunk.start, end: chunk.start + value.length, score: chunk.score, text: value });
    used += value.length;
  }
  return {
    text: bounded.map((chunk) => `[Chunk ${chunk.index + 1}]\n${chunk.text}`).join('\n\n'),
    chunks: bounded.map(({ text: _text, ...metadata }) => metadata),
    totalChunks: chunks.length,
    originalCharacters: String(text || '').length,
    contextCharacters: used,
  };
}

module.exports = { chunkDocument, retrieveDocumentContext, tokens };
