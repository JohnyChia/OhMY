-- Creator-only recruitment management and privacy-safe member profile stats.

create or replace function public.remove_travel_group_member(
  target_group_id uuid,
  target_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_creator_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;

  select creator_id into target_creator_id
  from public.travel_groups
  where id = target_group_id
    and creator_id = auth.uid()
    and status = 'waiting'
    and trip_phase = 'recruiting'
    and confirmed_at is null
  for update;

  if target_creator_id is null then
    raise exception 'Travellers can only be removed by the creator while the group is recruiting';
  end if;
  if target_user_id = target_creator_id then
    raise exception 'The creator cannot be removed from their own group';
  end if;

  delete from public.travel_group_members
  where group_id = target_group_id and user_id = target_user_id;

  if not found then
    raise exception 'This traveller is no longer in the group';
  end if;

  delete from public.travel_group_join_requests
  where group_id = target_group_id and user_id = target_user_id;
end;
$$;

revoke all on function public.remove_travel_group_member(uuid, uuid)
  from public, anon;
grant execute on function public.remove_travel_group_member(uuid, uuid)
  to authenticated;

create or replace function public.travel_group_member_stats(
  target_group_id uuid
)
returns table (
  user_id uuid,
  completed_trips bigint,
  community_post_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not exists (
    select 1
    from public.travel_group_members viewer
    where viewer.group_id = target_group_id
      and viewer.user_id = auth.uid()
  ) then
    raise exception 'Only members can view traveller statistics';
  end if;

  return query
  select member.user_id,
    (
      select count(*)
      from public.travel_history_entries history
      where history.user_id = member.user_id
    ) as completed_trips,
    (
      select count(*)
      from public.community_posts post
      where post.author_id = member.user_id
    ) as community_post_count
  from public.travel_group_members member
  where member.group_id = target_group_id
  order by member.joined_at;
end;
$$;

revoke all on function public.travel_group_member_stats(uuid)
  from public, anon;
grant execute on function public.travel_group_member_stats(uuid)
  to authenticated;
