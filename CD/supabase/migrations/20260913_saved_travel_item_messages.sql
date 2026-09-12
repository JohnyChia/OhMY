-- Allow Nova to remember an explicitly requested text message in addition to
-- places, links, and analysed attachments. This follow-up migration is kept
-- separate because the original saved-items migration may already be applied.
alter table if exists public.saved_travel_items
  drop constraint if exists saved_travel_items_source_type_check;

alter table if exists public.saved_travel_items
  add constraint saved_travel_items_source_type_check
  check (source_type in ('image', 'file', 'link', 'place', 'message'));
