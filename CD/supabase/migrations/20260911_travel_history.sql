-- Read-only travel history for completed solo and group journeys.
-- This creates a new table and does not alter teammates' trip tables.

create extension if not exists pgcrypto;

create table if not exists public.travel_history_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source_type text not null
    check (source_type in ('solo', 'group')),
  source_reference text not null,
  title text not null check (length(trim(title)) between 1 and 160),
  destination text not null check (length(trim(destination)) between 1 and 200),
  started_at timestamptz not null,
  ended_at timestamptz not null,
  distance_km numeric(10, 2) not null default 0
    check (distance_km >= 0),
  duration_minutes integer not null default 0
    check (duration_minutes >= 0),
  tags text[] not null default '{}',
  travel_mode text not null default 'Not recorded',
  itinerary jsonb not null default '[]'::jsonb
    check (jsonb_typeof(itinerary) = 'array'),
  created_at timestamptz not null default now(),
  constraint travel_history_valid_period check (ended_at >= started_at),
  constraint travel_history_unique_completion
    unique (user_id, source_type, source_reference)
);

create index if not exists travel_history_entries_user_ended_at
  on public.travel_history_entries(user_id, ended_at desc);

alter table public.travel_history_entries enable row level security;

drop policy if exists "users read own travel history"
  on public.travel_history_entries;
create policy "users read own travel history"
on public.travel_history_entries
for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "users record own completed journeys"
  on public.travel_history_entries;
create policy "users record own completed journeys"
on public.travel_history_entries
for insert
to authenticated
with check ((select auth.uid()) = user_id);

-- History is deliberately immutable from the Flutter client. No UPDATE or
-- DELETE policy is provided.
revoke all on table public.travel_history_entries from anon;
revoke all on table public.travel_history_entries from authenticated;
grant select, insert on table public.travel_history_entries to authenticated;
