-- Accepting a join request changes two records. Keep the request and
-- membership in one transaction so a creator never sees a half-accepted user.
create or replace function public.respond_travel_group_join_request(
  target_request_id uuid,
  accept_request boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  join_request public.travel_group_join_requests%rowtype;
  target_group public.travel_groups%rowtype;
  current_member_count integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;

  select *
  into join_request
  from public.travel_group_join_requests
  where id = target_request_id
  for update;

  if not found then
    raise exception 'Join request not found';
  end if;

  select *
  into target_group
  from public.travel_groups
  where id = join_request.group_id
  for update;

  if target_group.creator_id <> auth.uid() then
    raise exception 'Only the group creator can respond to this request';
  end if;

  if join_request.status <> 'pending' then
    raise exception 'This join request has already been answered';
  end if;

  if accept_request then
    if target_group.trip_phase <> 'recruiting' then
      raise exception 'The group is no longer accepting travellers';
    end if;

    select count(*)
    into current_member_count
    from public.travel_group_members
    where group_id = join_request.group_id;

    if current_member_count >= target_group.max_members then
      raise exception 'The group is already full';
    end if;

    insert into public.travel_group_members (
      group_id,
      user_id,
      role,
      display_name
    ) values (
      join_request.group_id,
      join_request.user_id,
      'member',
      join_request.traveller_name
    )
    on conflict (group_id, user_id) do nothing;
  end if;

  update public.travel_group_join_requests
  set status = case when accept_request then 'accepted' else 'declined' end,
      responded_by = auth.uid(),
      responded_at = now()
  where id = target_request_id;
end;
$$;

revoke all on function public.respond_travel_group_join_request(uuid, boolean)
  from public;
revoke execute on function public.respond_travel_group_join_request(uuid, boolean)
  from anon;
grant execute on function public.respond_travel_group_join_request(uuid, boolean)
  to authenticated;
