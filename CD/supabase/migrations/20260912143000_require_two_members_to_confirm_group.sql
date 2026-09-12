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

drop policy if exists "authenticated users discover travel groups"
  on public.travel_groups;

create policy "members read private travel group details"
on public.travel_groups
for select
to authenticated
using (creator_id = (select auth.uid()) or public.is_travel_group_member(id));

create or replace function public.discover_travel_groups(
  requested_group_id uuid default null
)
returns table (
  id uuid,
  creator_id uuid,
  creator_name text,
  name text,
  destination text,
  description text,
  join_mode text,
  status text,
  max_members integer,
  tags text[],
  created_at timestamptz,
  updated_at timestamptz,
  destination_place_id text,
  destination_address text,
  destination_latitude double precision,
  destination_longitude double precision,
  destination_photo_name text,
  confirmed_at timestamptz,
  member_count integer,
  trip_phase text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    travel_group.id,
    travel_group.creator_id,
    travel_group.creator_name,
    travel_group.name,
    travel_group.destination,
    travel_group.description,
    travel_group.join_mode,
    travel_group.status,
    travel_group.max_members,
    travel_group.tags,
    travel_group.created_at,
    travel_group.updated_at,
    travel_group.destination_place_id,
    travel_group.destination_address,
    travel_group.destination_latitude,
    travel_group.destination_longitude,
    travel_group.destination_photo_name,
    travel_group.confirmed_at,
    travel_group.member_count,
    travel_group.trip_phase
  from public.travel_groups travel_group
  where (select auth.uid()) is not null
  and case
    when requested_group_id is null then
      travel_group.status not in ('completed', 'cancelled')
    else travel_group.id = requested_group_id
  end
  order by travel_group.created_at desc
  limit 100;
$$;

revoke all on function public.discover_travel_groups(uuid) from public;
revoke all on function public.discover_travel_groups(uuid) from anon;
grant execute on function public.discover_travel_groups(uuid) to authenticated;
