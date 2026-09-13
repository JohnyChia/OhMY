const { detectLanguage } = require('./conversationGuardService');

const NAVIGATION_PATTERNS = Object.freeze([
  /^(?:please\s+)?(?:go|head|travel|drive|navigate)\s+(?:to\s+)?(.+)$/iu,
  /^(?:(?:please|can|could|would)\s+(?:you\s+)?)?(?:take|bring|get)\s+me\s+(?:to\s+)?(.+)$/iu,
  /^(?:can|could|shall)\s+(?:i|we)\s+(?:go|head|travel|drive)\s+(?:to\s+)?(.+)$/iu,
  /^(?:let(?:'|’)s|lets)\s+(?:go|head|travel|drive)\s+(?:to\s+)?(.+)$/iu,
  /^(?:i\s+(?:want|wanna|would\s+like)\s+to\s+)(?:go|travel|drive)\s+(?:to\s+)?(.+)$/iu,
  /^(?:i\s+(?:want|wanna|would\s+like)\s+to\s+)?(?:start|begin)\s+(?:a\s+)?(?:trip|journey)\s+(?:to\s+)?(.+)$/iu,
  /^(?:saya\s+(?:nak|mahu)\s+|nak\s+|mahu\s+)?(?:pergi|jalan)\s+(?:ke\s+)?(.+)$/iu,
  /^(?:(?:boleh|tolong)\s+)?(?:bawa\s+saya|pandu|navigasi)\s+(?:ke\s+)?(.+)$/iu,
  /^(?:jom\s+)?(?:pergi|jalan)\s+(?:ke\s+)?(.+)$/iu,
  /^(?:请)?(?:带我去|我要去|我想去|导航到|前往)(.+)$/u,
]);

function cleanDestination(value) {
  const cleaned = String(value || '')
    .trim()
    .replace(/[.!?。！？]+$/u, '')
    .replace(/(?:\s+(?:now|please|sekarang|sekarang juga|tolong))$/iu, '')
    .trim();
  return /^(?:to|ke)$/iu.test(cleaned) ? '' : cleaned;
}

function explicitNavigationRequest(text) {
  const value = String(text || '').trim();
  if (/\b(?:do not|don't|dont|never|not now|instead|or)\b|不要|别去|jangan/iu.test(value)) return null;
  for (const pattern of NAVIGATION_PATTERNS) {
    const destination = cleanDestination(value.match(pattern)?.[1]);
    if (!destination) continue;
    const languageCode = detectLanguage(value);
    return {
      destination,
      languageCode,
      style: languageCode === 'ms'
        ? 'malay'
        : languageCode === 'zh-CN' ? 'chinese' : 'english',
    };
  }
  return null;
}

module.exports = { explicitNavigationRequest, cleanDestination };
