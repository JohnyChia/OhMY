-- Existing traveler_profiles.user_id is text, so compare it with the
-- authenticated UUID converted to text. This preserves the team's schema.
alter table public.traveler_profiles enable row level security;

drop policy if exists "Travellers can read their own profile"
on public.traveler_profiles;
create policy "Travellers can read their own profile"
on public.traveler_profiles
for select
to authenticated
using (user_id = auth.uid()::text);

drop policy if exists "Travellers can create their own profile"
on public.traveler_profiles;
create policy "Travellers can create their own profile"
on public.traveler_profiles
for insert
to authenticated
with check (user_id = auth.uid()::text);

drop policy if exists "Travellers can update their own profile"
on public.traveler_profiles;
create policy "Travellers can update their own profile"
on public.traveler_profiles
for update
to authenticated
using (user_id = auth.uid()::text)
with check (user_id = auth.uid()::text);
