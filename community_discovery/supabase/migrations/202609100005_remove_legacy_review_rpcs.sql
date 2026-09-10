-- Remove obsolete client-side review/write paths after the Node v4 boundary.
-- The production feed and v4 service-only functions remain unchanged.
begin;

drop function if exists public.community_review_draft(text, text, text, text);
drop function if exists public.create_community_post_v3(uuid, text, text, text[], bigint[]);
drop function if exists public.update_community_post_v3(uuid, text, text, text[], bigint[]);
drop function if exists public.create_community_post_v2(uuid, text, text, text, bigint[]);
drop function if exists public.update_community_post_v2(uuid, text, text, text, bigint[]);
drop function if exists public.community_contains_blocked_word(text);
drop function if exists public.community_text_matches_trip(text, text, text, text);

commit;
