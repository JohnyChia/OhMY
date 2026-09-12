export interface ModerationTerm {
  term: string;
  language?: string | null;
}

export interface LocationAlias {
  canonical_location: string;
  alias: string;
}

export interface TagRow {
  id: number;
  name: string;
  tag_type: string;
}

export interface TagRule {
  tag_id: number;
  location_pattern?: string | null;
  place_type?: string | null;
  weight: number;
}

export interface DetectedTag {
  id: number;
  name: string;
  type: string;
}

export interface ReviewResult {
  approved: boolean;
  reason: string;
  code: string;
  fieldErrors: Record<string, string>;
}

export interface ReviewInput {
  title: string;
  description: string;
  destination: string;
  attraction: string;
  blockedTerms: ModerationTerm[];
  allowList: string[];
  aliases: LocationAlias[];
}

const leetMap: Record<string, string> = {
  '0': 'o',
  '1': 'i',
  '3': 'e',
  '4': 'a',
  '5': 's',
  '7': 't',
  '@': 'a',
  '$': 's',
  '!': 'i',
};

const stopWords = new Set([
  'a', 'an', 'and', 'at', 'by', 'for', 'from', 'in', 'of', 'on', 'the',
  'to', 'with', 'dan', 'di', 'ke', 'yang', '的', '在', '和',
]);

