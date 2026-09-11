-- Community Discovery v5: Profile Travel History integration.
-- Changes only Community-owned objects. public.travel_history_entries and
-- public.tags are read but never altered.
begin;

alter table public.community_posts
  add column if not exists history_entry_id uuid;

do $$
begin
  if to_regclass('public.travel_history_entries') is null then
    raise exception 'Apply 20260911_travel_history.sql before Community v5.';
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.community_posts'::regclass
      and conname = 'community_posts_history_entry_fk'
  ) then
    alter table public.community_posts
      add constraint community_posts_history_entry_fk
      foreign key (history_entry_id)
      references public.travel_history_entries(id)
      on delete restrict;
  end if;
end $$;

create unique index if not exists community_one_post_per_history_entry
  on public.community_posts(history_entry_id)
  where history_entry_id is not null;

create or replace function public.community_validation_context_v5(
  p_user_id uuid,
  p_history_entry_id uuid default null,
  p_post_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_history_id uuid;
  selected_trip_session_id uuid;
  selected_post_id uuid;
  post_owner uuid;
  post_is_seed boolean;
  destination text;
  history_type text;
  legacy_context jsonb;
begin
  if p_user_id is null or num_nonnulls(p_history_entry_id, p_post_id) <> 1 then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'Choose one Travel History entry or post.'
    );
  end if;

  if p_post_id is not null then
    select p.history_entry_id, p.trip_session_id, p.author_id, p.is_seed
      into selected_history_id, selected_trip_session_id, post_owner, post_is_seed
    from public.community_posts p
    where p.id = p_post_id;

    if not found then
      return jsonb_build_object('eligible', false, 'reason', 'Post not found.');
    end if;
    if post_is_seed or post_owner is distinct from p_user_id then
      return jsonb_build_object(
        'eligible', false,
        'reason', 'Only the author can edit this post.'
      );
    end if;
    if selected_history_id is null then
      if selected_trip_session_id is null then
        return jsonb_build_object(
          'eligible', false,
          'reason', 'This older post is not linked to Travel History.'
        );
      end if;
      legacy_context := public.community_validation_context_v4(
        p_user_id,
        null,
        p_post_id
      );
      return legacy_context || jsonb_build_object('history_entry_id', null);
    end if;
    selected_post_id := p_post_id;
  else
    selected_history_id := p_history_entry_id;
    select p.id into selected_post_id
    from public.community_posts p
    where p.history_entry_id = selected_history_id;
    if selected_post_id is not null then
      return jsonb_build_object(
        'eligible', false,
        'reason', 'This Travel History entry already has a post.'
      );
    end if;
  end if;

  select h.destination, h.source_type
    into destination, history_type
  from public.travel_history_entries h
  where h.id = selected_history_id
    and h.user_id = p_user_id;

  if not found then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'Travel History entry was not found for this account.'
    );
  end if;
  if history_type is distinct from 'solo' then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'Only solo Travel History entries can be shared.'
    );
  end if;
  if nullif(trim(destination), '') is null then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'This Travel History entry has no destination.'
    );
  end if;

  return jsonb_build_object(
    'eligible', true,
    'reason', 'Travel History entry is eligible.',
    'destination', trim(destination),
    'attraction', trim(destination),
    'history_entry_id', selected_history_id,
    'existing_post_id', selected_post_id
  );
end;
$$;

