const LOCAL_REPLIES = Object.freeze({
  unintelligible: {
    en: "I couldn't understand that. Please try again with a trip, place, or weather question.",
    ms: 'Saya kurang faham. Cuba lagi dengan soalan tentang perjalanan, tempat atau cuaca.',
    'zh-CN': '我不太明白。请再试一次，询问行程、地点或天气。',
  },
  abusive: {
    en: 'I can help with travel, places, and weather, but please keep the conversation respectful.',
    ms: 'Saya boleh bantu tentang perjalanan, tempat dan cuaca, tetapi sila berbual dengan sopan.',
    'zh-CN': '我可以协助行程、地点和天气问题，但请保持礼貌。',
  },
});

function detectLanguage(text) {
  if (/\p{Script=Han}/u.test(text)) return 'zh-CN';
  if (/\b(?:saya|awak|tolong|cari|pergi|cuaca|tempat|bodoh|bangang)\b/iu.test(text)) return 'ms';
  return 'en';
}

function hasTravelSignal(text) {
  return /\b(?:trip|travel|journey|weather|place|hotel|restaurant|go|visit|route|navigate|pergi|jalan|cuaca|tempat|makan|hotel|restoran)\b|旅行|天气|地点|餐厅|酒店|导航|去/iu.test(text);
}

function isClearlyGibberish(text) {
  const value = String(text || '').trim();
  if (!value) return true;
  const compact = value.replace(/\s+/g, '').toLocaleLowerCase();
  if (/^(?:asdfghjkl|asdf|qwertyuiop|qwerty|zxcvbnm|zxcv|hjkl)+$/u.test(compact)) return true;
  if (/(.)\1{7,}/u.test(value)) return true;
  const meaningful = value.match(/[\p{Letter}\p{Number}]/gu)?.length || 0;
  if (meaningful === 0) return true;
  return value.length >= 4 && meaningful / value.length < 0.25;
}

function isAbuseOnly(text) {
  const value = String(text || '');
  const abusive = /\b(?:fuck you|idiot|stupid|moron|bodoh|bangang|babi)\b|傻逼|白痴/iu.test(value);
  return abusive && !hasTravelSignal(value);
}

function guardConversationInput(text) {
  const languageCode = detectLanguage(String(text || ''));
  if (isClearlyGibberish(text)) {
    return {
      handled: true,
      intent: 'unintelligible',
      languageCode,
      reply: LOCAL_REPLIES.unintelligible[languageCode],
    };
  }
  if (isAbuseOnly(text)) {
    return {
      handled: true,
      intent: 'abusive',
      languageCode,
      reply: LOCAL_REPLIES.abusive[languageCode],
    };
  }
  return { handled: false, languageCode };
}

module.exports = {
  guardConversationInput,
  detectLanguage,
  isClearlyGibberish,
  isAbuseOnly,
};
