-- Blocks accidental row deletion without changing existing data or RLS.
-- INSERT, UPDATE, and normal ON CONFLICT DO UPDATE remain available.
-- Owners/admins can still remove this guard; it is not an admin security boundary.
create or replace function public.guard_traveler_profiles_deletion()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog
as $$
begin
  raise log 'traveler_profiles deletion guard: operation=%, session_user=%, current_user=%, application=%',
    TG_OP, session_user, current_user,
    current_setting('application_name', true);
  raise exception using
    errcode = '42501',
    message = 'Deleting or truncating traveler_profiles is blocked by the profile data protection guard.',
    hint = 'Keep existing profiles and update their fields instead. Intentional account-data deletion requires coordinated database-owner maintenance.';
end;
$$;

revoke all on function public.guard_traveler_profiles_deletion()
from public, anon, authenticated, service_role;

create or replace trigger protect_traveler_profiles_deletion
before delete or truncate on public.traveler_profiles
for each statement
execute function public.guard_traveler_profiles_deletion();

alter table public.traveler_profiles
enable always trigger protect_traveler_profiles_deletion;
