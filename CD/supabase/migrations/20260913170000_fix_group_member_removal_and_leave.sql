-- Fix recruitment member removal and let non-creators leave a Travel Group.

create or replace function public.remove_travel_group_member(
  target_group_id uuid,
  target_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_creator_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;

  select creator_id into target_creator_id
  from public.travel_groups
  where id = target_group_id
    and creator_id = auth.uid()
    and status = 'waiting'
    and trip_phase = 'recruiting'
    and confirmed_at is null
  for update;

  if target_creator_id is null then
    raise exception 'Travellers can only be removed by the creator while the group is recruiting';
  end if;
  if target_user_id = target_creator_id then
    raise exception 'The creator cannot be removed from their own group';
  end if;

  delete from public.travel_group_members
  where group_id = target_group_id and user_id = target_user_id;

  if not found then
    raise exception 'This traveller is no longer in the group';
  end if;

  delete from public.travel_group_join_requests
  where group_id = target_group_id and user_id = target_user_id;
end;
$$;

revoke all on function public.remove_travel_group_member(uuid, uuid)
  from public, anon;
grant execute on function public.remove_travel_group_member(uuid, uuid)
  to authenticated;

create or replace function public.leave_travel_group(target_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_creator_id uuid;
  target_status text;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;

  select creator_id, status into target_creator_id, target_status
  from public.travel_groups
  where id = target_group_id
  for update;

  if target_creator_id is null then
    raise exception 'Travel group not found';
  end if;
  if target_creator_id = auth.uid() then
    raise exception 'Creators must end or delete their Travel Group';
  end if;
  if target_status in ('completed', 'cancelled') then
    raise exception 'This Travel Group has already ended';
  end if;
  if not exists (
    select 1
    from public.travel_group_members member
    where member.group_id = target_group_id
      and member.user_id = auth.uid()
  ) then
    raise exception 'You are no longer a member of this group';
  end if;

  delete from public.travel_group_trip_participants participant
  using public.travel_group_trip_sessions session
  where participant.session_id = session.id
    and session.group_id = target_group_id
    and participant.user_id = auth.uid();

  delete from public.travel_group_join_requests
  where group_id = target_group_id and user_id = auth.uid();

  delete from public.travel_group_members
  where group_id = target_group_id and user_id = auth.uid();
end;
$$;

revoke all on function public.leave_travel_group(uuid) from public, anon;
grant execute on function public.leave_travel_group(uuid) to authenticated;

-- Ensure PostgREST exposes the new RPC immediately after this migration.
notify pgrst, 'reload schema';
