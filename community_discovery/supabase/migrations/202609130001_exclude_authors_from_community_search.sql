begin;

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
      p.attraction_name,p.location_name,p.description))
      like '%'||lower(trim(search_query))||'%'
      or exists(select 1 from public.community_post_tags pt
        join public.tags t on t.id=pt.tag_id
        where pt.post_id=p.id
          and lower(t.name) like '%'||lower(trim(search_query))||'%'))
  order by p.created_at desc
  limit least(greatest(result_limit,1),100)
  offset greatest(result_offset,0);
$$;

revoke all on function public.community_feed_v5(text,bigint[],integer,integer,boolean)
  from public;
grant execute on function public.community_feed_v5(text,bigint[],integer,integer,boolean)
  to anon, authenticated;

commit;
