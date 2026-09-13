-- A Travel Group history entry represents places the travellers actually
-- reached. Planned or confirmed stops that were still upcoming when the
-- creator ended the session must not appear in history or contribute distance.

create or replace function public.end_travel_group_journey(target_group_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
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
  where stop.group_id = target_group_id
    and stop.status = 'completed';

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

revoke all on function public.end_travel_group_journey(uuid)
  from public, anon;
grant execute on function public.end_travel_group_journey(uuid)
  to authenticated;

notify pgrst, 'reload schema';
