revoke all on function public.discover_travel_groups(uuid) from anon;
revoke all on function public.discover_travel_groups(uuid) from public;
grant execute on function public.discover_travel_groups(uuid) to authenticated;

drop policy if exists "members read private travel group details"
  on public.travel_groups;

create policy "members read private travel group details"
on public.travel_groups
for select
to authenticated
using (
  creator_id = (select auth.uid())
  or public.is_travel_group_member(id)
);
