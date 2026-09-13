-- Remove the presentation label from previously completed solo-trip titles.
-- Future solo journeys store only their destination name.

update public.travel_history_entries
set title = coalesce(
  nullif(
    trim(
      regexp_replace(
        title,
        '(^|[[:space:]]+)solo trip[[:space:]]*$',
        '',
        'i'
      )
    ),
    ''
  ),
  destination
)
where source_type = 'solo'
  and title ~* '(^|[[:space:]]+)solo trip[[:space:]]*$';
