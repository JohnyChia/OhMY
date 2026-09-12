CREATE OR REPLACE FUNCTION public.confirm_travel_group_suggestion(target_suggestion_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
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
    0, 'upcoming',
    auth.uid(), selected.latitude, selected.longitude
  ) returning id into new_stop_id;


  return new_stop_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.reorder_travel_group_itinerary(target_group_id uuid, ordered_stop_ids uuid[], leg_minutes integer[], leg_distances_km numeric[])
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if not public.is_travel_group_creator(target_group_id) then
    raise exception 'Only the creator can reorder the itinerary';
  end if;
  if not exists (
    select 1 from public.travel_groups
    where id = target_group_id and status in ('waiting', 'active')
  ) then
    raise exception 'The active itinerary cannot be reordered';
  end if;
  if cardinality(ordered_stop_ids) <> cardinality(leg_minutes)
      or cardinality(ordered_stop_ids) <> cardinality(leg_distances_km)
      or cardinality(ordered_stop_ids) <> (
        select count(*) from public.travel_group_itinerary_stops
        where group_id = target_group_id
      ) then
    raise exception 'The itinerary order is incomplete';
  end if;

  if (select count(distinct id) from unnest(ordered_stop_ids) as t(id)) <> cardinality(ordered_stop_ids)
      or exists (
        select 1 from public.travel_group_itinerary_stops s
        where s.group_id = target_group_id
          and (s.position = 0 or s.status in ('completed', 'current'))
          and ordered_stop_ids[s.position + 1] is distinct from s.id
      ) then
    raise exception 'The first destination, completed stops and active destination cannot move';
  end if;
  update public.travel_group_itinerary_stops
  set position = position + 100000
  where group_id = target_group_id;

  with requested as (
    select stop_id, ordinal - 1 as new_position,
      leg_minutes[ordinal] as new_minutes,
      leg_distances_km[ordinal] as new_distance
    from unnest(ordered_stop_ids) with ordinality as item(stop_id, ordinal)
  )
  update public.travel_group_itinerary_stops as stop
  set position = requested.new_position,
      travel_minutes_from_previous = greatest(requested.new_minutes, 0),
      travel_distance_from_previous_km = greatest(requested.new_distance, 0)
  from requested
  where stop.id = requested.stop_id and stop.group_id = target_group_id;

  if exists (
    select 1 from public.travel_group_itinerary_stops
    where group_id = target_group_id and position >= 100000
  ) then
    raise exception 'The itinerary contains an invalid stop';
  end if;
end;
$function$
;
create or replace function public.start_next_travel_group_leg(target_group_id uuid)
returns uuid language plpgsql security invoker set search_path = ''
as $$
declare
  next_stop public.travel_group_itinerary_stops%rowtype;
  session_id uuid;
begin
  if not public.is_travel_group_creator(target_group_id) then
    raise exception 'Only the creator can start the next leg';
  end if;
  perform 1 from public.travel_groups where id = target_group_id
    and status = 'active' and trip_phase = 'choosing_next' for update;
  if not found then raise exception 'Finish the current destination before starting the next leg'; end if;
  select * into next_stop from public.travel_group_itinerary_stops
    where group_id = target_group_id and status = 'upcoming' order by position limit 1;
  if next_stop.id is null then raise exception 'Confirm a destination in the itinerary first'; end if;
  select id into session_id from public.travel_group_trip_sessions
    where group_id = target_group_id and status in ('active', 'paused') limit 1;
  if session_id is null then raise exception 'The Travel Group session has ended'; end if;
  update public.travel_group_itinerary_stops set status = 'current' where id = next_stop.id;
  update public.travel_group_trip_sessions set phase = 'navigating', current_stop_id = next_stop.id,
    current_stop_index = next_stop.position where id = session_id;
  update public.travel_groups set trip_phase = 'navigating' where id = target_group_id;
  return next_stop.id;
end;
$$;
revoke all on function public.start_next_travel_group_leg(uuid) from public, anon;
grant execute on function public.start_next_travel_group_leg(uuid) to authenticated;
