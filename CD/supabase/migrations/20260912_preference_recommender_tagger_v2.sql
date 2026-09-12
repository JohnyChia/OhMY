-- Tagger V2: change-aware, atomic replacement of derived place tags.
-- The backend invokes this function with the service-role client only.

alter table public.places
    add column if not exists tag_fingerprint text,
    add column if not exists tag_language_summary jsonb not null default '{}'::jsonb,
    add column if not exists tag_evidence_summary jsonb not null default '{}'::jsonb;

alter table public.place_tags
    add column if not exists average_score double precision not null default 0,
    add column if not exists evidence_details jsonb not null default '{}'::jsonb,
    add column if not exists tagger_version text;

create index if not exists places_retagging_idx
    on public.places (tagger_version, id);

create or replace function public.replace_place_tags_v2(
    p_place jsonb,
    p_tags jsonb,
    p_tagger_version text,
    p_fingerprint text,
    p_language_summary jsonb default '{}'::jsonb,
    p_evidence_summary jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_place_id bigint;
    v_previous_fingerprint text;
    v_changed boolean;
begin
    if nullif(trim(p_place->>'google_place_id'), '') is null then
        raise exception 'google_place_id is required';
    end if;
    if nullif(trim(p_tagger_version), '') is null then
        raise exception 'tagger version is required';
    end if;
    if jsonb_typeof(coalesce(p_tags, '[]'::jsonb)) <> 'array' then
        raise exception 'p_tags must be a JSON array';
    end if;

    select id, tag_fingerprint
      into v_place_id, v_previous_fingerprint
      from public.places
     where google_place_id = p_place->>'google_place_id'
     for update;

    v_changed := v_place_id is null
        or v_previous_fingerprint is distinct from p_fingerprint;

    insert into public.places (
        google_place_id, name, description, latitude, longitude,
        formatted_address, rating, google_maps_uri, primary_type,
        place_types, photo_references, google_data_cached_at,
        google_data_expires_at, tags_updated_at, tagger_version,
        tag_status, tag_fingerprint, tag_language_summary,
        tag_evidence_summary
    ) values (
        p_place->>'google_place_id',
        coalesce(nullif(p_place->>'name', ''), 'Unknown place'),
        nullif(p_place->>'description', ''),
        nullif(p_place->>'latitude', '')::double precision,
        nullif(p_place->>'longitude', '')::double precision,
        nullif(p_place->>'formatted_address', ''),
        nullif(p_place->>'rating', '')::double precision,
        nullif(p_place->>'google_maps_uri', ''),
        nullif(p_place->>'primary_type', ''),
        coalesce(
            array(select jsonb_array_elements_text(coalesce(p_place->'place_types', '[]'::jsonb))),
            '{}'::text[]
        ),
        coalesce(p_place->'photo_references', '[]'::jsonb),
        coalesce((p_place->>'google_data_cached_at')::timestamptz, now()),
        (p_place->>'google_data_expires_at')::timestamptz,
        now(),
        p_tagger_version,
        'processed',
        p_fingerprint,
        coalesce(p_language_summary, '{}'::jsonb),
        coalesce(p_evidence_summary, '{}'::jsonb)
    )
    on conflict (google_place_id) do update set
        name = excluded.name,
        description = excluded.description,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        formatted_address = excluded.formatted_address,
        rating = excluded.rating,
        google_maps_uri = excluded.google_maps_uri,
        primary_type = excluded.primary_type,
        place_types = excluded.place_types,
        photo_references = excluded.photo_references,
        google_data_cached_at = excluded.google_data_cached_at,
        google_data_expires_at = excluded.google_data_expires_at,
        tags_updated_at = now(),
        tagger_version = excluded.tagger_version,
        tag_status = excluded.tag_status,
        tag_fingerprint = excluded.tag_fingerprint,
        tag_language_summary = excluded.tag_language_summary,
        tag_evidence_summary = excluded.tag_evidence_summary
    returning id into v_place_id;

    if v_changed then
        insert into public.tags (name, tag_type)
        select tag->>'name', tag->>'tagType'
          from jsonb_array_elements(coalesce(p_tags, '[]'::jsonb)) tag
         where nullif(trim(tag->>'name'), '') is not null
        on conflict (name) do update set tag_type = excluded.tag_type;

        -- Delete even when V2 produces no assignments. This is what prevents
        -- stale V1 relationships from surviving a zero-tag result.
        delete from public.place_tags where place_id = v_place_id;

        insert into public.place_tags (
            place_id, tag_id, confidence, evidence_count,
            supporting_reviews, source, updated_at, average_score,
            evidence_details, tagger_version
        )
        select
            v_place_id,
            t.id,
            coalesce((tag->>'confidence')::double precision, 0),
            coalesce((tag->>'evidenceCount')::integer, 0),
            coalesce((tag->>'supportingReviews')::integer, 0),
            coalesce(nullif(tag->>'source', ''), 'rule_based_reviews'),
            now(),
            coalesce((tag->>'averageScore')::double precision, 0),
            coalesce(tag->'evidenceDetails', '{}'::jsonb),
            p_tagger_version
          from jsonb_array_elements(coalesce(p_tags, '[]'::jsonb)) tag
          join public.tags t on t.name = tag->>'name';
    else
        -- The assignments are identical, but record that they were verified
        -- by the latest algorithm without rewriting the relationships.
        update public.place_tags
           set tagger_version = p_tagger_version,
               updated_at = now()
         where place_id = v_place_id;
    end if;

    return jsonb_build_object(
        'place_id', v_place_id,
        'changed', v_changed,
        'tag_count', jsonb_array_length(coalesce(p_tags, '[]'::jsonb)),
        'tagger_version', p_tagger_version
    );
end;
$$;

revoke all on function public.replace_place_tags_v2(
    jsonb, jsonb, text, text, jsonb, jsonb
) from public, anon, authenticated;
grant execute on function public.replace_place_tags_v2(
    jsonb, jsonb, text, text, jsonb, jsonb
) to service_role;

comment on function public.replace_place_tags_v2(
    jsonb, jsonb, text, text, jsonb, jsonb
) is 'Atomically replaces derived place tags only when their stable V2 fingerprint changes.';
