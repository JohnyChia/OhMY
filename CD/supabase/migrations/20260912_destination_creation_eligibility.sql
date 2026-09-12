-- GPS-based eligibility for group creation. The legacy function remains
-- callable only by this authenticated, validated security-definer wrapper.
create or replace function public.create_nearby_travel_group(
  group_name text, destination_name text, group_description text,
  group_tags text[], group_max_members integer, group_join_mode text,
  creator_display_name text, external_destination_id text,
  destination_formatted_address text, destination_lat double precision,
  destination_lng double precision, creator_lat double precision,
  creator_lng double precision, destination_photo text default null
) returns uuid
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;
  if creator_lat is null or creator_lng is null
      or creator_lat not between -90 and 90
      or creator_lng not between -180 and 180
      or destination_lat is null or destination_lng is null
      or destination_lat not between -90 and 90
      or destination_lng not between -180 and 180 then
    raise exception 'A current device location and valid destination are required';
  end if;
  if public.travel_group_distance_km(creator_lat, creator_lng,
      destination_lat, destination_lng) > 10.0 then
    raise exception 'Move within 10 km of the destination to create a group';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 0));
  if exists (
    select 1 from public.travel_group_members m
    join public.travel_groups g on g.id = m.group_id
    where m.user_id = auth.uid() and g.status in ('waiting', 'active')
  ) then
    raise exception 'Leave or finish your current Travel Group before creating another one';
  end if;
  return public.create_travel_group_with_destination(
    group_name, destination_name, group_description, group_tags,
    group_max_members, group_join_mode, creator_display_name,
    external_destination_id, destination_formatted_address,
    destination_lat, destination_lng, destination_photo);
end;
$$;
revoke all on function public.create_travel_group_with_destination(
  text, text, text, text[], integer, text, text, text, text,
  double precision, double precision, text) from public, anon, authenticated;
revoke all on function public.create_nearby_travel_group(
  text, text, text, text[], integer, text, text, text, text,
  double precision, double precision, double precision, double precision, text)
  from public, anon;
grant execute on function public.create_nearby_travel_group(
  text, text, text, text[], integer, text, text, text, text,
  double precision, double precision, double precision, double precision, text)
  to authenticated;
