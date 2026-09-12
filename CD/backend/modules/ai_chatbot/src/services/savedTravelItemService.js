const crypto = require('crypto');
const supabase = require('../config/supabase');
const linkAnalysisService = require('./linkAnalysisService');

const fallbackItems = new Map();

function clean(value, max = 2000) {
  return String(value || '').replace(/\s+/g, ' ').trim().slice(0, max);
}

function safeHttpsUrl(value) {
  const source = clean(value, 2000);
  if (!source) return null;
  try {
    const url = new URL(source);
    return url.protocol === 'https:' ? url.toString() : null;
  } catch (_) {
    return null;
  }
}

function canonicalItem(parameters = {}, context = {}) {
  const attachment = context.attachment?.analysisStatus === 'ready'
    ? context.attachment
    : null;
  const analysis = attachment?.analysis || {};
  const requestedUrl = safeHttpsUrl(parameters.source_url);
  const sourceType = attachment
    ? (analysis.type === 'image' ? 'image' : 'file')
    : requestedUrl
      ? 'link'
      : parameters.source_type === 'message'
        ? 'message'
        : 'place';
  const locationHint = clean(
    analysis.locationHint || analysis.normalizedContext?.locationHint || parameters.location_hint,
    240,
  );
  const tags = [...new Set([
    ...(Array.isArray(analysis.travelTags) ? analysis.travelTags : []),
    ...(Array.isArray(parameters.travel_tags) ? parameters.travel_tags : []),
  ].map((tag) => clean(tag, 80)).filter(Boolean))].slice(0, 24);
  const summary = clean(
    analysis.visualContext || analysis.extractedText || parameters.summary,
    4000,
  );
  const sourceName = clean(attachment?.name || parameters.source_name || requestedUrl || locationHint, 240);
  const title = clean(parameters.title || locationHint || sourceName || 'Saved travel item', 240);
  const hashMaterial = JSON.stringify({ sourceType, sourceName, requestedUrl, locationHint, tags, summary });
  return {
    source_type: sourceType,
    source_name: sourceName,
    source_url: requestedUrl,
    storage_path: null,
    content_hash: crypto.createHash('sha256').update(hashMaterial).digest('hex'),
    title,
    summary,
    location_hint: locationHint || null,
    google_place_id: clean(parameters.google_place_id, 240) || null,
    latitude: Number.isFinite(parameters.latitude) ? parameters.latitude : null,
    longitude: Number.isFinite(parameters.longitude) ? parameters.longitude : null,
    travel_tags: tags,
    metadata: {
      attachment_type: clean(analysis.type, 40) || null,
      verified_analysis: Boolean(attachment),
      original_binary_saved: false,
    },
  };
}

async function save(userId, parameters, context) {
  let enriched = { ...parameters };
  if (parameters?.source_url) {
    try {
      const link = await linkAnalysisService.analyze(parameters.source_url);
      enriched = {
        ...enriched,
        source_url: link.url,
        title: clean(enriched.title || link.title, 240),
        summary: clean(enriched.summary || link.content, 4000),
      };
    } catch (error) {
      // A valid HTTPS link remains useful saved data when the remote site is
      // temporarily unavailable. It can be analysed again when recalled.
      enriched = {
        ...enriched,
        summary: clean(enriched.summary || `Saved link: ${parameters.source_url}`, 4000),
      };
    }
  }
  const item = canonicalItem(enriched, context);
  if (!item.location_hint && !item.summary && !item.source_url) {
    return { success: false, error: 'There is no verified travel item or HTTPS link to save.' };
  }
  const row = { ...item, user_id: userId, updated_at: new Date().toISOString() };
  try {
    const { data, error } = await supabase
      .from('saved_travel_items')
      .upsert(row, { onConflict: 'user_id,content_hash' })
      .select()
      .single();
    if (error) throw error;
    return { success: true, saved: true, item: data };
  } catch (error) {
    console.warn('Supabase saved travel item unavailable, using bounded memory fallback:', error.message);
    const userItems = fallbackItems.get(userId) || [];
    const existing = userItems.findIndex((entry) => entry.content_hash === item.content_hash);
    const saved = { id: existing >= 0 ? userItems[existing].id : crypto.randomUUID(), ...row };
    if (existing >= 0) userItems[existing] = saved;
    else userItems.unshift(saved);
    fallbackItems.set(userId, userItems.slice(0, 100));
    return { success: true, saved: true, item: saved, persistence: 'memory_fallback' };
  }
}

async function list(userId, limit = 20) {
  const bounded = Math.max(1, Math.min(Number(limit) || 20, 50));
  try {
    const { data, error } = await supabase
      .from('saved_travel_items')
      .select('*')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(bounded);
    if (error) throw error;
    return { success: true, items: data || [] };
  } catch (error) {
    return { success: true, items: (fallbackItems.get(userId) || []).slice(0, bounded), persistence: 'memory_fallback' };
  }
}

async function remove(userId, itemId) {
  const id = clean(itemId, 80);
  if (!id) return { success: false, error: 'A saved item id is required.' };
  try {
    const { error } = await supabase
      .from('saved_travel_items')
      .delete()
      .eq('user_id', userId)
      .eq('id', id);
    if (error) throw error;
    return { success: true, removed: true, id };
  } catch (error) {
    const items = fallbackItems.get(userId) || [];
    fallbackItems.set(userId, items.filter((item) => item.id !== id));
    return { success: true, removed: true, id, persistence: 'memory_fallback' };
  }
}

function relevant(items, query, limit = 5) {
  const words = new Set(clean(query, 1000).toLowerCase().split(/[^\p{L}\p{N}]+/u).filter((word) => word.length > 1));
  return items
    .map((item) => {
      const haystack = [item.title, item.summary, item.location_hint, ...(item.travel_tags || [])]
        .join(' ').toLowerCase();
      const score = [...words].reduce((total, word) => total + (haystack.includes(word) ? 1 : 0), 0);
      return { item, score };
    })
    .filter(({ score }) => score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, limit)
    .map(({ item }) => item);
}

module.exports = { canonicalItem, save, list, remove, relevant };
