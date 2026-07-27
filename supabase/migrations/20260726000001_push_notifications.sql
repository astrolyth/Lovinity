-- Push notifications, phase 1: device tokens, a generic content-free dispatch
-- primitive, and hooks from chat send + pairing activation.
--
-- E2E note: dispatch_push NEVER carries plaintext. Callers pass only a fixed
-- category ('chat' | 'pairing') and canned copy chosen by the DB, never
-- decrypted message content -- the server cannot read ciphertext, so there is
-- nothing else it could put in a push anyway.
--
-- Graceful degradation: private.push_config is manually seeded per
-- environment (function_url + dispatch_secret for the edge function that
-- actually calls APNs/FCM). Until it's seeded, dispatch_push is a silent
-- no-op and every RPC that calls it keeps working exactly as before.

------------------------------------------------------------------
-- pg_net: dispatch_push below uses net.http_post to call the push-dispatch
-- edge function. Already enabled on this stack, but ensure it explicitly so
-- a fresh/other project applying this migration doesn't silently lack it.
------------------------------------------------------------------
create extension if not exists pg_net with schema extensions;

------------------------------------------------------------------
-- private schema: server-only config, never exposed via PostgREST
------------------------------------------------------------------
create schema if not exists private;

create table if not exists private.push_config (
  id              boolean primary key default true,
  function_url    text,
  dispatch_secret text,
  constraint push_config_single_row check (id)
);

comment on table private.push_config is
  'Single-row, manually seeded per environment (function_url + dispatch_secret '
  'for the push-dispatch edge function). Empty/absent row => dispatch_push is '
  'a silent no-op; chat and pairing must keep working with no push config.';

revoke all on private.push_config from public, authenticated, anon;

------------------------------------------------------------------
-- public.device_push_tokens: one row per installed device
------------------------------------------------------------------
create table public.device_push_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.users(id) on delete cascade,
  token       text not null unique,
  platform    text not null check (platform in ('ios', 'android')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index device_push_tokens_user_idx on public.device_push_tokens(user_id);

alter table public.device_push_tokens enable row level security;

-- Writes only via register_push_token / unregister_push_token (security
-- definer) so token->user reassignment is validated server-side.
create policy device_push_tokens_select_own on public.device_push_tokens
  for select using (user_id = auth.uid());
create policy device_push_tokens_delete_own on public.device_push_tokens
  for delete using (user_id = auth.uid());

grant select, delete on public.device_push_tokens to authenticated;

------------------------------------------------------------------
-- register_push_token: upsert on token, reassigning ownership if the same
-- token shows up under a different account (device shared/re-logged-in) --
-- prevents a stale token leaking push notifications to the wrong account.
------------------------------------------------------------------
create or replace function public.register_push_token(
  p_token    text,
  p_platform text
)
returns void
language plpgsql volatile security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  insert into public.device_push_tokens (user_id, token, platform, updated_at)
  values (v_uid, p_token, p_platform, now())
  on conflict (token) do update
    set user_id    = excluded.user_id,
        platform   = excluded.platform,
        updated_at = now();
end;
$$;

grant execute on function public.register_push_token(text, text) to authenticated;

------------------------------------------------------------------
-- unregister_push_token: remove one token owned by the caller (logout /
-- opt-out). Silently affects zero rows if the token isn't the caller's.
------------------------------------------------------------------
create or replace function public.unregister_push_token(p_token text)
returns void
language plpgsql volatile security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  delete from public.device_push_tokens
   where token = p_token and user_id = v_uid;
end;
$$;

grant execute on function public.unregister_push_token(text) to authenticated;

------------------------------------------------------------------
-- dispatch_push: the one place any RPC/trigger goes to fire a push. Not
-- granted to authenticated -- callable only from other SECURITY DEFINER
-- functions/triggers running as the db owner. Content-free by construction:
-- callers pass a category + canned copy, never message plaintext.
--
-- Best-effort: config missing => no-op; pg_net error => swallowed. Must
-- never raise, so it can never break the caller's transaction.
------------------------------------------------------------------
create or replace function public.dispatch_push(
  p_user_id uuid,
  p_type    text,
  p_title   text,
  p_body    text
)
returns void
language plpgsql volatile security definer
set search_path = public
as $$
declare
  v_cfg private.push_config%rowtype;
begin
  select * into v_cfg from private.push_config limit 1;
  if not found or v_cfg.function_url is null then
    return;
  end if;

  begin
    perform net.http_post(
      url     := v_cfg.function_url,
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer ' || v_cfg.dispatch_secret
      ),
      body    := jsonb_build_object(
        'user_id', p_user_id,
        'type',    p_type,
        'title',   p_title,
        'body',    p_body
      )
    );
  exception when others then
    -- best-effort: never let push dispatch break the caller's transaction,
    -- but surface real operator misconfig (e.g. bad function_url, pg_net
    -- missing) instead of swallowing it silently -- config-absent above is
    -- the only case that's expected and stays a clean, silent `return`.
    raise warning 'dispatch_push: push delivery failed: %', sqlerrm;
  end;
