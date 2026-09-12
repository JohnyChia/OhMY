create or replace function public.can_view_travel_group_profile(
  target_user_id text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    target_user_id = auth.uid()::text
    or exists (
      select 1
      from public.travel_group_members viewer
      join public.travel_group_members subject
        on subject.group_id = viewer.group_id
      where viewer.user_id = auth.uid()
        and subject.user_id::text = target_user_id
    );
$$;

revoke all on function public.can_view_travel_group_profile(text) from public;
grant execute on function public.can_view_travel_group_profile(text) to authenticated;

drop policy if exists "Travellers can read their own profile"
  on public.traveler_profiles;
drop policy if exists "Group members can read shared traveler profiles"
  on public.traveler_profiles;

create policy "Group members can read shared traveler profiles"
on public.traveler_profiles
for select
to authenticated
using (public.can_view_travel_group_profile(user_id));
