-- Wall photo/video posts: new sources, media-only items, private wall-media bucket.
-- Paths: <couple_id>/<item_id>/media.jpg|media.mp4, video thumb <couple_id>/<item_id>/thumb.jpg

alter table public.feed_items
  drop constraint feed_items_source_check,
  drop constraint feed_items_has_content,
  add constraint feed_items_source_check
    check (source is null or source in
      ('youtube', 'instagram', 'tiktok', 'article', 'note', 'photo', 'video')),
  add constraint feed_items_has_content
    check (url is not null
           or (note is not null and length(btrim(note)) > 0)
           or media_url is not null),
  add constraint feed_items_media_mime_check
    check (media_mime is null
           or media_mime in ('image/jpeg', 'video/mp4', 'video/quicktime'));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('wall-media', 'wall-media', false, 52428800,
        array['image/jpeg', 'video/mp4', 'video/quicktime'])
on conflict (id) do nothing;

create policy wall_media_select on storage.objects
  for select using (
    bucket_id = 'wall-media'
    and public.is_couple_member((storage.foldername(name))[1]::uuid)
  );

create policy wall_media_insert on storage.objects
  for insert with check (
    bucket_id = 'wall-media'
    and public.is_couple_member((storage.foldername(name))[1]::uuid)
  );

create policy wall_media_delete on storage.objects
  for delete using (
    bucket_id = 'wall-media'
    and owner = auth.uid()
    and public.is_couple_member((storage.foldername(name))[1]::uuid)
  );