end;
$$;

------------------------------------------------------------------
-- Recreate send_message adding p_notify_kind (trailing default, so the
-- existing 3-arg call site still resolves unchanged). All prior behaviour is
-- preserved byte-for-byte; only the notify step at the end is new.
------------------------------------------------------------------
drop function if exists public.send_message(integer, jsonb, uuid);

create or replace function public.send_message(
  p_sender_device_num integer,
  p_envelopes jsonb,
  p_message_id uuid default null,
  p_notify_kind text default 'message'
)
returns table (message_id uuid, created_at timestamptz)
language plpgsql volatile security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_cid    uuid;
  v_conv   uuid;
  v_msg    public.messages%rowtype;
  e        jsonb;
  v_spouse uuid;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select id into v_cid from public.couples
    where v_uid in (member_a, member_b) and status = 'active' limit 1;
  if v_cid is null then raise exception 'not_paired'; end if;

  select id into v_conv from public.conversations where couple_id = v_cid;
  if v_conv is null then
    insert into public.conversations (couple_id) values (v_cid) returning id into v_conv;
  end if;

  insert into public.messages (id, conversation_id, couple_id, sender_id, sender_device_num)
    values (coalesce(p_message_id, gen_random_uuid()), v_conv, v_cid, v_uid, p_sender_device_num)
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
      v_msg.id, v_cid, v_uid, p_sender_device_num,
      (e->>'recipient_id')::uuid, (e->>'recipient_device_num')::int,
      (e->>'cipher_type')::smallint, decode(e->>'ciphertext', 'hex')
    );
  end loop;

  update public.conversations set last_message_at = v_msg.created_at where id = v_conv;

  -- Notify the spouse exactly once per send (not per envelope, not the
  -- sender's own-device sync copies). p_notify_kind is a category hint
  -- chosen by the client, never message plaintext.
  if p_notify_kind <> 'silent' then
    select case when member_a = v_uid then member_b else member_a end
      into v_spouse
      from public.couples where id = v_cid;

    perform public.dispatch_push(
      v_spouse,
      'chat',
      'New message',
      case p_notify_kind
        when 'reaction' then 'Your partner reacted to a message'
        else 'New message from your partner'
      end
    );
  end if;

  message_id := v_msg.id; created_at := v_msg.created_at; return next;
end;
$$;

grant execute on function public.send_message(integer, jsonb, uuid, text) to authenticated;

------------------------------------------------------------------
-- Phase-2 pairing event: notify both members the moment a couple becomes
-- active. accept_pairing_invite INSERTs the couple row with status defaulting
-- to 'active' (see 20260715000001_roles.sql), so this MUST fire on INSERT, not
-- only UPDATE -- an UPDATE-only trigger would never fire for real pairings.
-- UPDATE is also covered so any future re-pairing/reactivation notifies too.
-- Demonstrates the generic dispatch_push path with a second event type.
------------------------------------------------------------------
create or replace function public.notify_pairing_active()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  -- On INSERT there is no OLD row; treat that as "was not active before".
  if new.status = 'active'
     and (tg_op = 'INSERT' or old.status is distinct from 'active') then
    perform public.dispatch_push(new.member_a, 'pairing', 'You''re connected',
      'You and your partner are now paired 💛');
    perform public.dispatch_push(new.member_b, 'pairing', 'You''re connected',
      'You and your partner are now paired 💛');
  end if;
  return new;
end;
$$;

drop trigger if exists on_couple_active on public.couples;
create trigger on_couple_active
  after insert or update on public.couples
  for each row execute function public.notify_pairing_active();
