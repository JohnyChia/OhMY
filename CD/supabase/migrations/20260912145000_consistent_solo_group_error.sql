create or replace function public.confirm_travel_group(target_group_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  new_session_id uuid;
  accepted_member_count integer;
begin
  if not public.is_travel_group_creator(target_group_id) then
    raise exception 'Only the creator can confirm this group';
  end if;

  select count(*)::integer into accepted_member_count
  from public.travel_group_members member
  where member.group_id = target_group_id;

  if accepted_member_count < 2 then
    raise exception 'Wait for another traveller before confirming the group';
  end if;

  select id into new_session_id
  from public.travel_group_trip_sessions
  where group_id = target_group_id and status in ('active', 'paused')
  limit 1;

  if new_session_id is null then
    insert into public.travel_group_trip_sessions (
      group_id, status, phase, started_by
    ) values (target_group_id, 'active', 'gathering', auth.uid())
    returning id into new_session_id;
  end if;

  insert into public.travel_group_trip_participants (
    session_id, user_id, display_name, avatar_url, role
  )
  select
    new_session_id,
    member.user_id,
    coalesce(nullif(member.display_name, ''), 'Traveller'),
    member.avatar_url,
    member.role
  from public.travel_group_members member
  where member.group_id = target_group_id
  on conflict (session_id, user_id) do update
  set display_name = excluded.display_name,
      avatar_url = excluded.avatar_url,
      role = excluded.role,
      last_seen_at = now();

  update public.travel_groups
  set confirmed_at = coalesce(confirmed_at, now()), trip_phase = 'gathering'
  where id = target_group_id;

  return new_session_id;
end;
$$;
