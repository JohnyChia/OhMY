-- Prototype-safe live-trip-only schema.
--
-- Do not run this file as well as SUPABASE_TRAVEL_GROUP_SETUP.sql. The unified
-- file includes these live tables plus the collaborative planning tables and
-- is the recommended migration for the current team database.
--
-- Keep this smaller file only if another team already owns travel_groups,
-- travel_group_members, suggestions and itinerary stops.

create extension if not exists pgcrypto;

create table if not exists public.travel_group_trip_sessions (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null,
  status text not null default 'active'
    check (status in ('active', 'paused', 'completed', 'cancelled')),
  started_by uuid not null references auth.users(id) on delete cascade,
  current_stop_id text,
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
  session_id uuid not null references public.travel_group_trip_sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null,
  avatar_url text,
  role text not null default 'member' check (role in ('creator', 'member')),
  sharing_enabled boolean not null default true,
  joined_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (session_id, user_id)
);

-- One row per member, overwritten as the member moves. This intentionally
-- avoids permanent location history for the prototype.
create table if not exists public.travel_group_live_locations (
  session_id uuid not null references public.travel_group_trip_sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
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

create or replace function public.touch_travel_group_trip_row()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists touch_travel_group_trip_session
  on public.travel_group_trip_sessions;
create trigger touch_travel_group_trip_session
before update on public.travel_group_trip_sessions
for each row execute function public.touch_travel_group_trip_row();

create or replace function public.is_travel_group_trip_owner(target_session_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.travel_group_trip_sessions session
    where session.id = target_session_id
      and session.started_by = auth.uid()
  );
$$;

create or replace function public.is_travel_group_trip_participant(target_session_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.travel_group_trip_participants participant
    where participant.session_id = target_session_id
      and participant.user_id = auth.uid()
  );
$$;

revoke all on function public.is_travel_group_trip_owner(uuid) from public;
revoke all on function public.is_travel_group_trip_participant(uuid) from public;
grant execute on function public.is_travel_group_trip_owner(uuid) to authenticated;
grant execute on function public.is_travel_group_trip_participant(uuid) to authenticated;

alter table public.travel_group_trip_sessions enable row level security;
alter table public.travel_group_trip_participants enable row level security;
alter table public.travel_group_live_locations enable row level security;

drop policy if exists "trip members read sessions" on public.travel_group_trip_sessions;
create policy "trip members read sessions"
on public.travel_group_trip_sessions for select
to authenticated
using (
  started_by = auth.uid()
  or public.is_travel_group_trip_participant(id)
);

drop policy if exists "creator starts trip session" on public.travel_group_trip_sessions;
create policy "creator starts trip session"
on public.travel_group_trip_sessions for insert
to authenticated
with check (started_by = auth.uid());

drop policy if exists "creator updates trip session" on public.travel_group_trip_sessions;
create policy "creator updates trip session"
on public.travel_group_trip_sessions for update
to authenticated
using (started_by = auth.uid())
with check (started_by = auth.uid());

drop policy if exists "creator deletes trip session" on public.travel_group_trip_sessions;
create policy "creator deletes trip session"
on public.travel_group_trip_sessions for delete
to authenticated
using (started_by = auth.uid());

drop policy if exists "trip members read participants" on public.travel_group_trip_participants;
create policy "trip members read participants"
on public.travel_group_trip_participants for select
to authenticated
using (
  public.is_travel_group_trip_owner(session_id)
  or public.is_travel_group_trip_participant(session_id)
);

drop policy if exists "creator seeds trip participants" on public.travel_group_trip_participants;
create policy "creator seeds trip participants"
on public.travel_group_trip_participants for insert
to authenticated
with check (
  user_id = auth.uid()
  or public.is_travel_group_trip_owner(session_id)
);

drop policy if exists "member or creator updates participant" on public.travel_group_trip_participants;
create policy "member or creator updates participant"
on public.travel_group_trip_participants for update
to authenticated
using (user_id = auth.uid() or public.is_travel_group_trip_owner(session_id))
with check (user_id = auth.uid() or public.is_travel_group_trip_owner(session_id));

drop policy if exists "member or creator removes participant" on public.travel_group_trip_participants;
create policy "member or creator removes participant"
on public.travel_group_trip_participants for delete
to authenticated
using (user_id = auth.uid() or public.is_travel_group_trip_owner(session_id));

drop policy if exists "trip members read live locations" on public.travel_group_live_locations;
create policy "trip members read live locations"
on public.travel_group_live_locations for select
to authenticated
using (public.is_travel_group_trip_participant(session_id));

drop policy if exists "member publishes own live location" on public.travel_group_live_locations;
create policy "member publishes own live location"
on public.travel_group_live_locations for insert
to authenticated
with check (
  user_id = auth.uid()
  and public.is_travel_group_trip_participant(session_id)
);

drop policy if exists "member updates own live location" on public.travel_group_live_locations;
create policy "member updates own live location"
on public.travel_group_live_locations for update
to authenticated
using (
  user_id = auth.uid()
  and public.is_travel_group_trip_participant(session_id)
)
with check (
  user_id = auth.uid()
  and public.is_travel_group_trip_participant(session_id)
);

drop policy if exists "member removes own live location" on public.travel_group_live_locations;
create policy "member removes own live location"
on public.travel_group_live_locations for delete
to authenticated
using (user_id = auth.uid() or public.is_travel_group_trip_owner(session_id));

alter table public.travel_group_trip_sessions replica identity full;
alter table public.travel_group_trip_participants replica identity full;
alter table public.travel_group_live_locations replica identity full;

do $$
begin
  alter publication supabase_realtime add table public.travel_group_trip_sessions;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.travel_group_trip_participants;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.travel_group_live_locations;
exception when duplicate_object then null;
end $$;
