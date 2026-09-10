-- Community Discovery v2
-- Scope: only community_* tables/functions and Supabase Realtime publication.
-- Existing trips, profiles, places, and tags are read but never altered.

alter table public.community_posts
  add column if not exists title text,
  add column if not exists attraction_name text,
  add column if not exists image_url text,
  add column if not exists is_seed boolean not null default false,
  add column if not exists moderation_status text not null default 'approved',
  add column if not exists moderation_reason text,
  add column if not exists location_relevance_score integer not null default 100;

alter table public.community_posts alter column author_id drop not null;
alter table public.community_posts alter column trip_session_id drop not null;
alter table public.community_posts alter column image_path drop not null;

update public.community_posts
set title = coalesce(nullif(title, ''), location_name),
    attraction_name = coalesce(nullif(attraction_name, ''), location_name)
where title is null or attraction_name is null;

alter table public.community_posts alter column title set not null;
alter table public.community_posts alter column attraction_name set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.community_posts'::regclass
      and conname = 'community_posts_moderation_status_check'
  ) then
    alter table public.community_posts
      add constraint community_posts_moderation_status_check
      check (moderation_status in ('approved', 'rejected', 'pending'));
  end if;
end $$;

create or replace function public.validate_community_post_trip()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  trip_owner uuid;
  trip_status text;
  trip_destination text;
  trip_name text;
  is_participant boolean;
begin
  if new.is_seed then
    if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then
      raise exception 'Seed posts can only be managed by the service role.';
    end if;
    if new.author_id is not null or new.trip_session_id is not null then
      raise exception 'Seed posts cannot impersonate a user or trip.';
    end if;
    return new;
  end if;

  if auth.uid() is null or new.author_id is distinct from auth.uid() then
    raise exception 'Sign in as the post author.';
  end if;

  select s.started_by, s.status, g.destination, g.name,
         exists (
           select 1 from public.travel_group_trip_participants p
           where p.session_id = s.id and p.user_id = auth.uid()
         )
    into trip_owner, trip_status, trip_destination, trip_name, is_participant
  from public.travel_group_trip_sessions s
  join public.travel_groups g on g.id = s.group_id
  where s.id = new.trip_session_id;

  if not found then raise exception 'Trip session not found.'; end if;
  if trip_status not in ('ended', 'completed') then
    raise exception 'Finish the trip before creating a post.';
  end if;
  if trip_owner is distinct from auth.uid() and not is_participant then
    raise exception 'You were not a participant in this trip.';
  end if;

  new.location_name := trip_destination;
  new.attraction_name := trip_name;
  return new;
end;
$$;

create or replace function public.community_text_matches_trip(
  post_title text,
  post_description text,
  trip_destination text,
  trip_name text
) returns boolean
language sql
immutable
as $$
  select
    lower(concat_ws(' ', post_title, post_description)) like '%' || lower(trim(trip_destination)) || '%'
    or lower(concat_ws(' ', post_title, post_description)) like '%' || lower(trim(trip_name)) || '%'
    or exists (
      select 1
      from unnest(regexp_split_to_array(lower(trim(trip_destination)), '\\s+')) word
      where length(word) >= 4
        and lower(concat_ws(' ', post_title, post_description)) like '%' || word || '%'
    );
$$;

