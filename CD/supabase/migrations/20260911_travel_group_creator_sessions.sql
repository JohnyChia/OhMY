-- Creator-led, plan-as-you-travel group sessions.
-- Additive migration for the existing Travel Group schema.

alter table public.travel_groups
  add column if not exists creator_name text not null default 'Traveller',
  add column if not exists destination_place_id text,
  add column if not exists destination_address text not null default '',
  add column if not exists destination_latitude double precision,
  add column if not exists destination_longitude double precision,
  add column if not exists destination_photo_name text,
  add column if not exists meetup_latitude double precision,
  add column if not exists meetup_longitude double precision,
  add column if not exists confirmed_at timestamptz,
  add column if not exists member_count integer not null default 1,
  add column if not exists trip_phase text not null default 'recruiting';

alter table public.travel_groups
  drop constraint if exists travel_groups_max_members_check;
alter table public.travel_groups
  alter column max_members set default 4;
alter table public.travel_groups
  add constraint travel_groups_max_members_check
  check (max_members between 2 and 4);

alter table public.travel_groups
  drop constraint if exists travel_groups_trip_phase_check;
alter table public.travel_groups
  add constraint travel_groups_trip_phase_check check (
    trip_phase in (
      'recruiting', 'gathering', 'navigating', 'choosing_next',
      'completed', 'cancelled'
    )
  );

alter table public.travel_groups
  drop constraint if exists travel_groups_destination_coordinates_check;
alter table public.travel_groups
  add constraint travel_groups_destination_coordinates_check check (
    (destination_latitude is null and destination_longitude is null)
    or
    (destination_latitude between -90 and 90
      and destination_longitude between -180 and 180)
  );

alter table public.travel_groups
  drop constraint if exists travel_groups_meetup_coordinates_check;
alter table public.travel_groups
  add constraint travel_groups_meetup_coordinates_check check (
    (meetup_latitude is null and meetup_longitude is null)
    or
    (meetup_latitude between -90 and 90
      and meetup_longitude between -180 and 180)
  );

alter table public.travel_group_join_requests
  add column if not exists traveller_name text not null default 'Traveller';

alter table public.travel_group_suggestions
  add column if not exists external_place_id text,
  add column if not exists latitude double precision,
  add column if not exists longitude double precision;

alter table public.travel_group_itinerary_stops
  add column if not exists external_place_id text,
  add column if not exists latitude double precision,
  add column if not exists longitude double precision;

alter table public.travel_group_trip_sessions
  add column if not exists phase text not null default 'gathering',
  add column if not exists journey_started_at timestamptz;

alter table public.travel_group_trip_sessions
  drop constraint if exists travel_group_trip_sessions_phase_check;
alter table public.travel_group_trip_sessions
  add constraint travel_group_trip_sessions_phase_check check (
    phase in ('gathering', 'navigating', 'choosing_next', 'completed', 'cancelled')
  );

create or replace function public.sync_travel_group_member_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_group_id uuid;
begin
  target_group_id := case
    when tg_op = 'DELETE' then old.group_id
    else new.group_id
  end;
  update public.travel_groups
  set member_count = (
    select count(*)::integer
    from public.travel_group_members member
    where member.group_id = target_group_id
  )
  where id = target_group_id;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.sync_travel_group_member_count() from public;

drop trigger if exists sync_travel_group_member_count
  on public.travel_group_members;
create trigger sync_travel_group_member_count
after insert or delete on public.travel_group_members
for each row execute function public.sync_travel_group_member_count();

