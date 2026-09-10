-- Read the existing shared tag taxonomy without changing tags or its RLS.
begin;

create or replace function public.get_filter_tags_v1()
returns table (id bigint, name text, tag_type text)
language sql
stable
security definer
set search_path = public
as $$
  select t.id, t.name::text, t.tag_type::text
  from public.tags t
  order by t.tag_type, t.name;
$$;

revoke all on function public.get_filter_tags_v1() from public;
grant execute on function public.get_filter_tags_v1() to anon, authenticated;

commit;
