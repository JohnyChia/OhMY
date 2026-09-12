-- Keep Travel Group membership exclusive for creators, improve meetup
-- diagnostics, and allow completed group history to be shared to Community.

create or replace function public.enforce_creator_group_exclusivity()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.travel_groups owned
    where owned.creator_id = new.user_id
      and owned.id <> new.group_id
      and owned.status in ('waiting', 'active')
  ) then
    raise exception 'End your current Travel Group before joining another one';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_creator_group_exclusivity
  on public.travel_group_members;
create trigger enforce_creator_group_exclusivity
before insert or update of group_id, user_id
on public.travel_group_members
for each row execute function public.enforce_creator_group_exclusivity();

create or replace function public.prevent_member_from_creating_group()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.travel_group_members member
    join public.travel_groups joined on joined.id = member.group_id
    where member.user_id = new.creator_id
      and joined.status in ('waiting', 'active')
  ) then
    raise exception 'Leave or finish your current Travel Group before creating another one';
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_member_from_creating_group
  on public.travel_groups;
create trigger prevent_member_from_creating_group
before insert on public.travel_groups
for each row execute function public.prevent_member_from_creating_group();

create or replace function public.community_validation_context_v5(
  p_user_id uuid,
  p_history_entry_id uuid default null,
  p_post_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_history_id uuid;
  selected_trip_session_id uuid;
  selected_post_id uuid;
  post_owner uuid;
  post_is_seed boolean;
  destination text;
  history_type text;
  legacy_context jsonb;
begin
  if p_user_id is null or num_nonnulls(p_history_entry_id, p_post_id) <> 1 then
    return jsonb_build_object('eligible', false, 'reason', 'Choose one Travel History entry or post.');
  end if;

  if p_post_id is not null then
    select p.history_entry_id, p.trip_session_id, p.author_id, p.is_seed
      into selected_history_id, selected_trip_session_id, post_owner, post_is_seed
    from public.community_posts p where p.id = p_post_id;
    if not found then
      return jsonb_build_object('eligible', false, 'reason', 'Post not found.');
    end if;
    if post_is_seed or post_owner is distinct from p_user_id then
      return jsonb_build_object('eligible', false, 'reason', 'Only the author can edit this post.');
    end if;
    if selected_history_id is null then
      if selected_trip_session_id is null then
        return jsonb_build_object('eligible', false, 'reason', 'This older post is not linked to Travel History.');
      end if;
      legacy_context := public.community_validation_context_v4(p_user_id, null, p_post_id);
      return legacy_context || jsonb_build_object('history_entry_id', null);
    end if;
    selected_post_id := p_post_id;
  else
    selected_history_id := p_history_entry_id;
    select p.id into selected_post_id
    from public.community_posts p where p.history_entry_id = selected_history_id;
    if selected_post_id is not null then
      return jsonb_build_object('eligible', false, 'reason', 'This Travel History entry already has a post.');
    end if;
  end if;

  select h.destination, h.source_type into destination, history_type
  from public.travel_history_entries h
  where h.id = selected_history_id and h.user_id = p_user_id;
  if not found then
    return jsonb_build_object('eligible', false, 'reason', 'Travel History entry was not found for this account.');
  end if;
  if history_type not in ('solo', 'group') then
    return jsonb_build_object('eligible', false, 'reason', 'This Travel History entry cannot be shared.');
  end if;
  if nullif(trim(destination), '') is null then
    return jsonb_build_object('eligible', false, 'reason', 'This Travel History entry has no destination.');
  end if;

  return jsonb_build_object(
    'eligible', true,
    'reason', 'Travel History entry is eligible.',
    'destination', trim(destination),
    'attraction', trim(destination),
    'history_entry_id', selected_history_id,
    'existing_post_id', selected_post_id
  );
end;
$$;

create or replace function public.eligible_community_history_entries_v5()
returns table (
  id uuid,
  title text,
  location_name text,
  attraction_name text,
  ended_at timestamptz,
  community_post_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  select h.id, h.title, h.destination, h.destination, h.ended_at, p.id
  from public.travel_history_entries h
  left join public.community_posts p
    on p.history_entry_id = h.id and p.author_id = auth.uid()
  where auth.uid() is not null
    and h.user_id = auth.uid()
    and h.source_type in ('solo', 'group')
  order by h.ended_at desc;
$$;

revoke all on function public.eligible_community_history_entries_v5()
  from public, anon;
grant execute on function public.eligible_community_history_entries_v5()
  to authenticated;

create or replace function public.begin_travel_group_journey(target_group_id uuid)
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
  blocked_name text;
  blocked_reason text;
begin
  if not public.is_travel_group_creator(target_group_id) then
    raise exception 'Only the creator can begin this journey';
  end if;
  select count(*)::integer into member_total
  from public.travel_group_members where group_id = target_group_id;
  if member_total < 2 then
    raise exception 'At least two real travellers must join before the Travel Group can start';
  end if;
  select id into target_session_id
  from public.travel_group_trip_sessions
  where group_id = target_group_id and status in ('active', 'paused') limit 1;
  if target_session_id is null then
    raise exception 'Confirm the group before beginning the journey';
  end if;
  select count(*)::integer into participant_total
  from public.travel_group_trip_participants where session_id = target_session_id;
  if participant_total < 2 or participant_total <> member_total then
    raise exception 'Refresh the lobby so every joined traveller is included before starting';
  end if;
  if not exists (
    select 1 from public.travel_groups
    where id = target_group_id and meetup_latitude is not null and meetup_longitude is not null
  ) then
    raise exception 'Set the meetup point before beginning the journey';
  end if;

  select participant.display_name,
    case
      when not participant.sharing_enabled then 'has location sharing turned off'
      when location.recorded_at is null then 'has not shared a location yet'
      when location.recorded_at < now() - interval '2 minutes' then 'has a location older than 2 minutes'
      else 'is more than 150 m from the meetup point'
    end
    into blocked_name, blocked_reason
  from public.travel_group_trip_participants participant
  left join public.travel_group_live_locations location
    on location.session_id = participant.session_id and location.user_id = participant.user_id
  cross join public.travel_groups travel_group
  where participant.session_id = target_session_id
    and travel_group.id = target_group_id
    and (
      not participant.sharing_enabled
      or location.recorded_at is null
      or location.recorded_at < now() - interval '2 minutes'
      or 6371000 * 2 * asin(sqrt(
        power(sin(radians(location.latitude - travel_group.meetup_latitude) / 2), 2)
        + cos(radians(travel_group.meetup_latitude)) * cos(radians(location.latitude))
        * power(sin(radians(location.longitude - travel_group.meetup_longitude) / 2), 2)
      )) > 150
    )
  order by participant.role = 'creator' desc
  limit 1;
  if blocked_name is not null then
    raise exception '% %', blocked_name, blocked_reason;
  end if;

  select id into first_stop_id
  from public.travel_group_itinerary_stops
  where group_id = target_group_id and status <> 'completed'
  order by position limit 1;
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

revoke all on function public.begin_travel_group_journey(uuid) from public, anon;
grant execute on function public.begin_travel_group_journey(uuid) to authenticated;
