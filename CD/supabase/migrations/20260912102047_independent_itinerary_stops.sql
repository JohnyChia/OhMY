-- Suggestions and confirmed itinerary snapshots have independent lifetimes.
create or replace function public.remove_travel_group_suggestion(target_suggestion_id uuid)
returns void language plpgsql security invoker set search_path = ''
as $$
declare selected public.travel_group_suggestions%rowtype;
begin
  select * into selected from public.travel_group_suggestions where id = target_suggestion_id;
  if not found then return; end if;
  if selected.suggested_by <> auth.uid() and not public.can_edit_travel_group(selected.group_id) then
    raise exception 'You cannot remove this suggestion';
  end if;
  if selected.status = 'confirmed' and not public.can_edit_travel_group(selected.group_id) then
    raise exception 'Only the creator can remove a confirmed suggestion';
  end if;
  update public.travel_group_itinerary_stops set suggestion_id = null where suggestion_id = selected.id;
  delete from public.travel_group_suggestions where id = selected.id;
end;
$$;

-- Repair order, not history: anchor the originally selected destination.
with ordered as (
  select s.id, row_number() over (partition by s.group_id order by
    coalesce(s.external_place_id = g.destination_place_id, s.place_name = g.destination, false) desc,
    s.position, s.id) - 1 as new_position
  from public.travel_group_itinerary_stops s join public.travel_groups g on g.id=s.group_id
)
update public.travel_group_itinerary_stops s set position = ordered.new_position + 100000
from ordered where s.id=ordered.id;
update public.travel_group_itinerary_stops set position=position-100000 where position>=100000;
update public.travel_group_trip_sessions t set current_stop_index=s.position
from public.travel_group_itinerary_stops s where t.current_stop_id=s.id;

create or replace function public.start_travel_group_leg_to(target_group_id uuid, target_stop_id uuid)
returns uuid language plpgsql security invoker set search_path = ''
as $$
declare next_id uuid;
begin
  if not public.is_travel_group_creator(target_group_id) then raise exception 'Only the creator can start a leg'; end if;
  perform 1 from public.travel_groups where id=target_group_id and status='active' and trip_phase='choosing_next' for update;
  if not found then raise exception 'Finish the current stop before starting the next leg'; end if;
  select id into next_id from public.travel_group_itinerary_stops where group_id=target_group_id
    and status='upcoming' order by position limit 1;
  if next_id is null or target_stop_id is null or next_id <> target_stop_id then
    raise exception 'The next destination changed. Refresh the itinerary and try again';
  end if;
  return public.start_next_travel_group_leg(target_group_id);
end;
$$;
revoke all on function public.start_travel_group_leg_to(uuid,uuid) from public, anon;
grant execute on function public.start_travel_group_leg_to(uuid,uuid) to authenticated;

create or replace function public.remove_travel_group_itinerary_stop(target_group_id uuid,target_stop_id uuid)
returns void language plpgsql security invoker set search_path = ''
as $$
declare linked_suggestion uuid;
begin
  if not public.is_travel_group_creator(target_group_id) then raise exception 'Only the creator can remove an itinerary stop'; end if;
  select s.suggestion_id into linked_suggestion from public.travel_group_itinerary_stops s
    join public.travel_groups g on g.id=s.group_id
    where s.id=target_stop_id and s.group_id=target_group_id and s.status='upcoming'
      and not coalesce(s.external_place_id=g.destination_place_id, s.place_name=g.destination, false);
  if not found then raise exception 'The initial destination, active stop and completed history cannot be removed'; end if;
  delete from public.travel_group_itinerary_stops where id=target_stop_id;
  if linked_suggestion is not null then
    update public.travel_group_suggestions set status='proposed' where id=linked_suggestion;
  end if;
  with ordered as (
    select id,row_number() over(order by position)-1 as new_position
    from public.travel_group_itinerary_stops where group_id=target_group_id
  )
  update public.travel_group_itinerary_stops s set position=ordered.new_position+100000
  from ordered where s.id=ordered.id;
  update public.travel_group_itinerary_stops set position=position-100000
    where group_id=target_group_id and position>=100000;
end;
$$;
