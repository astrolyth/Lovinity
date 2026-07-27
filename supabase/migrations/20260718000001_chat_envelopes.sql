-- Chat: restructure messages to logical-only + per-device ciphertext envelopes.
-- Chat has never shipped, so messages has no production rows to preserve.

alter table public.messages
  drop column if exists ciphertext,
  drop column if exists cipher_type,
  drop column if exists device_id,
  drop column if exists recipient_id,
  drop column if exists attachment_url,
  drop column if exists attachment_mime,
  drop column if exists attachment_bytes,
  drop column if exists ephemeral_until,
  drop column if exists reply_to,
  add column if not exists sender_device_num integer not null default 1;
alter table public.messages alter column sender_device_num drop default;

create table public.message_envelopes (
  id                   uuid primary key default gen_random_uuid(),
  message_id           uuid not null references public.messages(id) on delete cascade,
  couple_id            uuid not null references public.couples(id) on delete cascade,
  -- Denormalized sender address: an inbound envelope may be from the spouse OR
  -- from the recipient's OWN other device (multi-device sync), so the reader
  -- must know the sender's (user, device) to pick the right Signal session.
  -- message_envelopes is streamed on its own (realtime can't join messages).
  sender_id            uuid not null references public.users(id) on delete cascade,
  sender_device_num    integer not null,
  recipient_id         uuid not null references public.users(id) on delete cascade,
  recipient_device_num integer not null,
  cipher_type          smallint not null, -- 3 = prekey (X3DH first), 2 = message (per libsignal)
  ciphertext           bytea not null,
  created_at           timestamptz not null default now(),
  fetched_at           timestamptz
);
create index message_envelopes_recipient_idx
  on public.message_envelopes(recipient_id, fetched_at);
create index message_envelopes_message_idx on public.message_envelopes(message_id);

alter table public.message_envelopes enable row level security;

-- No direct insert policy: envelopes may only be written via the SECURITY
-- DEFINER send_message() RPC, which validates recipient_id/sender_id are
-- both members of the sender's couple before inserting.
-- A device reads/deletes only its own envelopes.
create policy envelopes_read_own on public.message_envelopes
  for select using (recipient_id = auth.uid());
create policy envelopes_delete_own on public.message_envelopes
  for delete using (recipient_id = auth.uid());

grant select, delete on public.message_envelopes to authenticated;

-- Atomic send: message row + N envelopes + bump conversation.
create or replace function public.send_message(
  p_sender_device_num integer,
  p_envelopes jsonb
)
returns table (message_id uuid, created_at timestamptz)
language plpgsql volatile security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_cid  uuid;
  v_conv uuid;
  v_msg  public.messages%rowtype;
  e      jsonb;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select id into v_cid from public.couples
    where v_uid in (member_a, member_b) and status = 'active' limit 1;
  if v_cid is null then raise exception 'not_paired'; end if;

  select id into v_conv from public.conversations where couple_id = v_cid;
  if v_conv is null then
    insert into public.conversations (couple_id) values (v_cid) returning id into v_conv;
  end if;

  insert into public.messages (conversation_id, couple_id, sender_id, sender_device_num)
    values (v_conv, v_cid, v_uid, p_sender_device_num)
    returning * into v_msg;

  for e in select * from jsonb_array_elements(p_envelopes) loop
    if (e->>'recipient_id')::uuid not in (
      select member_a from public.couples where id = v_cid
      union
      select member_b from public.couples where id = v_cid
    ) then
      raise exception 'invalid_recipient';
    end if;

    insert into public.message_envelopes
      (message_id, couple_id, sender_id, sender_device_num,
       recipient_id, recipient_device_num, cipher_type, ciphertext)
    values (
      v_msg.id, v_cid,
      v_uid, p_sender_device_num,
      (e->>'recipient_id')::uuid,
      (e->>'recipient_device_num')::int,
      (e->>'cipher_type')::smallint,
      decode(e->>'ciphertext', 'hex')
    );
  end loop;

  update public.conversations set last_message_at = v_msg.created_at where id = v_conv;

  message_id := v_msg.id; created_at := v_msg.created_at; return next;
end;
$$;
grant execute on function public.send_message(integer, jsonb) to authenticated;

-- Receipts: only the recipient side (a couple member who is not the sender) may set them.
create or replace function public.mark_delivered(p_message_id uuid)
returns void language plpgsql volatile security definer set search_path = public as $$
begin
  update public.messages set delivered_at = now()
   where id = p_message_id and delivered_at is null
     and public.is_couple_member(couple_id) and sender_id <> auth.uid();
end; $$;

create or replace function public.mark_read(p_message_id uuid)
returns void language plpgsql volatile security definer set search_path = public as $$
begin
  update public.messages set read_at = now(), delivered_at = coalesce(delivered_at, now())
   where id = p_message_id and read_at is null
     and public.is_couple_member(couple_id) and sender_id <> auth.uid();
end; $$;

grant execute on function public.mark_delivered(uuid) to authenticated;
grant execute on function public.mark_read(uuid) to authenticated;

-- Realtime: the recipient streams its envelopes; the sender streams receipt updates.
do $$ begin
  begin alter publication supabase_realtime add table public.message_envelopes;
  exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.messages;
  exception when duplicate_object then null; end;
end $$;
