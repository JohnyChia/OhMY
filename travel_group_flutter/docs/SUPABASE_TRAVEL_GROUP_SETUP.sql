-- Travel Group planning + live trip schema.
--
-- Safe alongside the team's existing messages, sessions, trip_states,
-- itineraries, traveler_profiles, places, tags, place_tags and
-- user_preferences tables. This migration does not alter those tables.
-- New user references use the canonical Supabase auth.users UUID.
-- Suggested/itinerary locations may reuse public.places.id.

create extension if not exists pgcrypto;

create table if not exists public.travel_groups (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 120),
  destination text not null check (length(trim(destination)) between 1 and 160),
  description text not null default '',
  meetup_place_id bigint references public.places(id) on delete set null,
  meetup_name text not null default '',
  meetup_note text not null default '',
  join_mode text not null default 'open'
    check (join_mode in ('open', 'request')),
  status text not null default 'waiting'
    check (status in ('waiting', 'active', 'completed', 'cancelled')),
  max_members integer not null default 8 check (max_members between 2 and 50),
  tags text[] not null default '{}',
  trip_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.travel_group_members (
  group_id uuid not null references public.travel_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member'
    check (role in ('creator', 'editor', 'member')),
  display_name text,
  avatar_url text,
  joined_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table if not exists public.travel_group_join_requests (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.travel_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  message text not null default '',
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  responded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  responded_at timestamptz
);

create unique index if not exists one_pending_join_request_per_group_user
  on public.travel_group_join_requests(group_id, user_id)
  where status = 'pending';

create table if not exists public.travel_group_suggestions (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.travel_groups(id) on delete cascade,
  suggested_by uuid not null references auth.users(id) on delete cascade,
  place_id bigint references public.places(id) on delete set null,
  place_name text not null check (length(trim(place_name)) > 0),
  source text not null default 'member',
  category text,
  distance_km numeric(8, 2) check (distance_km is null or distance_km >= 0),
  crowd_level text,
  duration_minutes integer not null default 60 check (duration_minutes > 0),
  tags text[] not null default '{}',
  status text not null default 'proposed'
    check (status in ('proposed', 'confirmed', 'rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, group_id)
);

create unique index if not exists one_active_suggestion_per_group_place
  on public.travel_group_suggestions(group_id, place_id)
  where place_id is not null and status in ('proposed', 'confirmed');

create index if not exists travel_group_suggestions_rank_source
  on public.travel_group_suggestions(group_id, status, created_at);

create table if not exists public.travel_group_suggestion_votes (
  suggestion_id uuid not null
    references public.travel_group_suggestions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  vote smallint not null check (vote in (-1, 1)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (suggestion_id, user_id)
);

-- Only configured cards become rows. Empty 08:30/10:00/12:30 slots remain a
-- client template until a Visit, Eat at or Rest at card is dropped into them.
create table if not exists public.travel_group_itinerary_stops (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.travel_groups(id) on delete cascade,
  suggestion_id uuid,
  place_id bigint references public.places(id) on delete set null,
  place_name text,
  stop_type text not null check (stop_type in ('visit', 'eat', 'rest')),
  position integer not null check (position >= 0),
  scheduled_at timestamptz,
  duration_minutes integer not null default 60 check (duration_minutes > 0),
  travel_minutes_from_previous integer not null default 0
    check (travel_minutes_from_previous >= 0),
  status text not null default 'upcoming'
    check (status in ('upcoming', 'current', 'completed', 'skipped')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (group_id, position),
  unique (id, group_id),
  foreign key (suggestion_id, group_id)
    references public.travel_group_suggestions(id, group_id) on delete restrict
);

create index if not exists travel_group_itinerary_order
  on public.travel_group_itinerary_stops(group_id, position);

create table if not exists public.travel_group_trip_sessions (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.travel_groups(id) on delete cascade,
  status text not null default 'active'
    check (status in ('active', 'paused', 'completed', 'cancelled')),
  started_by uuid not null references auth.users(id) on delete cascade,
  current_stop_id uuid
    references public.travel_group_itinerary_stops(id) on delete set null,
  current_stop_index integer not null default 0 check (current_stop_index >= 0),
  route jsonb not null default '[]'::jsonb
    check (jsonb_typeof(route) = 'array'),
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  updated_at timestamptz not null default now()
);

create unique index if not exists one_open_trip_session_per_group
  on public.travel_group_trip_sessions(group_id)
  where status in ('active', 'paused');

create table if not exists public.travel_group_trip_participants (
  session_id uuid not null
    references public.travel_group_trip_sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null,
  avatar_url text,
  role text not null default 'member'
    check (role in ('creator', 'editor', 'member')),
  sharing_enabled boolean not null default true,
  joined_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (session_id, user_id)
);

-- One overwritten row per participant; no permanent location history.
create table if not exists public.travel_group_live_locations (
  session_id uuid not null,
  user_id uuid not null,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  accuracy_m real check (accuracy_m is null or accuracy_m >= 0),
  heading_deg real check (heading_deg is null or heading_deg between 0 and 360),
  speed_mps real check (speed_mps is null or speed_mps >= 0),
  recorded_at timestamptz not null default now(),
  primary key (session_id, user_id),
  foreign key (session_id, user_id)
    references public.travel_group_trip_participants(session_id, user_id)
    on delete cascade
);

create index if not exists live_locations_by_session
  on public.travel_group_live_locations(session_id, recorded_at desc);

create or replace function public.set_travel_group_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_travel_groups_updated_at on public.travel_groups;
create trigger set_travel_groups_updated_at
before update on public.travel_groups
for each row execute function public.set_travel_group_updated_at();

drop trigger if exists set_travel_group_suggestions_updated_at
  on public.travel_group_suggestions;
create trigger set_travel_group_suggestions_updated_at
before update on public.travel_group_suggestions
for each row execute function public.set_travel_group_updated_at();

drop trigger if exists set_travel_group_votes_updated_at
  on public.travel_group_suggestion_votes;
create trigger set_travel_group_votes_updated_at
before update on public.travel_group_suggestion_votes
for each row execute function public.set_travel_group_updated_at();

drop trigger if exists set_travel_group_stops_updated_at
  on public.travel_group_itinerary_stops;
create trigger set_travel_group_stops_updated_at
before update on public.travel_group_itinerary_stops
for each row execute function public.set_travel_group_updated_at();

drop trigger if exists set_travel_group_sessions_updated_at
  on public.travel_group_trip_sessions;
create trigger set_travel_group_sessions_updated_at
before update on public.travel_group_trip_sessions
for each row execute function public.set_travel_group_updated_at();

create or replace function public.is_travel_group_member(target_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.travel_group_members member
    where member.group_id = target_group_id
      and member.user_id = auth.uid()
  );
$$;

create or replace function public.can_edit_travel_group(target_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.travel_group_members member
    where member.group_id = target_group_id
      and member.user_id = auth.uid()
      and member.role in ('creator', 'editor')
  );
$$;

create or replace function public.is_travel_group_creator(target_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.travel_groups travel_group
    where travel_group.id = target_group_id
      and travel_group.creator_id = auth.uid()
  );
$$;

create or replace function public.is_travel_group_trip_owner(target_session_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.travel_group_trip_sessions session
    where session.id = target_session_id
      and session.started_by = auth.uid()
  );
$$;

create or replace function public.is_travel_group_trip_participant(
  target_session_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.travel_group_trip_participants participant
    where participant.session_id = target_session_id
      and participant.user_id = auth.uid()
  );
$$;

revoke all on function public.is_travel_group_member(uuid) from public;
revoke all on function public.can_edit_travel_group(uuid) from public;
revoke all on function public.is_travel_group_creator(uuid) from public;
revoke all on function public.is_travel_group_trip_owner(uuid) from public;
revoke all on function public.is_travel_group_trip_participant(uuid) from public;
grant execute on function public.is_travel_group_member(uuid) to authenticated;
grant execute on function public.can_edit_travel_group(uuid) to authenticated;
grant execute on function public.is_travel_group_creator(uuid) to authenticated;
grant execute on function public.is_travel_group_trip_owner(uuid) to authenticated;
grant execute on function public.is_travel_group_trip_participant(uuid)
  to authenticated;

create or replace function public.seed_travel_group_creator()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.travel_group_members(group_id, user_id, role)
  values (new.id, new.creator_id, 'creator')
  on conflict (group_id, user_id) do update set role = 'creator';
  return new;
end;
$$;

drop trigger if exists seed_travel_group_creator_member on public.travel_groups;
create trigger seed_travel_group_creator_member
after insert on public.travel_groups
for each row execute function public.seed_travel_group_creator();

create or replace function public.protect_travel_group_member_role()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role is distinct from old.role
     and not public.is_travel_group_creator(old.group_id) then
    raise exception 'Only the group creator can change member roles';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_travel_group_member_role_change
  on public.travel_group_members;
create trigger protect_travel_group_member_role_change
before update on public.travel_group_members
for each row execute function public.protect_travel_group_member_role();

alter table public.travel_groups enable row level security;
alter table public.travel_group_members enable row level security;
alter table public.travel_group_join_requests enable row level security;
alter table public.travel_group_suggestions enable row level security;
alter table public.travel_group_suggestion_votes enable row level security;
alter table public.travel_group_itinerary_stops enable row level security;
alter table public.travel_group_trip_sessions enable row level security;
alter table public.travel_group_trip_participants enable row level security;
alter table public.travel_group_live_locations enable row level security;

drop policy if exists "authenticated users discover travel groups"
  on public.travel_groups;
create policy "authenticated users discover travel groups"
on public.travel_groups for select to authenticated using (true);

drop policy if exists "users create their own travel groups"
  on public.travel_groups;
create policy "users create their own travel groups"
on public.travel_groups for insert to authenticated
with check (creator_id = auth.uid());

drop policy if exists "creator updates travel group" on public.travel_groups;
create policy "creator updates travel group"
on public.travel_groups for update to authenticated
using (creator_id = auth.uid()) with check (creator_id = auth.uid());

drop policy if exists "creator deletes travel group" on public.travel_groups;
create policy "creator deletes travel group"
on public.travel_groups for delete to authenticated
using (creator_id = auth.uid());

drop policy if exists "members read group membership"
  on public.travel_group_members;
create policy "members read group membership"
on public.travel_group_members for select to authenticated
using (public.is_travel_group_member(group_id));

drop policy if exists "member joins an open waiting group"
  on public.travel_group_members;
create policy "member joins an open waiting group"
on public.travel_group_members for insert to authenticated
with check (
  user_id = auth.uid() and role = 'member' and exists (
    select 1 from public.travel_groups travel_group
    where travel_group.id = group_id
      and travel_group.join_mode = 'open'
      and travel_group.status = 'waiting'
  )
);

drop policy if exists "creator updates group members"
  on public.travel_group_members;
create policy "creator updates group members"
on public.travel_group_members for update to authenticated
using (public.is_travel_group_creator(group_id))
with check (public.is_travel_group_creator(group_id));

drop policy if exists "self or creator leaves group"
  on public.travel_group_members;
create policy "self or creator leaves group"
on public.travel_group_members for delete to authenticated
using (user_id = auth.uid() or public.is_travel_group_creator(group_id));

drop policy if exists "requester or creator reads join request"
  on public.travel_group_join_requests;
create policy "requester or creator reads join request"
on public.travel_group_join_requests for select to authenticated
using (user_id = auth.uid() or public.is_travel_group_creator(group_id));

drop policy if exists "user creates own join request"
  on public.travel_group_join_requests;
create policy "user creates own join request"
on public.travel_group_join_requests for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists "creator responds to join request"
  on public.travel_group_join_requests;
create policy "creator responds to join request"
on public.travel_group_join_requests for update to authenticated
using (public.is_travel_group_creator(group_id))
with check (public.is_travel_group_creator(group_id));

drop policy if exists "user cancels own join request"
  on public.travel_group_join_requests;
create policy "user cancels own join request"
on public.travel_group_join_requests for delete to authenticated
using (user_id = auth.uid() and status = 'pending');

drop policy if exists "members read suggestions"
  on public.travel_group_suggestions;
create policy "members read suggestions"
on public.travel_group_suggestions for select to authenticated
using (public.is_travel_group_member(group_id));

drop policy if exists "members add suggestions"
  on public.travel_group_suggestions;
create policy "members add suggestions"
on public.travel_group_suggestions for insert to authenticated
with check (
  suggested_by = auth.uid() and public.is_travel_group_member(group_id)
);

drop policy if exists "editors confirm suggestions"
  on public.travel_group_suggestions;
create policy "editors confirm suggestions"
on public.travel_group_suggestions for update to authenticated
using (public.can_edit_travel_group(group_id))
with check (public.can_edit_travel_group(group_id));

drop policy if exists "author or editor removes suggestion"
  on public.travel_group_suggestions;
create policy "author or editor removes suggestion"
on public.travel_group_suggestions for delete to authenticated
using (
  suggested_by = auth.uid() or public.can_edit_travel_group(group_id)
);

drop policy if exists "members read suggestion votes"
  on public.travel_group_suggestion_votes;
create policy "members read suggestion votes"
on public.travel_group_suggestion_votes for select to authenticated
using (exists (
  select 1 from public.travel_group_suggestions suggestion
  where suggestion.id = suggestion_id
    and public.is_travel_group_member(suggestion.group_id)
));

drop policy if exists "members cast own suggestion vote"
  on public.travel_group_suggestion_votes;
create policy "members cast own suggestion vote"
on public.travel_group_suggestion_votes for insert to authenticated
with check (
  user_id = auth.uid() and exists (
    select 1 from public.travel_group_suggestions suggestion
    where suggestion.id = suggestion_id
      and public.is_travel_group_member(suggestion.group_id)
  )
);

drop policy if exists "members update own suggestion vote"
  on public.travel_group_suggestion_votes;
create policy "members update own suggestion vote"
on public.travel_group_suggestion_votes for update to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "members remove own suggestion vote"
  on public.travel_group_suggestion_votes;
create policy "members remove own suggestion vote"
on public.travel_group_suggestion_votes for delete to authenticated
using (user_id = auth.uid());

drop policy if exists "members read itinerary stops"
  on public.travel_group_itinerary_stops;
create policy "members read itinerary stops"
on public.travel_group_itinerary_stops for select to authenticated
using (public.is_travel_group_member(group_id));

drop policy if exists "editors add itinerary stops"
  on public.travel_group_itinerary_stops;
create policy "editors add itinerary stops"
on public.travel_group_itinerary_stops for insert to authenticated
with check (
  created_by = auth.uid() and public.can_edit_travel_group(group_id)
);

drop policy if exists "editors update itinerary stops"
  on public.travel_group_itinerary_stops;
create policy "editors update itinerary stops"
on public.travel_group_itinerary_stops for update to authenticated
using (public.can_edit_travel_group(group_id))
with check (public.can_edit_travel_group(group_id));

drop policy if exists "editors remove itinerary stops"
  on public.travel_group_itinerary_stops;
create policy "editors remove itinerary stops"
on public.travel_group_itinerary_stops for delete to authenticated
using (public.can_edit_travel_group(group_id));

drop policy if exists "trip members read sessions"
  on public.travel_group_trip_sessions;
create policy "trip members read sessions"
on public.travel_group_trip_sessions for select to authenticated
using (
  public.is_travel_group_member(group_id)
  or public.is_travel_group_trip_participant(id)
);

drop policy if exists "editors start trip session"
  on public.travel_group_trip_sessions;
create policy "editors start trip session"
on public.travel_group_trip_sessions for insert to authenticated
with check (
  started_by = auth.uid() and public.can_edit_travel_group(group_id)
);

drop policy if exists "editors update trip session"
  on public.travel_group_trip_sessions;
create policy "editors update trip session"
on public.travel_group_trip_sessions for update to authenticated
using (public.can_edit_travel_group(group_id))
with check (public.can_edit_travel_group(group_id));

drop policy if exists "creator deletes trip session"
  on public.travel_group_trip_sessions;
create policy "creator deletes trip session"
on public.travel_group_trip_sessions for delete to authenticated
using (public.is_travel_group_creator(group_id));

drop policy if exists "trip members read participants"
  on public.travel_group_trip_participants;
create policy "trip members read participants"
on public.travel_group_trip_participants for select to authenticated
using (public.is_travel_group_trip_participant(session_id)
       or public.is_travel_group_trip_owner(session_id));

drop policy if exists "editor seeds trip participants"
  on public.travel_group_trip_participants;
create policy "editor seeds trip participants"
on public.travel_group_trip_participants for insert to authenticated
with check (user_id = auth.uid() or public.is_travel_group_trip_owner(session_id));

drop policy if exists "member or owner updates participant"
  on public.travel_group_trip_participants;
create policy "member or owner updates participant"
on public.travel_group_trip_participants for update to authenticated
using (user_id = auth.uid() or public.is_travel_group_trip_owner(session_id))
with check (user_id = auth.uid() or public.is_travel_group_trip_owner(session_id));

drop policy if exists "member or owner removes participant"
  on public.travel_group_trip_participants;
create policy "member or owner removes participant"
on public.travel_group_trip_participants for delete to authenticated
using (user_id = auth.uid() or public.is_travel_group_trip_owner(session_id));

drop policy if exists "trip members read live locations"
  on public.travel_group_live_locations;
create policy "trip members read live locations"
on public.travel_group_live_locations for select to authenticated
using (public.is_travel_group_trip_participant(session_id));

drop policy if exists "member publishes own live location"
  on public.travel_group_live_locations;
create policy "member publishes own live location"
on public.travel_group_live_locations for insert to authenticated
with check (
  user_id = auth.uid()
  and public.is_travel_group_trip_participant(session_id)
);

drop policy if exists "member updates own live location"
  on public.travel_group_live_locations;
create policy "member updates own live location"
on public.travel_group_live_locations for update to authenticated
using (
  user_id = auth.uid()
  and public.is_travel_group_trip_participant(session_id)
)
with check (
  user_id = auth.uid()
  and public.is_travel_group_trip_participant(session_id)
);

drop policy if exists "member removes own live location"
  on public.travel_group_live_locations;
create policy "member removes own live location"
on public.travel_group_live_locations for delete to authenticated
using (user_id = auth.uid() or public.is_travel_group_trip_owner(session_id));

grant select, insert, update, delete on table
  public.travel_groups,
  public.travel_group_members,
  public.travel_group_join_requests,
  public.travel_group_suggestions,
  public.travel_group_suggestion_votes,
  public.travel_group_itinerary_stops,
  public.travel_group_trip_sessions,
  public.travel_group_trip_participants,
  public.travel_group_live_locations
to authenticated;

alter table public.travel_groups replica identity full;
alter table public.travel_group_members replica identity full;
alter table public.travel_group_join_requests replica identity full;
alter table public.travel_group_suggestions replica identity full;
alter table public.travel_group_suggestion_votes replica identity full;
alter table public.travel_group_itinerary_stops replica identity full;
alter table public.travel_group_trip_sessions replica identity full;
alter table public.travel_group_trip_participants replica identity full;
alter table public.travel_group_live_locations replica identity full;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'travel_groups',
    'travel_group_members',
    'travel_group_join_requests',
    'travel_group_suggestions',
    'travel_group_suggestion_votes',
    'travel_group_itinerary_stops',
    'travel_group_trip_sessions',
    'travel_group_trip_participants',
    'travel_group_live_locations'
  ]
  loop
    begin
      execute format(
        'alter publication supabase_realtime add table public.%I',
        table_name
      );
    exception when duplicate_object then
      null;
    end;
  end loop;
end $$;