export function normalizeText(value: string): string {
  return value
    .normalize('NFKD')
    .replace(/\p{M}/gu, '')
    .toLocaleLowerCase()
    .replace(/[013457@$!]/g, (character) => leetMap[character] ?? character)
    .replace(/(.)\1{2,}/gu, '$1$1')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function tokens(value: string): string[] {
  return normalizeText(value)
    .split(' ')
    .filter((token) => token.length > 0);
}

export function levenshtein(left: string, right: string): number {
  const previous = Array.from({ length: right.length + 1 }, (_, index) => index);
  for (let row = 1; row <= left.length; row += 1) {
    const current = [row];
    for (let column = 1; column <= right.length; column += 1) {
      current[column] = Math.min(
        (current[column - 1] ?? 0) + 1,
        (previous[column] ?? 0) + 1,
        (previous[column - 1] ?? 0) + (left[row - 1] === right[column - 1] ? 0 : 1),
      );
    }
    previous.splice(0, previous.length, ...current);
  }
  return previous[right.length] ?? left.length;
}

function containsBlockedLanguage(
  value: string,
  blockedTerms: ModerationTerm[],
  allowList: string[],
): boolean {
  let normalized = normalizeText(value);
  const allowed = new Set(allowList.map(normalizeText));
  for (const allowedTerm of allowed) {
    if (allowedTerm) normalized = normalized.replaceAll(allowedTerm, ' ');
  }
  const valueTokens = tokens(normalized);
  const compact = normalized.replace(/\s/g, '');

  for (const blocked of blockedTerms) {
    const term = normalizeText(blocked.term);
    if (!term || allowed.has(term)) continue;
    const termCompact = term.replace(/\s/g, '');
    if (term.includes(' ')) {
      if (` ${normalized} `.includes(` ${term} `)) return true;
    } else if (valueTokens.includes(term)) {
      return true;
    }
    const containsNonLatin = /[^a-z0-9]/u.test(termCompact);
    if ((termCompact.length >= 4 || (containsNonLatin && termCompact.length >= 2)) && compact.includes(termCompact)) {
      return true;
    }
    if (
      term.length >= 5 &&
      valueTokens.some(
        (token) => Math.abs(token.length - term.length) <= 1 && levenshtein(token, term) <= 1,
      )
    ) {
      return true;
    }
  }
  return false;
}

function textQualityError(value: string): string | null {
  const normalized = normalizeText(value);
  const valueTokens = tokens(value);
  const letters = normalized.replace(/[^\p{L}]/gu, '');
  if (letters.length < 3) return 'Write meaningful words instead of symbols or numbers.';
  if (/(.)\1{7,}/iu.test(value)) return 'Remove excessively repeated characters.';
  if (letters.length >= 24 && new Set([...letters]).size / letters.length < 0.12) {
    return 'The text appears repetitive or unreadable.';
  }
  if (valueTokens.length >= 7) {
    const counts = new Map<string, number>();
    for (const token of valueTokens) counts.set(token, (counts.get(token) ?? 0) + 1);
    if (Math.max(...counts.values()) / valueTokens.length > 0.6) {
      return 'The text repeats the same words too often.';
    }
  }
  return null;
}

function containsLink(value: string): boolean {
  if (/(?:https?:\/\/|ftp:\/\/|mailto:|www\.)/iu.test(value)) return true;

  // Also block link-like domains without a protocol, such as example.com/path.
  return /(?:^|[\s([{])(?:[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?\.)+[a-z]{2,24}(?=$|[\s)\]},/?:#])/iu.test(
    value,
  );
}

function locationNameVariants(value: string): string[] {
  const variants = [
    value,
    ...value.split(/[,;/|()[\]{}\-\u2013\u2014]+/u),
  ];
  return [...new Set(variants.map((variant) => normalizeText(variant)).filter(Boolean))];
}

function locationMatches(
  value: string,
  destination: string,
  attraction: string,
  aliases: LocationAlias[],
): boolean {
  const normalizedText = normalizeText(value);
  const expected = [
    ...locationNameVariants(destination),
    ...locationNameVariants(attraction),
  ];
  const normalizedExpected = new Set(expected);
  for (const alias of aliases) {
    const canonicalVariants = locationNameVariants(alias.canonical_location);
    if (canonicalVariants.some((variant) => normalizedExpected.has(variant))) {
      expected.push(...locationNameVariants(alias.alias));
    }
  }

  const textTokens = new Set(tokens(normalizedText));
  return expected.some((candidate) => {
    const phrase = candidate;
    if (!phrase) return false;
    if (` ${normalizedText} `.includes(` ${phrase} `)) return true;
    const compactPhrase = phrase.replace(/\s/g, '');
    // Common place names are often written both spaced and joined, for
    // example "TAR UMT" and "TARUMT" or "Kuala Lumpur" and
    // "KualaLumpur". Only accept the complete compact location token so a
    // short, unrelated partial word cannot satisfy the location check.
    if (compactPhrase.length >= 5 && textTokens.has(compactPhrase)) return true;
    const important = tokens(phrase).filter((token) => token.length >= 3 && !stopWords.has(token));
    if (important.length === 0) return false;
    const matches = important.filter((word) =>
      [...textTokens].some(
        (token) => token === word || (word.length >= 5 && levenshtein(token, word) <= 1),
      ),
    ).length;
    return matches / important.length >= 0.5;
  });
}

function locationPrompt(destination: string, attraction: string): string {
  const names = [...new Set([attraction.trim(), destination.trim()].filter(Boolean))];
  return names.length === 0
    ? 'Mention the completed trip location.'
    : `Mention ${names.join(' or ')}.`;
}

export function reviewPostText(input: ReviewInput): ReviewResult {
  const title = input.title.trim();
  const description = input.description.trim();
  const fieldErrors: Record<string, string> = {};
  if (title.length < 3 || title.length > 120) {
    fieldErrors.title = 'Title must be between 3 and 120 characters.';
  }
  if (description.length < 10 || description.length > 1000) {
    fieldErrors.description = 'Description must be between 10 and 1000 characters.';
  }
  if (Object.keys(fieldErrors).length > 0) {
    return { approved: false, reason: 'Check the highlighted fields.', code: 'INVALID_LENGTH', fieldErrors };
  }

  if (containsLink(title)) {
    fieldErrors.title = 'Links are not allowed in the title.';
  }
  if (containsLink(description)) {
    fieldErrors.description = 'Links are not allowed in the description.';
  }
  if (Object.keys(fieldErrors).length > 0) {
    return {
      approved: false,
      reason: 'Remove all links before submitting your post.',
      code: 'LINK_NOT_ALLOWED',
      fieldErrors,
    };
  }

  const titleQuality = textQualityError(title);
  const descriptionQuality = textQualityError(description);
  if (titleQuality) fieldErrors.title = titleQuality;
  if (descriptionQuality) fieldErrors.description = descriptionQuality;
  if (Object.keys(fieldErrors).length > 0) {
    return { approved: false, reason: 'Use clear, meaningful language.', code: 'LOW_QUALITY_TEXT', fieldErrors };
  }

  const titleContainsBlockedLanguage = containsBlockedLanguage(
    title,
    input.blockedTerms,
    input.allowList,
  );
  const descriptionContainsBlockedLanguage = containsBlockedLanguage(
    description,
    input.blockedTerms,
    input.allowList,
  );
  if (titleContainsBlockedLanguage || descriptionContainsBlockedLanguage) {
    if (titleContainsBlockedLanguage) {
      fieldErrors.title = 'Remove inappropriate or disguised abusive language from the title.';
    }
    if (descriptionContainsBlockedLanguage) {
      fieldErrors.description =
        'Remove inappropriate or disguised abusive language from the description.';
    }
    return {
      approved: false,
      reason: 'Your post contains inappropriate language. Remove it and try again.',
      code: 'INAPPROPRIATE_LANGUAGE',
      fieldErrors,
    };
  }

  const titleMatches = locationMatches(
    title,
    input.destination,
    input.attraction,
    input.aliases,
  );
  const descriptionMatches = locationMatches(
    description,
    input.destination,
    input.attraction,
    input.aliases,
  );
  if (!titleMatches || !descriptionMatches) {
    const prompt = locationPrompt(input.destination, input.attraction);
    if (!titleMatches) {
      fieldErrors.title =
        `The title must clearly relate to the completed trip location. ${prompt}`;
    }
    if (!descriptionMatches) {
      fieldErrors.description =
        `The description must clearly relate to the completed trip location. ${prompt}`;
    }
    const missingField = !titleMatches && !descriptionMatches
      ? 'The title and description must each'
      : !titleMatches
        ? 'The title must'
        : 'The description must';
    return {
      approved: false,
      reason: `${missingField} clearly relate to the completed trip location.`,
      code: 'LOCATION_MISMATCH',
      fieldErrors,
    };
  }

  return {
    approved: true,
    reason: 'The text is clear, appropriate, and related to the completed trip.',
    code: 'APPROVED',
    fieldErrors: {},
  };
}

export function detectLocationTags(input: {
  destination: string;
  attraction: string;
  placeTypes: string[];
  tags: TagRow[];
  rules: TagRule[];
  fallbackTagName: string;
}): DetectedTag[] {
  const location = normalizeText(`${input.destination} ${input.attraction}`);
  const placeTypes = new Set(input.placeTypes.map(normalizeText));
  const scores = new Map<number, number>();
  for (const rule of input.rules) {
    let matched = false;
    if (rule.location_pattern) {
      const pattern = normalizeText(rule.location_pattern);
      matched = pattern.length > 0 && (` ${location} `.includes(` ${pattern} `) || location.includes(pattern));
    }
    if (rule.place_type && placeTypes.has(normalizeText(rule.place_type))) matched = true;
    if (matched) scores.set(rule.tag_id, (scores.get(rule.tag_id) ?? 0) + Number(rule.weight || 1));
  }

  const ranked = input.tags
    .map((tag) => ({ tag, score: scores.get(tag.id) ?? 0 }))
    .filter((entry) => entry.score > 0)
    .sort((left, right) => right.score - left.score || left.tag.name.localeCompare(right.tag.name))
    .slice(0, 3)
    .map(({ tag }) => ({ id: tag.id, name: tag.name, type: tag.tag_type }));

  if (ranked.length > 0) return ranked;
  // Do not guess a category when Google Places returns no mapped location
  // type. Publishing fails closed until an explicit place-type rule exists.
  return [];
}
