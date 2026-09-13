// Ephemeral search constraints. Never persisted as traveler preferences.
const categories = [
  { tag: 'park', pattern: /\bparks?\b|taman|公园/i, query: 'park', types: ['park', 'national_park'] },
  { tag: 'museum', pattern: /\bmuseums?\b|muzium|博物馆/i, query: 'museum', types: ['museum'] },
  { tag: 'shopping', pattern: /\bshopping\b|\bmall\b|买东西|购物|membeli belah/i, query: 'shopping mall', types: ['shopping_mall'] },
  { tag: 'hotel', pattern: /\bhotels?\b|\baccommodation\b|penginapan|酒店|住宿/i, query: 'hotel', types: ['hotel', 'lodging'] },
  { tag: 'beach', pattern: /\bbeaches?\b|pantai|海滩/i, query: 'beach', types: ['beach'] },
  { tag: 'hiking', pattern: /\bhik(?:e|ing)\b|mendaki|徒步|登山/i, query: 'hiking area', types: ['hiking_area'] },
  { tag: 'fast_food', pattern: /fast[ _-]?food|makanan segera|快餐/i, query: 'fast food restaurant', types: ['fast_food_restaurant'] },
  { tag: 'chinese_cuisine', pattern: /\bchinese\s+(?:food|cuisines?|restaurants?|dining|dishes?|eateries)\b|(?:makanan|restoran|masakan)\s+(?:cina|chinese)|中餐|中华料理/i, query: 'Chinese restaurant', types: ['chinese_restaurant'] },
  { tag: 'western_cuisine', pattern: /\bwestern\s+(?:food|cuisines?|restaurants?|dining|dishes?|eateries)\b|(?:makanan|restoran|masakan)\s+(?:barat|western)|西餐/i, query: 'Western restaurant', types: ['american_restaurant', 'steak_house'] },
  { tag: 'hotpot', pattern: /\bhot[ -]?pot\b|火锅/i, query: 'hot pot restaurant', types: ['hot_pot_restaurant'] },
  { tag: 'cafe', pattern: /\bcaf[eé]s?\b|\bcoffee\s+shops?\b|咖啡|kafe/i, query: 'cafe', types: ['cafe', 'coffee_shop'] },
];

function requestTags(text) {
  const value = String(text || '');
  return categories.filter((category) => {
    const match = value.match(category.pattern);
    if (!match) return false;
    const prefix = value.slice(Math.max(0, match.index - 24), match.index);
    return !/(?:\b(?:no|not|avoid|without)\s+(?:any\s+)?|不要|不去|避免|bukan\s+|elak\s+)$/i.test(prefix);
  });
}

function matchesRequest(place, constraints) {
  const types = [place.primaryType, ...(place.types || [])];
  const label = [place.displayName?.text, place.primaryTypeDisplayName?.text,
    typeof place.primaryTypeDisplayName === 'string' ? place.primaryTypeDisplayName : '']
    .filter(Boolean).join(' ');
  return constraints.every((constraint) =>
    constraint.types.some((type) => types.includes(type)) || constraint.pattern.test(label));
}

module.exports = { requestTags, matchesRequest };