create or replace function public.community_create_post_v5(
  p_user_id uuid,
  p_history_entry_id uuid,
  p_title text,
  p_description text,
  p_image_paths text[],
  p_tag_ids bigint[],
  p_moderation_reason text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
  path_value text;
  image_index integer;
  context jsonb;
begin
  context := public.community_validation_context_v5(
    p_user_id,
    p_history_entry_id,
    null
  );
  if not coalesce((context->>'eligible')::boolean, false) then
    raise exception '%', context->>'reason';
  end if;
  if length(trim(p_title)) not between 3 and 120 then
    raise exception 'Title must be between 3 and 120 characters.';
  end if;
  if length(trim(p_description)) not between 10 and 1000 then
    raise exception 'Description must be between 10 and 1000 characters.';
  end if;
  if cardinality(p_image_paths) not between 1 and 6 then
    raise exception 'Select between 1 and 6 pictures.';
  end if;
  if cardinality(p_tag_ids) not between 1 and 3 then
    raise exception 'Automatic tags are missing.';
  end if;
  if exists (
    select 1 from unnest(p_tag_ids) id
    where not exists (select 1 from public.tags t where t.id = id)
  ) then
    raise exception 'Automatic tag does not exist.';
  end if;
  foreach path_value in array p_image_paths loop
    if path_value is null or path_value not like p_user_id::text || '/%' then
      raise exception 'One or more pictures do not belong to the signed-in user.';
    end if;
  end loop;

  perform set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into public.community_posts(
    author_id, author_name, history_entry_id, title, attraction_name,
    location_name, description, image_path, is_seed, moderation_status,
    moderation_reason, location_relevance_score
  ) values (
    p_user_id, public.community_user_display_name(), p_history_entry_id,
    trim(p_title), context->>'destination', context->>'destination',
    trim(p_description), p_image_paths[1], false, 'approved',
    p_moderation_reason, 100
  ) returning id into new_id;

  insert into public.community_post_tags(post_id, tag_id)
  select new_id, id from unnest(p_tag_ids) id;
  for image_index in 1..cardinality(p_image_paths) loop
    insert into public.community_post_images(post_id, position, image_path)
    values(new_id, image_index - 1, p_image_paths[image_index]);
  end loop;
  return new_id;
end;
$$;

create or replace function public.community_update_post_v5(
  p_user_id uuid,
  p_post_id uuid,
  p_title text,
  p_description text,
  p_image_paths text[],
  p_tag_ids bigint[],
  p_moderation_reason text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  path_value text;
  image_index integer;
  context jsonb;
begin
  context := public.community_validation_context_v5(p_user_id, null, p_post_id);
  if not coalesce((context->>'eligible')::boolean, false) then
    raise exception '%', context->>'reason';
  end if;
  if length(trim(p_title)) not between 3 and 120 then
    raise exception 'Title must be between 3 and 120 characters.';
  end if;
  if length(trim(p_description)) not between 10 and 1000 then
    raise exception 'Description must be between 10 and 1000 characters.';
  end if;
  if cardinality(p_image_paths) > 6 then
    raise exception 'A post can contain up to 6 pictures.';
  end if;
  if cardinality(p_tag_ids) not between 1 and 3 then
    raise exception 'Automatic tags are missing.';
  end if;
  if exists (
    select 1 from unnest(p_tag_ids) id
    where not exists (select 1 from public.tags t where t.id = id)
  ) then
    raise exception 'Automatic tag does not exist.';
  end if;
  foreach path_value in array p_image_paths loop
    if path_value is null or path_value not like p_user_id::text || '/%' then
      raise exception 'One or more pictures do not belong to the signed-in user.';
    end if;
  end loop;

  perform set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  update public.community_posts set
    title = trim(p_title),
    description = trim(p_description),
    image_path = case
      when cardinality(p_image_paths) > 0 then p_image_paths[1]
      else image_path
    end,
    moderation_status = 'approved',
    moderation_reason = p_moderation_reason,
    updated_at = now()
  where id = p_post_id;

  delete from public.community_post_tags where post_id = p_post_id;
  insert into public.community_post_tags(post_id, tag_id)
  select p_post_id, id from unnest(p_tag_ids) id;
  if cardinality(p_image_paths) > 0 then
    delete from public.community_post_images where post_id = p_post_id;
    for image_index in 1..cardinality(p_image_paths) loop
      insert into public.community_post_images(post_id, position, image_path)
      values(p_post_id, image_index - 1, p_image_paths[image_index]);
    end loop;
  end if;
  return p_post_id;
end;
$$;

create or replace function public.community_post_id_for_history_v5(
  p_history_entry_id uuid
) returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select p.id
  from public.community_posts p
  where p.history_entry_id = p_history_entry_id
    and p.author_id = auth.uid()
  limit 1;
$$;

create or replace function public.eligible_community_history_entries_v5()
returns table (
  id uuid,
  title text,
  location_name text,
  attraction_name text,
  ended_at timestamptz,
  community_post_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  select h.id, h.title, h.destination, h.destination, h.ended_at, p.id
  from public.travel_history_entries h
  left join public.community_posts p
    on p.history_entry_id = h.id and p.author_id = auth.uid()
  where auth.uid() is not null
    and h.user_id = auth.uid()
    and h.source_type = 'solo'
  order by h.ended_at desc;
$$;

create or replace function public.community_feed_v5(
  search_query text default '',
  tag_filters bigint[] default '{}',
  result_limit integer default 50,
  result_offset integer default 0,
  bookmarked_only boolean default false
) returns table (
  id uuid, author_id uuid, author_name text, trip_session_id uuid,
  history_entry_id uuid, title text, attraction_name text,
  location_name text, description text, image_path text, image_url text,
  image_paths text[], image_urls text[], tags text[], tag_ids bigint[],
  created_at timestamptz, updated_at timestamptz, like_count bigint,
  comment_count bigint, is_liked boolean, is_bookmarked boolean,
  is_owner boolean, moderation_status text
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.author_id, p.author_name, p.trip_session_id,
    p.history_entry_id, p.title, p.attraction_name, p.location_name,
    p.description, p.image_path, p.image_url,
    coalesce((select array_agg(i.image_path order by i.position)
      filter (where i.image_path is not null)
      from public.community_post_images i where i.post_id = p.id), '{}'),
    coalesce((select array_agg(i.image_url order by i.position)
      filter (where i.image_url is not null)
      from public.community_post_images i where i.post_id = p.id), '{}'),
    coalesce((select array_agg(t.name order by t.name)
      from public.community_post_tags pt join public.tags t on t.id=pt.tag_id
      where pt.post_id=p.id), '{}'),
    coalesce((select array_agg(pt.tag_id order by pt.tag_id)
      from public.community_post_tags pt where pt.post_id=p.id), '{}'),
    p.created_at, p.updated_at,
    (select count(*) from public.community_post_likes l where l.post_id=p.id),
    (select count(*) from public.community_post_comments c where c.post_id=p.id),
    exists(select 1 from public.community_post_likes l
      where l.post_id=p.id and l.user_id=auth.uid()),
    exists(select 1 from public.community_post_bookmarks b
      where b.post_id=p.id and b.user_id=auth.uid()),
    (p.author_id is not null and p.author_id=auth.uid()),
    p.moderation_status
  from public.community_posts p
  where p.moderation_status='approved'
    and (not bookmarked_only or exists(select 1
      from public.community_post_bookmarks b
      where b.post_id=p.id and b.user_id=auth.uid()))
    and (coalesce(cardinality(tag_filters),0)=0 or exists(select 1
      from public.community_post_tags pt
      where pt.post_id=p.id and pt.tag_id=any(tag_filters)))
    and (trim(search_query)='' or lower(concat_ws(' ',p.title,
      p.attraction_name,p.location_name,p.description,p.author_name))
      like '%'||lower(trim(search_query))||'%'
      or exists(select 1 from public.community_post_tags pt
        join public.tags t on t.id=pt.tag_id
        where pt.post_id=p.id
          and lower(t.name) like '%'||lower(trim(search_query))||'%'))
  order by p.created_at desc
  limit least(greatest(result_limit,1),100)
  offset greatest(result_offset,0);
$$;

revoke all on function public.community_validation_context_v5(uuid,uuid,uuid)
  from public, anon, authenticated;
revoke all on function public.community_create_post_v5(uuid,uuid,text,text,text[],bigint[],text)
  from public, anon, authenticated;
revoke all on function public.community_update_post_v5(uuid,uuid,text,text,text[],bigint[],text)
  from public, anon, authenticated;
grant execute on function public.community_validation_context_v5(uuid,uuid,uuid)
  to service_role;
grant execute on function public.community_create_post_v5(uuid,uuid,text,text,text[],bigint[],text)
  to service_role;
grant execute on function public.community_update_post_v5(uuid,uuid,text,text,text[],bigint[],text)
  to service_role;
grant execute on function public.community_post_id_for_history_v5(uuid)
  to authenticated;
grant execute on function public.eligible_community_history_entries_v5()
  to authenticated;
grant execute on function public.community_feed_v5(text,bigint[],integer,integer,boolean)
  to anon, authenticated;

commit;
