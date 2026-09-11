-- Creator-only testing helper for moving explicitly labelled demo travellers.
-- Real participants and the creator's device location are never modified.

create or replace function public.simulate_travel_group_members_toward_meetup(
  target_session_id uuid,
  target_latitude double precision,
  target_longitude double precision,
  reset_positions boolean default false
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  target_group_id uuid;
  session_phase text;
  session_status text;
  participant record;
  current_latitude double precision;
  current_longitude double precision;
  start_distance_km double precision;
  angle_radians double precision;
  remaining_distance_km double precision;
  simulated_count integer := 0;
begin
  if caller_id is null then
    raise exception 'Authentication is required';
  end if;
  if target_latitude not between -90 and 90
      or target_longitude not between -180 and 180 then
    raise exception 'A valid meetup coordinate is required';
  end if;

  select session.group_id, session.phase, session.status
  into target_group_id, session_phase, session_status
  from public.travel_group_trip_sessions as session
  join public.travel_groups as travel_group
    on travel_group.id = session.group_id
  where session.id = target_session_id
    and travel_group.creator_id = caller_id;

  if target_group_id is null then
    raise exception 'Only the group creator can run meetup simulation';
  end if;
  if session_status not in ('active', 'paused') or session_phase <> 'gathering' then
    raise exception 'Meetup simulation is only available during gathering';
  end if;

  for participant in
    select trip_participant.user_id,
           row_number() over (order by trip_participant.user_id) as sequence
    from public.travel_group_trip_participants as trip_participant
    where trip_participant.session_id = target_session_id
      and trip_participant.user_id <> caller_id
      and trip_participant.display_name like '%(Demo)%'
  loop
    select location.latitude, location.longitude
    into current_latitude, current_longitude
    from public.travel_group_live_locations as location
    where location.session_id = target_session_id
      and location.user_id = participant.user_id;

    if reset_positions or not found then
      -- Give every demo traveller a unique starting point 6-8 km away.
      start_distance_km := 9.0 - least(participant.sequence::double precision, 3.0);
      angle_radians := radians(participant.sequence::double precision * 137.0);
      current_latitude := target_latitude
        + (start_distance_km / 111.32) * cos(angle_radians);
      current_longitude := target_longitude
        + (start_distance_km / (
          111.32 * greatest(abs(cos(radians(target_latitude))), 0.01)
        )) * sin(angle_radians);
    else
      remaining_distance_km := public.travel_group_distance_km(
        current_latitude,
        current_longitude,
        target_latitude,
        target_longitude
      );
      if remaining_distance_km <= 0.25 then
        current_latitude := target_latitude;
        current_longitude := target_longitude;
      else
        -- Close 45% of the remaining straight-line distance on each tick.
        current_latitude := current_latitude
          + (target_latitude - current_latitude) * 0.45;
        current_longitude := current_longitude
          + (target_longitude - current_longitude) * 0.45;
      end if;
    end if;

    insert into public.travel_group_live_locations (
      session_id,
      user_id,
      latitude,
      longitude,
      accuracy_m,
      speed_mps,
      recorded_at
    ) values (
      target_session_id,
      participant.user_id,
      current_latitude,
      current_longitude,
      8,
      1.4,
      now()
    )
    on conflict (session_id, user_id) do update
    set latitude = excluded.latitude,
        longitude = excluded.longitude,
        accuracy_m = excluded.accuracy_m,
        speed_mps = excluded.speed_mps,
        recorded_at = excluded.recorded_at;

    update public.travel_group_trip_participants
    set sharing_enabled = true,
        last_seen_at = now()
    where session_id = target_session_id
      and user_id = participant.user_id;

    simulated_count := simulated_count + 1;
  end loop;

  return simulated_count;
end;
$$;

revoke all on function public.simulate_travel_group_members_toward_meetup(
  uuid, double precision, double precision, boolean
) from public, anon;
grant execute on function public.simulate_travel_group_members_toward_meetup(
  uuid, double precision, double precision, boolean
) to authenticated;
