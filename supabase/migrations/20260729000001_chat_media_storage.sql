-- Private Storage bucket for E2E-encrypted chat photo/video attachments.
-- Objects here are opaque AES-256-GCM ciphertext (see AttachmentPayload /
-- attachment_crypto.dart) -- Supabase never holds a decryption key, matching
-- the same "server never sees plaintext" guarantee as message_envelopes.
--
-- Path convention: <couple_id>/<message_id>. RLS reuses the couple
-- membership check already used elsewhere (public.is_couple_member), read
-- off the first path segment via storage.foldername(name).

insert into storage.buckets (id, name, public)
values ('chat-media', 'chat-media', false)
on conflict (id) do nothing;

create policy chat_media_select on storage.objects
  for select using (
    bucket_id = 'chat-media'
    and public.is_couple_member((storage.foldername(name))[1]::uuid)
  );

create policy chat_media_insert on storage.objects
  for insert with check (
    bucket_id = 'chat-media'
    and public.is_couple_member((storage.foldername(name))[1]::uuid)
  );
