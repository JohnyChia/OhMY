-- Joining must go through the proximity-validating RPC. Direct member inserts
-- would otherwise bypass the 10 km destination check.
drop policy if exists "member joins an open waiting group"
  on public.travel_group_members;
revoke insert on table public.travel_group_members from authenticated;
