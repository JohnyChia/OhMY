alter table public.travel_group_itinerary_stops
  add column if not exists travel_distance_from_previous_km numeric(8, 2)
  not null default 0
  check (travel_distance_from_previous_km >= 0);

create or replace function public.prevent_duplicate_travel_group_place()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  normalized_name text := regexp_replace(lower(trim(new.place_name)), '\s+', ' ', 'g');
begin
  perform 1 from public.travel_groups where id = new.group_id for update;

  if exists (
    select 1
    from public.travel_groups as travel_group
    where travel_group.id = new.group_id
      and (
        (new.external_place_id is not null
          and travel_group.destination_place_id = new.external_place_id)
        or regexp_replace(lower(trim(travel_group.destination)), '\s+', ' ', 'g') = normalized_name
      )
  ) or exists (
    select 1
    from public.travel_group_suggestions as suggestion
    where suggestion.group_id = new.group_id
      and suggestion.id <> new.id
      and (
        (new.external_place_id is not null
          and suggestion.external_place_id = new.external_place_id)
        or regexp_replace(lower(trim(suggestion.place_name)), '\s+', ' ', 'g') = normalized_name
      )
  ) then
    raise exception 'This place is already part of the group plan'
      using errcode = '23505';
  end if;

  return new;
end;
$$;

drop trigger if exists prevent_duplicate_travel_group_place
  on public.travel_group_suggestions;
create trigger prevent_duplicate_travel_group_place
before insert or update of external_place_id, place_name
on public.travel_group_suggestions
for each row execute function public.prevent_duplicate_travel_group_place();

create or replace function public.join_open_travel_group(
  target_group_id uuid,
  member_display_name text
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
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;

  select * into target_group
  from public.travel_groups
  where id = target_group_id
  for update;

  if not found then raise exception 'Travel group not found'; end if;
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
      session_id, user_id, display_name, role
    ) values (
      target_session_id, auth.uid(),
      coalesce(nullif(trim(member_display_name), ''), 'Traveller'), 'member'
    ) on conflict (session_id, user_id) do update
      set display_name = excluded.display_name, last_seen_at = now();
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
        session_id, user_id, display_name, role
      ) values (
        target_session_id, join_request.user_id,
        join_request.traveller_name, 'member'
      ) on conflict (session_id, user_id) do update
        set display_name = excluded.display_name, last_seen_at = now();
    end if;
  end if;

  update public.travel_group_join_requests
  set status = case when accept_request then 'accepted' else 'declined' end,
      responded_by = auth.uid(), responded_at = now()
  where id = target_request_id;
end;
$$;

create or replace function public.remove_travel_group_suggestion(
  target_suggestion_id uuid
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  selected public.travel_group_suggestions%rowtype;
begin
  select * into selected from public.travel_group_suggestions
  where id = target_suggestion_id;
  if not found then return; end if;
  if selected.suggested_by <> auth.uid()
      and not public.can_edit_travel_group(selected.group_id) then
    raise exception 'You cannot remove this suggestion';
  end if;
  if exists (
    select 1 from public.travel_group_itinerary_stops
    where suggestion_id = selected.id and status = 'current'
  ) then
    raise exception 'The active destination cannot be removed';
  end if;
  if selected.status = 'confirmed'
      and not public.can_edit_travel_group(selected.group_id) then
    raise exception 'Only the creator can remove a confirmed stop';
  end if;

  delete from public.travel_group_itinerary_stops
  where suggestion_id = selected.id;
  delete from public.travel_group_suggestions where id = selected.id;

  with ordered as (
    select id, row_number() over (order by position) - 1 as new_position
    from public.travel_group_itinerary_stops
    where group_id = selected.group_id
  )
  update public.travel_group_itinerary_stops as stop
  set position = ordered.new_position + 100000
  from ordered where stop.id = ordered.id;
  update public.travel_group_itinerary_stops
  set position = position - 100000
  where group_id = selected.group_id and position >= 100000;
end;
$$;

create or replace function public.remove_travel_group_itinerary_stop(
  target_group_id uuid,
  target_stop_id uuid
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  linked_suggestion_id uuid;
begin
  if not public.is_travel_group_creator(target_group_id) then
    raise exception 'Only the creator can remove an itinerary stop';
  end if;
  select suggestion_id into linked_suggestion_id
  from public.travel_group_itinerary_stops
  where id = target_stop_id and group_id = target_group_id
    and status <> 'current';
  if not found then raise exception 'This stop cannot be removed'; end if;

  delete from public.travel_group_itinerary_stops where id = target_stop_id;
  if linked_suggestion_id is not null then
    update public.travel_group_suggestions set status = 'proposed'
    where id = linked_suggestion_id;
  end if;

  with ordered as (
    select id, row_number() over (order by position) - 1 as new_position
    from public.travel_group_itinerary_stops where group_id = target_group_id
  )
  update public.travel_group_itinerary_stops as stop
  set position = ordered.new_position + 100000
  from ordered where stop.id = ordered.id;
  update public.travel_group_itinerary_stops
  set position = position - 100000
  where group_id = target_group_id and position >= 100000;
end;
$$;

create or replace function public.reorder_travel_group_itinerary(
  target_group_id uuid,
  ordered_stop_ids uuid[],
  leg_minutes integer[],
  leg_distances_km numeric[]
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not public.is_travel_group_creator(target_group_id) then
    raise exception 'Only the creator can reorder the itinerary';
  end if;
  if not exists (
    select 1 from public.travel_groups
    where id = target_group_id and status = 'waiting'
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
$$;

create or replace function public.require_two_members_to_begin_group_journey()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.trip_phase = 'navigating' and old.trip_phase <> 'navigating'
      and (select count(*) from public.travel_group_members
           where group_id = new.id) < 2 then
    raise exception 'At least two travellers must join before starting';
  end if;
  return new;
end;
$$;

drop trigger if exists require_two_members_to_begin_group_journey
  on public.travel_groups;
create trigger require_two_members_to_begin_group_journey
before update of trip_phase on public.travel_groups
for each row execute function public.require_two_members_to_begin_group_journey();

revoke all on function public.join_open_travel_group(uuid, text) from public;
revoke execute on function public.join_open_travel_group(uuid, text) from anon;
grant execute on function public.join_open_travel_group(uuid, text) to authenticated;
revoke all on function public.respond_travel_group_join_request(uuid, boolean) from public;
revoke execute on function public.respond_travel_group_join_request(uuid, boolean) from anon;
grant execute on function public.respond_travel_group_join_request(uuid, boolean) to authenticated;
revoke all on function public.remove_travel_group_suggestion(uuid) from public, anon;
grant execute on function public.remove_travel_group_suggestion(uuid) to authenticated;
revoke all on function public.remove_travel_group_itinerary_stop(uuid, uuid) from public, anon;
grant execute on function public.remove_travel_group_itinerary_stop(uuid, uuid) to authenticated;
revoke all on function public.reorder_travel_group_itinerary(uuid, uuid[], integer[], numeric[]) from public, anon;
grant execute on function public.reorder_travel_group_itinerary(uuid, uuid[], integer[], numeric[]) to authenticated;
revoke all on function public.prevent_duplicate_travel_group_place() from public, anon, authenticated;
revoke all on function public.require_two_members_to_begin_group_journey() from public, anon, authenticated;
