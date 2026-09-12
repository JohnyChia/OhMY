/**
 * Conservative guard for optional LLM transcript polishing. It deliberately
 * favours the original ASR result when a proposed correction could replace a
 * meaningful word, number, CJK text, or an identifier such as a place code.
 */
function normalize(text) {
  return String(text || '').trim().replace(/\s+/gu, ' ');
}

function words(text) {
  return normalize(text).match(/[\p{L}\p{N}]+/gu) || [];
}

function editDistance(left, right) {
  const a = left.toLocaleLowerCase();
  const b = right.toLocaleLowerCase();
  const row = Array.from({ length: b.length + 1 }, (_, index) => index);
  for (let i = 1; i <= a.length; i += 1) {
    let previous = row[0];
    row[0] = i;
    for (let j = 1; j <= b.length; j += 1) {
      const saved = row[j];
      row[j] = Math.min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] === b[j - 1] ? 0 : 1));
      previous = saved;
    }
  }
  return row[b.length];
}

function hasCandidateFor(sourceWord, candidateWords) {
  const maximumDistance = sourceWord.length <= 4 ? 1 : 2;
  return candidateWords.some((word) =>
    editDistance(sourceWord, word) <= maximumDistance,
  );
}

function protectedTokens(text) {
  const cjk = text.match(/\p{Script=Han}+/gu) || [];
  const values = text.match(/(?:RM|MYR|USD|\$|€|£)?\s*\d+(?:[.,:]\d+)*(?:\s?(?:am|pm))?/giu) || [];
  const identifiers = text.match(/\b[A-Z][A-Z0-9-]{1,}\b/g) || [];
  return [...cjk, ...values, ...identifiers].map((token) => normalize(token));
}

function containsToken(text, token) {
  return text.toLocaleLowerCase().includes(token.toLocaleLowerCase());
}

/** Returns the canonical transcript plus diagnostic-only validation metadata. */
function preserveTranscriptMeaning(rawText, proposedText) {
  const raw = normalize(rawText);
  const proposed = normalize(proposedText);
  if (!raw || !proposed || raw === proposed) {
    return { text: raw || proposed, accepted: true, reason: 'unchanged' };
  }

  if (protectedTokens(raw).some((token) => !containsToken(proposed, token))) {
    return { text: raw, accepted: false, reason: 'protected_token_changed' };
  }

  const candidateWords = words(proposed);
  const droppedMeaningfulWord = words(raw).some((word) => {
    if (word.length < 3 || /^\d+$/u.test(word)) return false;
    return !candidateWords.some((candidate) => candidate.toLocaleLowerCase() === word.toLocaleLowerCase()) &&
      !hasCandidateFor(word, candidateWords);
  });
  if (droppedMeaningfulWord) {
    return { text: raw, accepted: false, reason: 'meaningful_word_changed' };
  }

  return { text: proposed, accepted: true, reason: 'conservative_correction' };
}

module.exports = { preserveTranscriptMeaning };
