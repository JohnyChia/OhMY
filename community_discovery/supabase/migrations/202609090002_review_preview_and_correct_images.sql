-- Community Discovery-only changes. Existing trip, profile, place, and tags
-- tables are intentionally not altered.
begin;

create or replace function public.community_review_draft(
  post_title text,
  post_description text,
  expected_destination text,
  expected_attraction text
) returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  combined_text text := lower(concat_ws(' ', post_title, post_description));
  destination_text text := lower(trim(coalesce(expected_destination, '')));
  attraction_text text := lower(trim(coalesce(expected_attraction, '')));
  matched boolean := false;
  review_score integer := 0;
  review_reason text;
begin
  if length(trim(coalesce(post_title, ''))) < 3 then
    return jsonb_build_object('approved', false, 'score', 0,
      'reason', 'Rejected: title must contain at least 3 characters.');
  end if;
  if length(trim(coalesce(post_description, ''))) < 10 then
    return jsonb_build_object('approved', false, 'score', 0,
      'reason', 'Rejected: description must contain at least 10 characters.');
  end if;

  if attraction_text <> '' and combined_text like '%' || attraction_text || '%' then
    matched := true;
    review_score := 100;
    review_reason := 'Approved: the post mentions the completed trip attraction.';
  elsif destination_text <> '' and combined_text like '%' || destination_text || '%' then
    matched := true;
    review_score := 90;
    review_reason := 'Approved: the post mentions the completed trip destination.';
  elsif public.community_text_matches_trip(
    post_title, post_description, expected_destination, expected_attraction
  ) then
    matched := true;
    review_score := 70;
    review_reason := 'Approved: a meaningful destination keyword matches the completed trip.';
  else
    review_reason := 'Rejected: the content does not mention Kuala Lumpur or the completed trip attraction.';
  end if;

  return jsonb_build_object(
    'approved', matched, 'score', review_score, 'reason', review_reason
  );
end;
$$;

grant execute on function public.community_review_draft(text,text,text,text)
  to anon, authenticated;

update public.community_posts
set image_url = case id
  when '6f5a3f36-7d79-4d9d-a101-000000000001'::uuid then 'https://commons.wikimedia.org/wiki/Special:Redirect/file/Kwai%20Chai%20Hong%203.jpg?width=1200'
  when '6f5a3f36-7d79-4d9d-a101-000000000002'::uuid then 'https://commons.wikimedia.org/wiki/Special:Redirect/file/Petronas%20Towers%20-%20Kuala%20Lumpur%20%2818145552928%29.jpg?width=1200'
  when '6f5a3f36-7d79-4d9d-a101-000000000003'::uuid then 'https://commons.wikimedia.org/wiki/Special:Redirect/file/The%20Merdeka%20Square%2CKL%20Malaysia%20.jpg?width=1200'
  when '6f5a3f36-7d79-4d9d-a101-000000000004'::uuid then 'https://commons.wikimedia.org/wiki/Special:Redirect/file/Central%20Market%20Kuala%20Lumpur.jpg?width=1200'
  when '6f5a3f36-7d79-4d9d-a101-000000000005'::uuid then 'https://commons.wikimedia.org/wiki/Special:Redirect/file/Jalan%20Alor%20-%20Kuala%20Lumpur.jpg?width=1200'
  when '6f5a3f36-7d79-4d9d-a101-000000000006'::uuid then 'https://commons.wikimedia.org/wiki/Special:Redirect/file/KLCC%20Park%202010.jpg?width=1200'
  when '6f5a3f36-7d79-4d9d-a101-000000000007'::uuid then 'https://commons.wikimedia.org/wiki/Special:Redirect/file/Bukit%20Bintang%20in%20Kuala%20Lumpur%2C%20Malaysia%20-%2008.jpg?width=1200'
  else image_url
end,
updated_at = now()
where is_seed = true
  and id between '6f5a3f36-7d79-4d9d-a101-000000000001'::uuid
             and '6f5a3f36-7d79-4d9d-a101-000000000007'::uuid;

commit;
