-- Restrict only the Community Discovery image bucket.
update storage.buckets
set file_size_limit = 10485760,
    allowed_mime_types = array['image/jpeg', 'image/png']::text[]
where id = 'community-posts';