create or replace function public.create_travel_group_with_destination(
  group_name text,
  destination_name text,
  group_description text,
  group_tags text[],
  group_max_members integer,
  group_join_mode text,
  creator_display_name text,
  external_destination_id text,
  destination_formatted_address text,
  destination_lat double precision,
  destination_lng double precision,
  destination_photo text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  new_group_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;
  if trim(group_name) = '' or trim(destination_name) = '' then
    raise exception 'A group title and destination are required';
  end if;
  if group_max_members not between 2 and 4 then
    raise exception 'A travel group allows 2 to 4 travellers';
  end if;

  insert into public.travel_groups (
    creator_id, creator_name, name, destination, description, tags,
    max_members, join_mode, status, trip_phase, destination_place_id,
    destination_address, destination_latitude, destination_longitude,
    destination_photo_name
  ) values (
    auth.uid(), coalesce(nullif(trim(creator_display_name), ''), 'Traveller'),
    trim(group_name), trim(destination_name), trim(group_description),
    coalesce(group_tags, '{}'), group_max_members, group_join_mode,
    'waiting', 'recruiting', external_destination_id,
    coalesce(destination_formatted_address, ''), destination_lat,
    destination_lng, destination_photo
  ) returning id into new_group_id;

  update public.travel_group_members
  set display_name = coalesce(nullif(trim(creator_display_name), ''), 'Traveller')
  where group_id = new_group_id and user_id = auth.uid();

  insert into public.travel_group_itinerary_stops (
    group_id, external_place_id, place_name, stop_type, position,
    duration_minutes, travel_minutes_from_previous, status, created_by,
    latitude, longitude
  ) values (
    new_group_id, external_destination_id, trim(destination_name), 'visit', 0,
    60, 0, 'upcoming', auth.uid(), destination_lat, destination_lng
  );

  return new_group_id;
end;
$$;

create or replace function public.confirm_travel_group(target_group_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  new_session_id uuid;
begin
  if not public.is_travel_group_creator(target_group_id) then
    raise exception 'Only the creator can confirm this group';
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

create or replace function public.begin_travel_group_journey(target_group_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  target_session_id uuid;
  first_stop_id uuid;
  missing_members integer;
begin
  if not public.is_travel_group_creator(target_group_id) then
    raise exception 'Only the creator can begin this journey';
  end if;

  select session.id into target_session_id
  from public.travel_group_trip_sessions session
  where session.group_id = target_group_id
    and session.status in ('active', 'paused')
  limit 1;

  if target_session_id is null then
    raise exception 'Confirm the group before beginning the journey';
  end if;
  if not exists (
    select 1 from public.travel_groups travel_group
    where travel_group.id = target_group_id
      and travel_group.meetup_latitude is not null
      and travel_group.meetup_longitude is not null
  ) then
    raise exception 'Set the meetup point before beginning the journey';
  end if;

  select count(*)::integer into missing_members
  from public.travel_group_trip_participants participant
  left join public.travel_group_live_locations location
    on location.session_id = participant.session_id
   and location.user_id = participant.user_id
  cross join public.travel_groups travel_group
  where participant.session_id = target_session_id
    and travel_group.id = target_group_id
    and participant.sharing_enabled
    and (
      location.recorded_at is null
      or location.recorded_at < now() - interval '2 minutes'
      or 6371000 * 2 * asin(sqrt(
        power(sin(radians(location.latitude - travel_group.meetup_latitude) / 2), 2)
        + cos(radians(travel_group.meetup_latitude))
        * cos(radians(location.latitude))
        * power(sin(radians(location.longitude - travel_group.meetup_longitude) / 2), 2)
      )) > 150
    );

  if missing_members > 0 then
    raise exception 'Everyone must be at the meetup point with a recent location before starting';
  end if;

  select stop.id into first_stop_id
  from public.travel_group_itinerary_stops stop
  where stop.group_id = target_group_id and stop.status <> 'completed'
  order by stop.position
  limit 1;

  if first_stop_id is null then
    raise exception 'The group needs a destination before starting';
  end if;

  update public.travel_group_itinerary_stops
  set status = case when id = first_stop_id then 'current' else status end
  where group_id = target_group_id;

  update public.travel_group_trip_sessions
  set phase = 'navigating', current_stop_id = first_stop_id,
      current_stop_index = 0, journey_started_at = coalesce(journey_started_at, now())
  where id = target_session_id;

  update public.travel_groups
  set status = 'active', trip_phase = 'navigating'
  where id = target_group_id;

  return target_session_id;
end;
$$;

create or replace function public.complete_travel_group_stop(
  target_group_id uuid,
  target_stop_id uuid
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not public.is_travel_group_creator(target_group_id) then
    raise exception 'Only the creator can complete a stop';
  end if;

  update public.travel_group_itinerary_stops
  set status = 'completed'
  where id = target_stop_id and group_id = target_group_id and status = 'current';
  if not found then
    raise exception 'Only the current stop can be completed';
  end if;

  update public.travel_group_trip_sessions
  set phase = 'choosing_next', current_stop_id = null
  where group_id = target_group_id and status in ('active', 'paused');
  update public.travel_groups
  set trip_phase = 'choosing_next'
  where id = target_group_id;
end;
$$;

create or replace function public.confirm_travel_group_suggestion(
  target_suggestion_id uuid
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  selected public.travel_group_suggestions%rowtype;
  new_stop_id uuid;
  next_position integer;
  active_phase text;
begin
  select * into selected
  from public.travel_group_suggestions
  where id = target_suggestion_id;
  if selected.id is null or not public.can_edit_travel_group(selected.group_id) then
    raise exception 'Only the creator can confirm this suggestion';
  end if;

  select id into new_stop_id
  from public.travel_group_itinerary_stops
  where suggestion_id = selected.id and group_id = selected.group_id;
  if new_stop_id is not null then
    return new_stop_id;
  end if;

  select coalesce(max(position), -1) + 1 into next_position
  from public.travel_group_itinerary_stops
  where group_id = selected.group_id;
  select trip_phase into active_phase
  from public.travel_groups where id = selected.group_id;

  update public.travel_group_suggestions
  set status = 'confirmed' where id = selected.id;
  insert into public.travel_group_itinerary_stops (
    group_id, suggestion_id, external_place_id, place_name, stop_type,
    position, duration_minutes, travel_minutes_from_previous, status,
    created_by, latitude, longitude
  ) values (
    selected.group_id, selected.id, selected.external_place_id,
    selected.place_name, 'visit', next_position, selected.duration_minutes,
    0, case when active_phase = 'choosing_next' then 'current' else 'upcoming' end,
    auth.uid(), selected.latitude, selected.longitude
  ) returning id into new_stop_id;

  if active_phase = 'choosing_next' then
    update public.travel_group_trip_sessions
    set phase = 'navigating', current_stop_id = new_stop_id,
        current_stop_index = next_position
    where group_id = selected.group_id and status in ('active', 'paused');
    update public.travel_groups
    set trip_phase = 'navigating'
    where id = selected.group_id;
  end if;

  return new_stop_id;
end;
$$;

create or replace function public.end_travel_group_journey(target_group_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not public.is_travel_group_creator(target_group_id) then
    raise exception 'Only the creator can end this journey';
  end if;
  update public.travel_group_trip_sessions
  set status = 'completed', phase = 'completed', ended_at = now(),
      current_stop_id = null
  where group_id = target_group_id and status in ('active', 'paused');
  update public.travel_groups
  set status = 'completed', trip_phase = 'completed'
  where id = target_group_id;
  delete from public.travel_group_live_locations
  where session_id in (
    select id from public.travel_group_trip_sessions where group_id = target_group_id
  );
end;
$$;

revoke all on function public.create_travel_group_with_destination(
  text, text, text, text[], integer, text, text, text, text,
  double precision, double precision, text
) from public;
revoke all on function public.confirm_travel_group(uuid) from public;
revoke all on function public.begin_travel_group_journey(uuid) from public;
revoke all on function public.complete_travel_group_stop(uuid, uuid) from public;
revoke all on function public.confirm_travel_group_suggestion(uuid) from public;
revoke all on function public.end_travel_group_journey(uuid) from public;

grant execute on function public.create_travel_group_with_destination(
  text, text, text, text[], integer, text, text, text, text,
  double precision, double precision, text
) to authenticated;
grant execute on function public.confirm_travel_group(uuid) to authenticated;
grant execute on function public.begin_travel_group_journey(uuid) to authenticated;
grant execute on function public.complete_travel_group_stop(uuid, uuid)
  to authenticated;
grant execute on function public.confirm_travel_group_suggestion(uuid)
  to authenticated;
grant execute on function public.end_travel_group_journey(uuid)
  to authenticated;
