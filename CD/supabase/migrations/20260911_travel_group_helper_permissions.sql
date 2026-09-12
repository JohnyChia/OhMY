-- Lock down the legacy Travel Group helper and trigger functions as well.
revoke execute on function public.can_edit_travel_group(uuid) from public, anon;
revoke execute on function public.is_travel_group_creator(uuid) from public, anon;
revoke execute on function public.is_travel_group_member(uuid) from public, anon;
revoke execute on function public.is_travel_group_trip_owner(uuid) from public, anon;
revoke execute on function public.is_travel_group_trip_participant(uuid)
  from public, anon;

grant execute on function public.can_edit_travel_group(uuid) to authenticated;
grant execute on function public.is_travel_group_creator(uuid) to authenticated;
grant execute on function public.is_travel_group_member(uuid) to authenticated;
grant execute on function public.is_travel_group_trip_owner(uuid)
  to authenticated;
grant execute on function public.is_travel_group_trip_participant(uuid)
  to authenticated;

revoke execute on function public.protect_travel_group_member_role()
  from public, anon, authenticated;
revoke execute on function public.seed_travel_group_creator()
  from public, anon, authenticated;
revoke execute on function public.sync_travel_group_member_count()
  from public, anon, authenticated;
