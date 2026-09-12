-- Community Discovery: server-enforced comment throttling and duplicate checks.
begin;

create or replace function public.community_add_comment_v7(
  p_post_id uuid,
  p_content text
) returns setof public.community_post_comments
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  clean_content text := trim(coalesce(p_content, ''));
  normalized_content text;
begin
  if current_user_id is null then
    raise exception 'Please sign in to comment.';
  end if;
  if char_length(clean_content) < 1 or char_length(clean_content) > 500 then
    raise exception 'Comments must be 1-500 characters.';
  end if;
  if not exists (
    select 1 from public.community_posts where id = p_post_id
  ) then
    raise exception 'Post not found.';
  end if;

  -- Serialize comment attempts from one account so parallel requests cannot
  -- bypass the cooldown or per-minute cap.
  perform pg_advisory_xact_lock(hashtextextended(current_user_id::text, 0));

  if exists (
    select 1
    from public.community_post_comments
    where user_id = current_user_id
      and post_id = p_post_id
      and created_at > now() - interval '5 minutes'
  ) then
    raise exception 'Please wait 5 minutes before commenting on this post again.';
  end if;

  normalized_content := lower(regexp_replace(clean_content, '\s+', ' ', 'g'));
  if exists (
    select 1
    from public.community_post_comments
    where user_id = current_user_id
      and post_id = p_post_id
      and created_at > now() - interval '10 minutes'
      and lower(regexp_replace(trim(content), '\s+', ' ', 'g')) = normalized_content
  ) then
    raise exception 'You already posted this comment recently.';
  end if;

  return query
  insert into public.community_post_comments (post_id, user_id, content)
  values (p_post_id, current_user_id, clean_content)
  returning *;
end;
$$;

revoke all on function public.community_add_comment_v7(uuid, text)
  from public, anon;
grant execute on function public.community_add_comment_v7(uuid, text)
  to authenticated;

-- Force client writes through the guarded RPC. The security-definer function
-- keeps its owner-level insert access.
revoke insert on table public.community_post_comments from anon, authenticated;

commit;
