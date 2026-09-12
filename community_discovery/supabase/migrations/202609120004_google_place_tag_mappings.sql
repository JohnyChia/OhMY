-- Community Discovery: map current Google Places types to existing shared tags.
-- The shared tags table is read only; only Community-owned rules and post links
-- are changed.
begin;

insert into public.community_location_tag_rules(tag_id, place_type, weight)
select t.id, mapping.place_type, mapping.weight
from (values
  ('Educational', 'university', 7.0),
  ('Educational', 'educational_institution', 7.0),
  ('Educational', 'school', 6.0),
  ('Educational', 'library', 5.0),
  ('Landmark', 'tourist_attraction', 5.0),
  ('Landmark', 'monument', 6.0),
  ('Historical Landmark', 'historical_place', 7.0),
  ('Museum', 'museum', 7.0),
  ('Park', 'state_park', 6.0),
  ('Nature', 'hiking_area', 6.0),
  ('Nature', 'beach', 6.0),
  ('Cafe', 'coffee_shop', 7.0),
  ('Shopping', 'store', 4.0),
  ('Entertainment', 'amusement_center', 6.0),
  ('Entertainment', 'amusement_park', 7.0),
  ('Entertainment', 'movie_theater', 6.0),
  ('Entertainment', 'night_club', 6.0),
  ('Religious Heritage', 'buddhist_temple', 6.0)
) as mapping(tag_name, place_type, weight)
join public.tags t on lower(t.name) = lower(mapping.tag_name)
on conflict do nothing;

-- Correct existing TAR UMT posts that previously received the generic
-- Cultural Experience fallback before university mappings existed.
delete from public.community_post_tags pt
using public.community_posts p, public.tags t
where pt.post_id = p.id
  and pt.tag_id = t.id
  and lower(t.name) = 'cultural experience'
  and lower(p.attraction_name || ' ' || p.location_name) ~ 'tar[[:space:]]*umt';

insert into public.community_post_tags(post_id, tag_id)
select p.id, t.id
from public.community_posts p
join public.tags t on lower(t.name) = 'educational'
where lower(p.attraction_name || ' ' || p.location_name) ~ 'tar[[:space:]]*umt'
on conflict do nothing;

commit;
