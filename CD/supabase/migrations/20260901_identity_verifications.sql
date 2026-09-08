-- Verified Traveller prototype records. This is separate from
-- traveler_profiles because only the secure local backend may write it.
create table if not exists public.identity_verifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  document_type text not null check (document_type in ('mykad', 'passport')),
  document_hash text,
  status text not null default 'processing'
    check (status in ('processing', 'verified', 'failed')),
  face_match_score double precision,
  failure_code text,
  storage_prefix text,
  purge_after timestamptz,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- A document can have many failed attempts, but only one verified owner.
create unique index if not exists identity_verifications_verified_document_key
on public.identity_verifications (document_hash)
where status = 'verified' and document_hash is not null;

create index if not exists identity_verifications_user_id_idx
on public.identity_verifications (user_id, created_at desc);

alter table public.identity_verifications enable row level security;

drop policy if exists "Travellers can read their own verification status"
on public.identity_verifications;
create policy "Travellers can read their own verification status"
on public.identity_verifications
for select
to authenticated
using (user_id = auth.uid());

-- No insert/update/delete policy is intentionally provided. Only the local
-- backend service role can change verification results.

insert into storage.buckets (id, name, public)
values ('identity-verification-private', 'identity-verification-private', false)
on conflict (id) do update set public = false;

-- Users receive no direct Storage policy. Photos are uploaded and deleted by
-- the trusted local backend only, so they cannot read each other's documents.