create or replace function public.create_community_post_v2(
  p_trip_session_id uuid,
  p_title text,
  p_description text,
  p_image_path text,
  p_tag_ids bigint[]
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
  destination text;
  trip_name text;
begin
  if auth.uid() is null then raise exception 'Please sign in.'; end if;
  if length(trim(p_title)) not between 3 and 120 then
    raise exception 'Title must be between 3 and 120 characters.';
  end if;
  if length(trim(p_description)) not between 10 and 1000 then
    raise exception 'Description must be between 10 and 1000 characters.';
  end if;
  if p_image_path is null or trim(p_image_path) = '' then
    raise exception 'A picture is required.';
  end if;
  if coalesce(cardinality(p_tag_ids), 0) = 0 then
    raise exception 'Select at least one tag.';
  end if;
  if exists (select 1 from unnest(p_tag_ids) x where not exists (select 1 from public.tags t where t.id = x)) then
    raise exception 'One or more tags do not exist.';
  end if;

  select g.destination, g.name into destination, trip_name
  from public.travel_group_trip_sessions s
  join public.travel_groups g on g.id = s.group_id
  where s.id = p_trip_session_id;

  if not public.community_text_matches_trip(p_title, p_description, destination, trip_name) then
    raise exception 'Location review failed. Mention the trip destination or attraction in the title or description.';
  end if;

  insert into public.community_posts (
    author_id, author_name, trip_session_id, title, attraction_name,
    location_name, description, image_path, is_seed,
    moderation_status, moderation_reason, location_relevance_score
  ) values (
    auth.uid(), public.community_user_display_name(), p_trip_session_id,
    trim(p_title), trip_name, destination, trim(p_description), p_image_path,
    false, 'approved', 'Completed-trip ownership and text/location relevance verified.', 100
  ) returning id into new_id;

  insert into public.community_post_tags(post_id, tag_id)
  select distinct new_id, tag_id from unnest(p_tag_ids) tag_id;
  return new_id;
end;
$$;

create or replace function public.update_community_post_v2(
  p_post_id uuid,
  p_title text,
  p_description text,
  p_image_path text,
  p_tag_ids bigint[]
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  existing public.community_posts%rowtype;
  destination text;
  trip_name text;
begin
  select * into existing from public.community_posts where id = p_post_id for update;
  if not found then raise exception 'Post not found.'; end if;
  if existing.is_seed or existing.author_id is distinct from auth.uid() then
    raise exception 'Only the author can edit this post.';
  end if;
  if length(trim(p_title)) not between 3 and 120 then
    raise exception 'Title must be between 3 and 120 characters.';
  end if;
  if length(trim(p_description)) not between 10 and 1000 then
    raise exception 'Description must be between 10 and 1000 characters.';
  end if;
  if coalesce(cardinality(p_tag_ids), 0) = 0 then raise exception 'Select at least one tag.'; end if;
  if exists (select 1 from unnest(p_tag_ids) x where not exists (select 1 from public.tags t where t.id = x)) then
    raise exception 'One or more tags do not exist.';
  end if;

  select g.destination, g.name into destination, trip_name
  from public.travel_group_trip_sessions s join public.travel_groups g on g.id = s.group_id
  where s.id = existing.trip_session_id;
  if not public.community_text_matches_trip(p_title, p_description, destination, trip_name) then
    raise exception 'Location review failed. Mention the trip destination or attraction in the title or description.';
  end if;

  update public.community_posts set
    title = trim(p_title), description = trim(p_description),
    image_path = coalesce(nullif(trim(p_image_path), ''), image_path),
    moderation_status = 'approved',
    moderation_reason = 'Completed-trip ownership and text/location relevance verified.',
    location_relevance_score = 100, updated_at = now()
  where id = p_post_id;

  delete from public.community_post_tags where post_id = p_post_id;
  insert into public.community_post_tags(post_id, tag_id)
  select distinct p_post_id, tag_id from unnest(p_tag_ids) tag_id;
  return p_post_id;
end;
$$;

create or replace function public.community_feed_v2(
  search_query text default '',
  tag_filters bigint[] default '{}',
  result_limit integer default 50,
  result_offset integer default 0,
  bookmarked_only boolean default false
) returns table (
  id uuid, author_id uuid, author_name text, trip_session_id uuid,
  title text, attraction_name text, location_name text, description text,
  image_path text, image_url text, tags text[], tag_ids bigint[],
  created_at timestamptz, updated_at timestamptz,
  like_count bigint, comment_count bigint,
  is_liked boolean, is_bookmarked boolean, is_owner boolean,
  moderation_status text
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.author_id, p.author_name, p.trip_session_id,
    p.title, p.attraction_name, p.location_name, p.description,
    p.image_path, p.image_url,
    coalesce((select array_agg(t.name order by t.name) from public.community_post_tags pt join public.tags t on t.id=pt.tag_id where pt.post_id=p.id), '{}'),
    coalesce((select array_agg(pt.tag_id order by pt.tag_id) from public.community_post_tags pt where pt.post_id=p.id), '{}'),
    p.created_at, p.updated_at,
    (select count(*) from public.community_post_likes l where l.post_id=p.id),
    (select count(*) from public.community_post_comments c where c.post_id=p.id),
    exists(select 1 from public.community_post_likes l where l.post_id=p.id and l.user_id=auth.uid()),
    exists(select 1 from public.community_post_bookmarks b where b.post_id=p.id and b.user_id=auth.uid()),
    (p.author_id is not null and p.author_id=auth.uid()), p.moderation_status
  from public.community_posts p
  where p.moderation_status='approved'
    and (not bookmarked_only or exists(select 1 from public.community_post_bookmarks b where b.post_id=p.id and b.user_id=auth.uid()))
    and (coalesce(cardinality(tag_filters),0)=0 or exists(select 1 from public.community_post_tags pt where pt.post_id=p.id and pt.tag_id=any(tag_filters)))
    and (trim(search_query)='' or lower(concat_ws(' ',p.title,p.attraction_name,p.location_name,p.description,p.author_name)) like '%'||lower(trim(search_query))||'%'
      or exists(select 1 from public.community_post_tags pt join public.tags t on t.id=pt.tag_id where pt.post_id=p.id and lower(t.name) like '%'||lower(trim(search_query))||'%'))
  order by p.created_at desc limit least(greatest(result_limit,1),100) offset greatest(result_offset,0);
$$;

create or replace function public.eligible_community_trips_v2()
returns table (id uuid, title text, location_name text, attraction_name text, ended_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select s.id, g.name, g.destination, g.name, coalesce(s.ended_at,s.updated_at)
  from public.travel_group_trip_sessions s
  join public.travel_groups g on g.id=s.group_id
  where auth.uid() is not null
    and s.status in ('ended','completed')
    and (s.started_by=auth.uid() or exists(select 1 from public.travel_group_trip_participants p where p.session_id=s.id and p.user_id=auth.uid()))
    and not exists(select 1 from public.community_posts cp where cp.trip_session_id=s.id)
  order by coalesce(s.ended_at,s.updated_at) desc;
$$;

grant execute on function public.community_feed_v2(text,bigint[],integer,integer,boolean) to anon, authenticated;
grant execute on function public.eligible_community_trips_v2() to authenticated;
grant execute on function public.create_community_post_v2(uuid,text,text,text,bigint[]) to authenticated;
grant execute on function public.update_community_post_v2(uuid,text,text,text,bigint[]) to authenticated;

insert into public.community_posts
  (id, author_id, author_name, trip_session_id, title, attraction_name, location_name,
   description, image_path, image_url, is_seed, moderation_status, moderation_reason,
   location_relevance_score, created_at, updated_at)
values
('6f5a3f36-7d79-4d9d-a101-000000000001',null,'Aina',null,'Morning light at Kwai Chai Hong','Kwai Chai Hong','Kuala Lumpur','Visit Kwai Chai Hong in Kuala Lumpur before 9 AM for quieter lanes, heritage murals and beautiful morning light.',null,'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=1200',true,'approved','Curated Kuala Lumpur seed post.',100,now()-interval '1 hour',now()-interval '1 hour'),
('6f5a3f36-7d79-4d9d-a101-000000000002',null,'Ravi',null,'Petronas Towers after sunset','Petronas Twin Towers','Kuala Lumpur','The Petronas Twin Towers and KLCC skyline in Kuala Lumpur look best just after sunset when the city lights appear.',null,'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=1200',true,'approved','Curated Kuala Lumpur seed post.',100,now()-interval '5 hours',now()-interval '5 hours'),
('6f5a3f36-7d79-4d9d-a101-000000000003',null,'Mei',null,'A slow walk around Merdeka Square','Merdeka Square','Kuala Lumpur','Merdeka Square is an easy Kuala Lumpur heritage walk with colonial architecture and plenty of open space for photos.',null,'https://images.unsplash.com/photo-1568659585069-facb248da994?w=1200',true,'approved','Curated Kuala Lumpur seed post.',100,now()-interval '1 day',now()-interval '1 day'),
('6f5a3f36-7d79-4d9d-a101-000000000004',null,'Farah',null,'Local finds at Central Market','Central Market','Kuala Lumpur','Central Market in Kuala Lumpur is useful for local crafts, small gifts and a quick introduction to Malaysian culture.',null,'https://images.unsplash.com/photo-1516211697506-8360dbcfe9a4?w=1200',true,'approved','Curated Kuala Lumpur seed post.',100,now()-interval '2 days',now()-interval '2 days'),
('6f5a3f36-7d79-4d9d-a101-000000000005',null,'Daniel',null,'Dinner along Jalan Alor','Jalan Alor','Kuala Lumpur','Jalan Alor in Kuala Lumpur comes alive at night. Share a few dishes and walk the full street before choosing a stall.',null,'https://images.unsplash.com/photo-1559314809-0d155014e29e?w=1200',true,'approved','Curated Kuala Lumpur seed post.',100,now()-interval '3 days',now()-interval '3 days'),
('6f5a3f36-7d79-4d9d-a101-000000000006',null,'Nurul',null,'A green break at KLCC Park','KLCC Park','Kuala Lumpur','KLCC Park is a calm green break in central Kuala Lumpur with shaded paths and a clear view of the towers.',null,'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=1200',true,'approved','Curated Kuala Lumpur seed post.',100,now()-interval '4 days',now()-interval '4 days'),
('6f5a3f36-7d79-4d9d-a101-000000000007',null,'Jason',null,'Evening energy in Bukit Bintang','Bukit Bintang','Kuala Lumpur','Bukit Bintang is one of Kuala Lumpur''s liveliest evening areas for shopping, cafes and people-watching.',null,'https://images.unsplash.com/photo-1518005020951-eccb494ad742?w=1200',true,'approved','Curated Kuala Lumpur seed post.',100,now()-interval '5 days',now()-interval '5 days')
on conflict (id) do update set
  title=excluded.title, attraction_name=excluded.attraction_name,
  location_name=excluded.location_name, description=excluded.description,
  image_url=excluded.image_url, updated_at=excluded.updated_at;

insert into public.community_post_tags(post_id,tag_id)
select seed.post_id,t.id from (values
 ('6f5a3f36-7d79-4d9d-a101-000000000001'::uuid,'Heritage'),
 ('6f5a3f36-7d79-4d9d-a101-000000000001'::uuid,'Cultural Experience'),
 ('6f5a3f36-7d79-4d9d-a101-000000000002'::uuid,'Landmark'),
 ('6f5a3f36-7d79-4d9d-a101-000000000003'::uuid,'Historical Landmark'),
 ('6f5a3f36-7d79-4d9d-a101-000000000004'::uuid,'Traditional Craft'),
 ('6f5a3f36-7d79-4d9d-a101-000000000005'::uuid,'Local Cuisine'),
 ('6f5a3f36-7d79-4d9d-a101-000000000006'::uuid,'Nature'),
 ('6f5a3f36-7d79-4d9d-a101-000000000007'::uuid,'Shopping'),
 ('6f5a3f36-7d79-4d9d-a101-000000000007'::uuid,'Cafe')
) seed(post_id,tag_name)
join public.tags t on lower(t.name)=lower(seed.tag_name)
on conflict do nothing;

do $$
declare table_name text;
begin
  foreach table_name in array array['community_posts','community_post_tags','community_post_likes','community_post_bookmarks','community_post_comments'] loop
    if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=table_name) then
      execute format('alter publication supabase_realtime add table public.%I',table_name);
    end if;
  end loop;
end $$;
