const { detectLanguage } = require('./conversationGuardService');
const { requestTags } = require('./requestTagService');
const { explicitNavigationRequest } = require('./explicitNavigationService');

function categoryDestination(value) {
  const text = String(value || '').toLowerCase().trim().replace(/[.!?。！？]+$/u, '');
  // A category plus modifiers is not a named endpoint. Proper nouns left
  // after stripping these terms must still go through semantic interpretation.
  const words = text.replace(/\b(?:a|an|the|some|any|nearest|nearby|closest|local|good|nice|quiet|cheap|accessible|wheelchair|indoor|open|now|near|me|around|here|restaurant|restaurants|cafe|cafes|coffee|shop|shops|park|parks|museum|museums|hotel|hotels|beach|beaches|shopping|mall|malls|hiking|area|fast|food|chinese|western)\b/g, '')
    .replace(/附近|最近的|最近|一家|一个|咖啡店|咖啡馆|公园|博物馆|酒店|海滩|餐厅|快餐|中餐|西餐|购物中心/g, '')
    .replace(/\b(?:sebuah|kedai|kafe|restoran|taman|muzium|hotel|pantai|terdekat|berdekatan|dekat|saya)\b/g, '')
    .replace(/[\s,-]+/g, '');
  return Boolean(requestTags(text).length && !words);
}

function clarification(language) {
  return language === 'ms' ? 'Sila nyatakan satu tempat yang ingin dituju.'
    : language === 'zh-CN' ? '请确认你想前往的具体地点。'
      : 'Please confirm the specific place you want to go to.';
}

// Pure interpretation seam: no database writes or trip side effects.
function planSoloRequest(text) {
  const message = String(text || '').trim();
  const language = detectLanguage(message);
  const groupAction = /\b(?:create|start|join|leave|manage|kick|invite)\b.{0,40}\b(?:group|lobby)\b|\b(?:group trip|group travel)\b|旅行团|团体旅行|perjalanan berkumpulan/i.test(message);
  const tags = requestTags(message);
  const nearMe = /\b(?:near me|nearby|around me|my area|dekat saya|sekitar saya)\b|附近|我这里/i.test(message);
  const movement = explicitNavigationRequest(message);
  const discovery = Boolean(movement && categoryDestination(movement.destination));
  const unsafeMovement = /\b(?:do not|don't|dont|never|not now|instead|or)\b|不要|别去|jangan/iu.test(message);
  const replies = {
    en: 'Nova supports solo travel only. Please use Group Travel to manage a group journey.',
    ms: 'Nova hanya menyokong perjalanan solo. Sila gunakan Group Travel untuk mengurus perjalanan berkumpulan.',
    'zh-CN': 'Nova 只支持独自旅行。请使用 Group Travel 管理团体旅行。',
  };
  return {
    groupAction, language, nearMe,
    movement, discovery, unsafeMovement,
    destinationKind: discovery ? 'category' : movement ? 'unverified_endpoint' : 'unspecified',
    requirements: tags.map(tag => tag.query),
    simpleNearby: nearMe && !/\b(?:no|not|avoid|without|halal|cheap|budget|accessible|wheelchair|quiet|open|indoor)\b|不要|便宜|无障碍/i.test(message),
    reply: groupAction ? replies[language] || replies.en : '',
  };
}

function applySoloPolicy(classification, text) {
  const plan = planSoloRequest(text);
  const result = { ...classification, parameters: { ...classification.parameters } };
  if (plan.groupAction) {
    return { ...result, intent: 'out_of_scope', toolName: null, allowMap: false,
      draftResponse: plan.reply, draft_response: plan.reply };
  }
  if (result.intent === 'navigation') {
    const generic = plan.discovery || categoryDestination(result.parameters.destination);
    if (plan.unsafeMovement) {
      return { ...result, intent: 'clarification', toolName: null, allowMap: false,
        requiresClarification: true, draftResponse: clarification(plan.language),
        draft_response: clarification(plan.language) };
    }
    if (generic) {
      result.intent = 'recommendation';
      result.toolName = classification.toolName ? 'recommendation' : null;
      result.allowMap = false;
      result.parameters.requirements = [...new Set([
        ...plan.requirements, ...(result.parameters.requirements || []),
      ])];
      delete result.parameters.destination;
      result.location = { name: '', country: '' };
    }
  }
  result.requestPlan = { destination_kind: plan.destinationKind,
    location_source: plan.nearMe || plan.discovery ? 'device_gps' : 'explicit_or_context',
    navigation_allowed: result.intent === 'navigation' && Boolean(result.toolName) };
  return result;
}

module.exports = { planSoloRequest, applySoloPolicy, categoryDestination };
