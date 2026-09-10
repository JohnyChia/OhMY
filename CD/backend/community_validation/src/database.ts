import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { LocationAlias, ModerationTerm, TagRow, TagRule } from './nlp.js';

export interface ValidationContext {
  eligible: boolean;
  reason: string;
  destination: string;
  attraction: string;
  tripSessionId: string;
  existingPostId?: string | null;
}

export interface RuleData {
  blockedTerms: ModerationTerm[];
  allowList: string[];
  aliases: LocationAlias[];
  tags: TagRow[];
  tagRules: TagRule[];
  fallbackTagName: string;
}

export function createDatabaseClient(url: string, serviceRoleKey: string): SupabaseClient {
  return createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export async function authenticate(client: SupabaseClient, token: string): Promise<string> {
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) throw new Error('UNAUTHENTICATED');
  return data.user.id;
}

export async function loadValidationContext(
  client: SupabaseClient,
  userId: string,
  input: { tripSessionId?: string; postId?: string },
): Promise<ValidationContext> {
  const { data, error } = await client.rpc('community_validation_context_v4', {
    p_user_id: userId,
    p_trip_session_id: input.tripSessionId ?? null,
    p_post_id: input.postId ?? null,
  });
  if (error) throw error;
  const row = data as Record<string, unknown>;
  return {
    eligible: row.eligible === true,
    reason: String(row.reason ?? 'Trip validation failed.'),
    destination: String(row.destination ?? ''),
    attraction: String(row.attraction ?? ''),
    tripSessionId: String(row.trip_session_id ?? ''),
    existingPostId: row.existing_post_id ? String(row.existing_post_id) : null,
  };
}

export async function loadRuleData(client: SupabaseClient): Promise<RuleData> {
  const [termsResult, allowResult, aliasesResult, tagsResult, rulesResult, settingsResult] =
    await Promise.all([
      client.from('community_blocked_words').select('term, language').eq('active', true),
      client.from('community_moderation_allowlist').select('term').eq('active', true),
      client.from('community_location_aliases').select('canonical_location, alias').eq('active', true),
      client.from('tags').select('id, name, tag_type'),
      client
        .from('community_location_tag_rules')
        .select('tag_id, location_pattern, place_type, weight')
        .eq('active', true),
      client.from('community_nlp_settings').select('key, value'),
    ]);

  for (const result of [termsResult, allowResult, aliasesResult, tagsResult, rulesResult, settingsResult]) {
    if (result.error) throw result.error;
  }
  const settings = new Map(
    (settingsResult.data ?? []).map((row) => [String(row.key), String(row.value)]),
  );
  return {
    blockedTerms: (termsResult.data ?? []) as ModerationTerm[],
    allowList: (allowResult.data ?? []).map((row) => String(row.term)),
    aliases: (aliasesResult.data ?? []) as LocationAlias[],
    tags: (tagsResult.data ?? []).map((row) => ({
      id: Number(row.id),
      name: String(row.name),
      tag_type: String(row.tag_type),
    })),
    tagRules: (rulesResult.data ?? []).map((row) => ({
      tag_id: Number(row.tag_id),
      location_pattern: row.location_pattern ? String(row.location_pattern) : null,
      place_type: row.place_type ? String(row.place_type) : null,
      weight: Number(row.weight),
    })),
    fallbackTagName: settings.get('fallback_tag_name') ?? 'Cultural Experience',
  };
}
