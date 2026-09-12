-- Community Discovery: current usernames and owner moderation controls.
-- Shared profile, trip, and tags tables are not modified.
begin;

create or replace function public.community_user_display_name()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(trim(auth.jwt() -> 'user_metadata' ->> 'username'), ''),
    nullif(trim(auth.jwt() -> 'user_metadata' ->> 'display_name'), ''),
    nullif(trim(auth.jwt() -> 'user_metadata' ->> 'full_name'), ''),
    (
      select coalesce(
        nullif(trim(u.raw_user_meta_data ->> 'username'), ''),
        nullif(trim(u.raw_user_meta_data ->> 'display_name'), ''),
        nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''),
        nullif(split_part(u.email, '@', 1), '')
      )
      from auth.users u
      where u.id = auth.uid()
    ),
    'Traveller'
  );
$$;

-- Correct names already stored by the service-role publishing flow.
alter table public.community_posts
  disable trigger validate_community_post_trip_trigger;

update public.community_posts p
set author_name = coalesce(
  nullif(trim(u.raw_user_meta_data ->> 'username'), ''),
  nullif(trim(u.raw_user_meta_data ->> 'display_name'), ''),
  nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''),
  nullif(split_part(u.email, '@', 1), ''),
  p.author_name
)
from auth.users u
where p.author_id = u.id
  and not p.is_seed;

alter table public.community_posts
  enable trigger validate_community_post_trip_trigger;

update public.community_post_comments c
set author_name = coalesce(
  nullif(trim(u.raw_user_meta_data ->> 'username'), ''),
  nullif(trim(u.raw_user_meta_data ->> 'display_name'), ''),
  nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''),
  nullif(split_part(u.email, '@', 1), ''),
  c.author_name
)
from auth.users u
where c.user_id = u.id;

-- An author cannot save their own post. Remove old invalid rows before
-- enforcing the rule for future inserts.
delete from public.community_post_bookmarks b
using public.community_posts p
where p.id = b.post_id
  and p.author_id = b.user_id;

drop policy if exists community_bookmarks_insert_own
  on public.community_post_bookmarks;
create policy community_bookmarks_insert_own
on public.community_post_bookmarks
for insert
to authenticated
with check (
  user_id = auth.uid()
  and not exists (
    select 1
    from public.community_posts p
    where p.id = post_id
      and p.author_id = auth.uid()
  )
);

create or replace function public.community_delete_comment_v6(
  p_comment_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  comment_owner uuid;
  post_owner uuid;
begin
  if auth.uid() is null then
    raise exception 'Please sign in.';
  end if;

  select c.user_id, p.author_id
    into comment_owner, post_owner
  from public.community_post_comments c
  join public.community_posts p on p.id = c.post_id
  where c.id = p_comment_id;

  if not found then
    raise exception 'Comment not found.';
  end if;
  if comment_owner is distinct from auth.uid()
     and post_owner is distinct from auth.uid() then
    raise exception 'Only the comment author or post author can delete this comment.';
  end if;

  delete from public.community_post_comments
  where id = p_comment_id;
end;
$$;

create or replace function public.community_delete_post_v6(
  p_post_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  post_owner uuid;
  post_is_seed boolean;
begin
  if auth.uid() is null then
    raise exception 'Please sign in.';
  end if;

  select p.author_id, p.is_seed
    into post_owner, post_is_seed
  from public.community_posts p
  where p.id = p_post_id;

  if not found then
    raise exception 'Post not found.';
  end if;
  if post_is_seed or post_owner is distinct from auth.uid() then
    raise exception 'Only the author can delete this post.';
  end if;

  delete from public.community_posts
  where id = p_post_id;
end;
$$;

revoke all on function public.community_delete_comment_v6(uuid)
  from public, anon;
grant execute on function public.community_delete_comment_v6(uuid)
  to authenticated;

revoke all on function public.community_delete_post_v6(uuid)
  from public, anon;
grant execute on function public.community_delete_post_v6(uuid)
  to authenticated;

commit;
