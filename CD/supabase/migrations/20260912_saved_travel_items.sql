create table if not exists public.saved_travel_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source_type text not null check (source_type in ('image', 'file', 'link', 'place', 'message')),
  source_name text not null default '',
  source_url text,
  storage_path text,
  content_hash text not null,
  title text not null,
  summary text not null default '',
  location_hint text,
  google_place_id text,
  latitude double precision,
  longitude double precision,
  travel_tags text[] not null default '{}',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_used_at timestamptz
);

create unique index if not exists saved_travel_items_user_hash_key
  on public.saved_travel_items(user_id, content_hash);
create index if not exists saved_travel_items_user_created_idx
  on public.saved_travel_items(user_id, created_at desc);
create index if not exists saved_travel_items_tags_idx
  on public.saved_travel_items using gin(travel_tags);

alter table public.saved_travel_items enable row level security;

alter table public.saved_travel_items
  drop constraint if exists saved_travel_items_source_type_check;
alter table public.saved_travel_items
  add constraint saved_travel_items_source_type_check
  check (source_type in ('image', 'file', 'link', 'place', 'message'));

drop policy if exists "users read own saved travel items" on public.saved_travel_items;
create policy "users read own saved travel items"
on public.saved_travel_items for select to authenticated
using (auth.uid() = user_id);

drop policy if exists "users insert own saved travel items" on public.saved_travel_items;
create policy "users insert own saved travel items"
on public.saved_travel_items for insert to authenticated
with check (auth.uid() = user_id);

drop policy if exists "users update own saved travel items" on public.saved_travel_items;
create policy "users update own saved travel items"
on public.saved_travel_items for update to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "users delete own saved travel items" on public.saved_travel_items;
create policy "users delete own saved travel items"
on public.saved_travel_items for delete to authenticated
using (auth.uid() = user_id);

insert into storage.buckets (id, name, public, file_size_limit)
values ('saved-travel-items', 'saved-travel-items', false, 8388608)
on conflict (id) do update set public = false, file_size_limit = 8388608;

drop policy if exists "users read own saved travel files" on storage.objects;
create policy "users read own saved travel files"
on storage.objects for select to authenticated
using (
  bucket_id = 'saved-travel-items'
  and (storage.foldername(name))[1] = auth.uid()::text
);
