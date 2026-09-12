-- A creator may own one ongoing Travel Group at a time. Ending a journey
-- atomically closes it and records the completed trip for every participant.

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
security definer
set search_path = public
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

  -- Serialize simultaneous create requests from the same signed-in user so
  -- the app receives the friendly error before the unique index is needed.
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 0));
  if exists (
    select 1
    from public.travel_groups
    where creator_id = auth.uid()
      and status in ('waiting', 'active')
  ) then
    raise exception 'End your current Travel Group before creating another one';
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

-- Group creation must go through the serialized function above. This keeps
-- concurrent devices from bypassing the one-ongoing-group rule.
revoke insert on table public.travel_groups from authenticated;
revoke all on function public.create_travel_group_with_destination(
  text, text, text, text[], integer, text, text, text, text,
  double precision, double precision, text
) from public, anon;
grant execute on function public.create_travel_group_with_destination(
  text, text, text, text[], integer, text, text, text, text,
  double precision, double precision, text
) to authenticated;

create or replace function public.end_travel_group_journey(target_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_group public.travel_groups%rowtype;
  target_session public.travel_group_trip_sessions%rowtype;
  completed_at timestamptz := now();
  journey_started timestamptz;
  itinerary_snapshot jsonb;
  total_distance numeric(10, 2);
  total_minutes integer;
begin
  if not public.is_travel_group_creator(target_group_id) then
    raise exception 'Only the creator can end this Travel Group';
  end if;

  select * into target_group
  from public.travel_groups
  where id = target_group_id
  for update;

  select * into target_session
  from public.travel_group_trip_sessions
  where group_id = target_group_id and status in ('active', 'paused')
  order by started_at desc
  limit 1
  for update;

  if target_session.id is null then
    raise exception 'There is no active Travel Group journey to end';
  end if;

  journey_started := coalesce(
    target_session.journey_started_at,
    target_session.started_at,
    completed_at
  );

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object('name', stop.place_name)
        order by stop.position
      ),
      '[]'::jsonb
    ),
    coalesce(sum(stop.travel_distance_from_previous_km), 0)::numeric(10, 2)
  into itinerary_snapshot, total_distance
  from public.travel_group_itinerary_stops stop
  where stop.group_id = target_group_id;

  total_minutes := greatest(
    0,
    floor(extract(epoch from (completed_at - journey_started)) / 60)::integer
  );

  insert into public.travel_history_entries (
    user_id, source_type, source_reference, title, destination,
    started_at, ended_at, distance_km, duration_minutes, tags,
    travel_mode, itinerary
  )
  select
    participant.user_id,
    'group',
    target_session.id::text,
    target_group.name,
    target_group.destination,
    journey_started,
    completed_at,
    total_distance,
    total_minutes,
    target_group.tags,
    'Travel Group',
    itinerary_snapshot
  from public.travel_group_trip_participants participant
  where participant.session_id = target_session.id
  on conflict (user_id, source_type, source_reference) do nothing;

  update public.travel_group_trip_sessions
  set status = 'completed', phase = 'completed', ended_at = completed_at,
      current_stop_id = null
  where id = target_session.id;

  update public.travel_groups
  set status = 'completed', trip_phase = 'completed'
  where id = target_group_id;

  delete from public.travel_group_live_locations
  where session_id = target_session.id;
end;
$$;

revoke all on function public.end_travel_group_journey(uuid) from public, anon;
grant execute on function public.end_travel_group_journey(uuid) to authenticated;
