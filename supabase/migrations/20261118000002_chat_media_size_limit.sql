-- chat-media had no size cap (wall-media caps at 50 MB). Chat uploads are
-- E2E-encrypted blobs (application/octet-stream), so the MIME list stays open
-- and only the size is bounded. MediaPicker allows 50 MiB of plaintext
-- (maxVideoBytes); 55 MiB leaves room for the encryption envelope.
update storage.buckets set file_size_limit = 57671680 where id = 'chat-media';
