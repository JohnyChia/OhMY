-- Community Discovery: allow every owned Travel History entry to be shared.
-- Both solo and group history rows use history_entry_id. Legacy posts linked
-- directly to a Travel Group trip_session_id remain supported.
-- Shared history/group tables are read only.
begin;

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
  legacy_context jsonb;
begin
  if p_user_id is null or num_nonnulls(p_history_entry_id, p_post_id) <> 1 then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'Choose one Travel History entry or post.'
    );
  end if;

  if p_post_id is not null then
    select p.history_entry_id, p.trip_session_id, p.author_id, p.is_seed
      into selected_history_id, selected_trip_session_id, post_owner, post_is_seed
    from public.community_posts p
    where p.id = p_post_id;

    if not found then
      return jsonb_build_object('eligible', false, 'reason', 'Post not found.');
    end if;
    if post_is_seed or post_owner is distinct from p_user_id then
      return jsonb_build_object(
        'eligible', false,
        'reason', 'Only the author can edit this post.'
      );
    end if;
    if selected_history_id is null then
      if selected_trip_session_id is null then
        return jsonb_build_object(
          'eligible', false,
          'reason', 'This older post is not linked to Travel History.'
        );
      end if;
      legacy_context := public.community_validation_context_v4(
        p_user_id,
        null,
        p_post_id
      );
      return legacy_context || jsonb_build_object('history_entry_id', null);
    end if;
    selected_post_id := p_post_id;
  else
    selected_history_id := p_history_entry_id;
    select p.id into selected_post_id
    from public.community_posts p
    where p.history_entry_id = selected_history_id;
    if selected_post_id is not null then
      return jsonb_build_object(
        'eligible', false,
        'reason', 'This Travel History entry already has a post.'
      );
    end if;
  end if;

  select h.destination
    into destination
  from public.travel_history_entries h
  where h.id = selected_history_id
    and h.user_id = p_user_id;

  if not found then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'Travel History entry was not found for this account.'
    );
  end if;
  if nullif(trim(destination), '') is null then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'This Travel History entry has no destination.'
    );
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

create or replace function public.validate_community_post_trip()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  trip_owner uuid;
  trip_status text;
  trip_destination text;
  trip_name text;
  is_participant boolean;
  history_owner uuid;
begin
  if new.is_seed then
    if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then
      raise exception 'Seed posts can only be managed by the service role.';
    end if;
    if new.author_id is not null
       or new.trip_session_id is not null
       or new.history_entry_id is not null then
      raise exception 'Seed posts cannot impersonate a user or trip.';
    end if;
    return new;
  end if;

  if auth.uid() is null or new.author_id is distinct from auth.uid() then
    raise exception 'Sign in as the post author.';
  end if;

  if new.history_entry_id is not null then
    if new.trip_session_id is not null then
      raise exception 'Choose either Travel History or a Trip Session.';
    end if;

    select h.user_id, h.destination
      into history_owner, trip_destination
    from public.travel_history_entries h
    where h.id = new.history_entry_id;

    if not found then raise exception 'Travel History entry not found.'; end if;
    if history_owner is distinct from auth.uid() then
      raise exception 'This Travel History entry does not belong to you.';
    end if;
    if nullif(trim(trip_destination), '') is null then
      raise exception 'This Travel History entry has no destination.';
    end if;

    new.location_name := trim(trip_destination);
    new.attraction_name := trim(trip_destination);
    return new;
  end if;

  if new.trip_session_id is null then
    raise exception 'Choose a completed trip.';
  end if;

  select s.started_by, s.status, g.destination, g.name,
         exists (
           select 1 from public.travel_group_trip_participants p
           where p.session_id = s.id and p.user_id = auth.uid()
         )
    into trip_owner, trip_status, trip_destination, trip_name, is_participant
  from public.travel_group_trip_sessions s
  join public.travel_groups g on g.id = s.group_id
  where s.id = new.trip_session_id;

  if not found then raise exception 'Trip session not found.'; end if;
  if trip_status not in ('ended', 'completed') then
    raise exception 'Finish the trip before creating a post.';
  end if;
  if trip_owner is distinct from auth.uid() and not is_participant then
    raise exception 'You were not a participant in this trip.';
  end if;

  new.location_name := trip_destination;
  new.attraction_name := trip_name;
  return new;
end;
$$;

create or replace function public.eligible_community_history_entries_v6()
returns table (
  id uuid,
  title text,
  location_name text,
  attraction_name text,
  ended_at timestamptz,
  community_post_id uuid,
  source_type text
)
language sql
stable
security definer
set search_path = public
as $$
  select h.id, h.title, h.destination, h.destination, h.ended_at, p.id,
         h.source_type
  from public.travel_history_entries h
  left join public.community_posts p
    on p.history_entry_id = h.id and p.author_id = auth.uid()
  where auth.uid() is not null
    and h.user_id = auth.uid()
  order by h.ended_at desc;
$$;

revoke all on function public.eligible_community_history_entries_v6()
  from public, anon;
grant execute on function public.eligible_community_history_entries_v6()
  to authenticated;

commit;
