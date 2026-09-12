-- Supabase projects can have explicit role grants in addition to PUBLIC's
-- default function privilege. The Travel Group API is authenticated-only.
do $$
declare
  function_signature regprocedure;
begin
  for function_signature in
    select procedure.oid::regprocedure
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = any (array[
        'begin_travel_group_journey',
        'can_edit_travel_group',
        'complete_travel_group_stop',
        'confirm_travel_group',
        'confirm_travel_group_suggestion',
        'create_travel_group_with_destination',
        'end_travel_group_journey',
        'is_travel_group_creator',
        'is_travel_group_member',
        'is_travel_group_trip_owner',
        'is_travel_group_trip_participant',
        'respond_travel_group_join_request'
      ])
  loop
    execute format('revoke execute on function %s from anon', function_signature);
  end loop;

  for function_signature in
    select procedure.oid::regprocedure
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = any (array[
        'protect_travel_group_member_role',
        'seed_travel_group_creator',
        'sync_travel_group_member_count'
      ])
  loop
    execute format(
      'revoke execute on function %s from anon, authenticated',
      function_signature
    );
  end loop;
end;
$$;
