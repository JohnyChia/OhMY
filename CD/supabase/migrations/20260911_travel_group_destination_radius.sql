alter table public.travel_group_join_requests
  add column if not exists request_latitude double precision,
  add column if not exists request_longitude double precision,
  add column if not exists destination_distance_km double precision;

create or replace function public.travel_group_distance_km(
  first_latitude double precision,
  first_longitude double precision,
  second_latitude double precision,
  second_longitude double precision
)
returns double precision
language sql
immutable
security invoker
set search_path = ''
as $$
  select 6371.0 * acos(
    least(1.0, greatest(-1.0,
      sin(radians(first_latitude)) * sin(radians(second_latitude))
      + cos(radians(first_latitude)) * cos(radians(second_latitude))
      * cos(radians(second_longitude - first_longitude))
    ))
  );
$$;

create or replace function public.validate_travel_group_join_proximity()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  target_group public.travel_groups%rowtype;
begin
  if new.request_latitude is null or new.request_longitude is null
      or new.request_latitude not between -90 and 90
      or new.request_longitude not between -180 and 180 then
    raise exception 'A valid current location is required to join';
  end if;

  select * into target_group
  from public.travel_groups
  where id = new.group_id;

  if not found or target_group.destination_latitude is null
      or target_group.destination_longitude is null then
    raise exception 'This group has no valid destination location';
  end if;

  new.destination_distance_km := public.travel_group_distance_km(
    new.request_latitude,
    new.request_longitude,
    target_group.destination_latitude,
    target_group.destination_longitude
  );

  if new.destination_distance_km > 10.0 then
    raise exception 'Traveller must be within 10 km of the destination';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_travel_group_join_proximity
  on public.travel_group_join_requests;
create trigger validate_travel_group_join_proximity
before insert or update of group_id, request_latitude, request_longitude
on public.travel_group_join_requests
for each row execute function public.validate_travel_group_join_proximity();

revoke all on function public.join_open_travel_group(uuid, text) from public;
revoke execute on function public.join_open_travel_group(uuid, text) from anon, authenticated;
drop function public.join_open_travel_group(uuid, text);

create function public.join_open_travel_group(
  target_group_id uuid,
  member_display_name text,
  member_latitude double precision,
  member_longitude double precision
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_group public.travel_groups%rowtype;
  target_session_id uuid;
  current_member_count integer;
  destination_distance_km double precision;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  if member_latitude is null or member_longitude is null
      or member_latitude not between -90 and 90
      or member_longitude not between -180 and 180 then
    raise exception 'A valid current location is required to join';
  end if;

  select * into target_group
  from public.travel_groups
  where id = target_group_id
  for update;

  if not found then raise exception 'Travel group not found'; end if;
  if target_group.destination_latitude is null
      or target_group.destination_longitude is null then
    raise exception 'This group has no valid destination location';
  end if;

  destination_distance_km := public.travel_group_distance_km(
    member_latitude,
    member_longitude,
    target_group.destination_latitude,
    target_group.destination_longitude
  );
  if destination_distance_km > 10.0 then
    raise exception 'Traveller must be within 10 km of the destination';
  end if;

  if target_group.join_mode <> 'open' then
    raise exception 'This group requires creator approval';
  end if;
  if target_group.status <> 'waiting'
      or target_group.trip_phase not in ('recruiting', 'gathering') then
    raise exception 'This group is no longer accepting travellers';
  end if;
  if exists (
    select 1 from public.travel_group_members
    where group_id = target_group_id and user_id = auth.uid()
  ) then
    return;
  end if;

  select count(*)::integer into current_member_count
  from public.travel_group_members where group_id = target_group_id;
  if current_member_count >= target_group.max_members then
    raise exception 'The group is already full';
  end if;

  insert into public.travel_group_members (
    group_id, user_id, role, display_name
  ) values (
    target_group_id, auth.uid(), 'member',
    coalesce(nullif(trim(member_display_name), ''), 'Traveller')
  );

  select id into target_session_id
  from public.travel_group_trip_sessions
  where group_id = target_group_id and status in ('active', 'paused')
    and phase = 'gathering'
  limit 1;

  if target_session_id is not null then
    insert into public.travel_group_trip_participants (
      session_id, user_id, display_name, role, sharing_enabled
    ) values (
      target_session_id, auth.uid(),
      coalesce(nullif(trim(member_display_name), ''), 'Traveller'), 'member', true
    ) on conflict (session_id, user_id) do update
      set display_name = excluded.display_name,
          sharing_enabled = true,
          last_seen_at = now();
  end if;
end;
$$;

create or replace function public.respond_travel_group_join_request(
  target_request_id uuid,
  accept_request boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  join_request public.travel_group_join_requests%rowtype;
  target_group public.travel_groups%rowtype;
  target_session_id uuid;
  current_member_count integer;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;

  select * into join_request
  from public.travel_group_join_requests
  where id = target_request_id
  for update;
  if not found then raise exception 'Join request not found'; end if;

  select * into target_group
  from public.travel_groups
  where id = join_request.group_id
  for update;
  if target_group.creator_id <> auth.uid() then
    raise exception 'Only the group creator can respond to this request';
  end if;
  if join_request.status <> 'pending' then
    raise exception 'This join request has already been answered';
  end if;

  if accept_request then
    if join_request.destination_distance_km is null
        or join_request.destination_distance_km > 10.0 then
      raise exception 'Traveller must be within 10 km of the destination';
    end if;
    if target_group.status <> 'waiting'
        or target_group.trip_phase not in ('recruiting', 'gathering') then
      raise exception 'The group is no longer accepting travellers';
    end if;
    select count(*)::integer into current_member_count
    from public.travel_group_members where group_id = join_request.group_id;
    if current_member_count >= target_group.max_members then
      raise exception 'The group is already full';
    end if;

    insert into public.travel_group_members (
      group_id, user_id, role, display_name
    ) values (
      join_request.group_id, join_request.user_id, 'member',
      join_request.traveller_name
    ) on conflict (group_id, user_id) do nothing;

    select id into target_session_id
    from public.travel_group_trip_sessions
    where group_id = join_request.group_id and status in ('active', 'paused')
      and phase = 'gathering'
    limit 1;
    if target_session_id is not null then
      insert into public.travel_group_trip_participants (
        session_id, user_id, display_name, role, sharing_enabled
      ) values (
        target_session_id, join_request.user_id,
        join_request.traveller_name, 'member', true
      ) on conflict (session_id, user_id) do update
        set display_name = excluded.display_name,
            sharing_enabled = true,
            last_seen_at = now();
    end if;
  end if;

  update public.travel_group_join_requests
  set status = case when accept_request then 'accepted' else 'declined' end,
      responded_by = auth.uid(), responded_at = now()
  where id = target_request_id;
end;
$$;

revoke all on function public.join_open_travel_group(
  uuid, text, double precision, double precision
) from public;
revoke execute on function public.join_open_travel_group(
  uuid, text, double precision, double precision
) from anon;
grant execute on function public.join_open_travel_group(
  uuid, text, double precision, double precision
) to authenticated;

revoke all on function public.travel_group_distance_km(
  double precision, double precision, double precision, double precision
) from public, anon;
grant execute on function public.travel_group_distance_km(
  double precision, double precision, double precision, double precision
) to authenticated;
revoke all on function public.validate_travel_group_join_proximity()
  from public, anon, authenticated;
