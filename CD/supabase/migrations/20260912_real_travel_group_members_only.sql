-- Retire the meetup demo-member facility and require at least two real
-- membership rows before a creator can begin group navigation.

delete from public.travel_group_live_locations as location
using public.travel_group_trip_participants as participant
where location.session_id = participant.session_id
  and location.user_id = participant.user_id
  and participant.display_name like '%(Demo)%';

delete from public.travel_group_trip_participants
where display_name like '%(Demo)%';

delete from public.travel_group_join_requests
where traveller_name like '%(Demo)%';

delete from public.travel_group_members
where display_name like '%(Demo)%';

drop function if exists public.simulate_travel_group_members_toward_meetup(
  uuid, double precision, double precision, boolean
);

create or replace function public.begin_travel_group_journey(
  target_group_id uuid
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  target_session_id uuid;
  first_stop_id uuid;
  member_total integer;
  participant_total integer;
  missing_members integer;
begin
  if not public.is_travel_group_creator(target_group_id) then
    raise exception 'Only the creator can begin this journey';
  end if;

  select count(*)::integer into member_total
  from public.travel_group_members member
  where member.group_id = target_group_id;

  if member_total < 2 then
    raise exception 'At least two real travellers must join before the Travel Group can start';
  end if;

  select session.id into target_session_id
  from public.travel_group_trip_sessions session
  where session.group_id = target_group_id
    and session.status in ('active', 'paused')
  limit 1;

  if target_session_id is null then
    raise exception 'Confirm the group before beginning the journey';
  end if;

  select count(*)::integer into participant_total
  from public.travel_group_trip_participants participant
  where participant.session_id = target_session_id;

  if participant_total < 2 or participant_total <> member_total then
    raise exception 'Refresh the lobby so every joined traveller is included before starting';
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
    and (
      not participant.sharing_enabled
      or location.recorded_at is null
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
      current_stop_index = 0,
      journey_started_at = coalesce(journey_started_at, now())
  where id = target_session_id;

  update public.travel_groups
  set status = 'active', trip_phase = 'navigating'
  where id = target_group_id;

  return target_session_id;
end;
$$;

revoke all on function public.begin_travel_group_journey(uuid)
  from public, anon;
grant execute on function public.begin_travel_group_journey(uuid)
  to authenticated;
