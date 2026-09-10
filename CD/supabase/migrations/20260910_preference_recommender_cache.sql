-- Preference recommender cache. The backend accesses these tables only with
-- SUPABASE_SERVICE_ROLE_KEY; mobile clients must never receive that key.

alter table public.places
    add column if not exists formatted_address text,
    add column if not exists rating double precision,
    add column if not exists google_maps_uri text,
    add column if not exists primary_type text,
    add column if not exists place_types text[] not null default '{}',
    add column if not exists photo_references jsonb not null default '[]'::jsonb,
    add column if not exists google_data_cached_at timestamptz,
    add column if not exists google_data_expires_at timestamptz;

alter table public.place_tags
    add column if not exists updated_at timestamptz not null default now();

create unique index if not exists places_google_place_id_key
    on public.places (google_place_id);

create unique index if not exists tags_name_key
    on public.tags (name);

create unique index if not exists place_tags_place_id_tag_id_key
    on public.place_tags (place_id, tag_id);

create index if not exists places_cache_lookup_idx
    on public.places (google_place_id, tag_status, tagger_version);

create index if not exists places_location_idx
    on public.places (latitude, longitude);

create index if not exists place_tags_place_id_idx
    on public.place_tags (place_id);

alter table public.places enable row level security;
alter table public.tags enable row level security;
alter table public.place_tags enable row level security;

comment on column public.places.google_data_expires_at is
    'Expiry for refreshable Google Places content. Derived tags can be reused while tagger_version matches.';
comment on column public.places.photo_references is
    'Google Places photo resource names and required author attributions; never cached image bytes.';
