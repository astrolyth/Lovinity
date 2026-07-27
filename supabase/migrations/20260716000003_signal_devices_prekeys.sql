-- libsignal addresses are (name, int deviceId); device_id is a uuid, so each
-- device also needs a small integer number, unique per user (1 = first device).
alter table public.signal_key_bundles
  add column if not exists device_num integer;

create unique index if not exists signal_bundles_user_devicenum_idx
  on public.signal_key_bundles(user_id, device_num);

-- One-time prekeys must be consumed atomically; a jsonb array cannot be popped
-- safely and handing the same prekey to two senders breaks the handshake.
create table if not exists public.signal_one_time_prekeys (
  user_id     uuid not null references public.users(id) on delete cascade,
  device_num  integer not null,
  prekey_id   integer not null,
  pub         bytea not null,
  consumed_at timestamptz,
  primary key (user_id, device_num, prekey_id)
);

create index if not exists signal_otp_unconsumed_idx
  on public.signal_one_time_prekeys(user_id, device_num)
  where consumed_at is null;

alter table public.signal_one_time_prekeys enable row level security;

-- Own rows: full control (upload/replenish). Spouse: no direct select --
-- prekeys are handed out only via fetch_prekey_bundles (security definer).
create policy signal_otp_own on public.signal_one_time_prekeys
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, update, delete on public.signal_one_time_prekeys to authenticated;

-- Correct the documented cipher_type values: libsignal uses
-- CiphertextMessage.whisperType = 2 and prekeyType = 3.
comment on column public.messages.cipher_type is
  'libsignal CiphertextMessage type: 3 = prekey (X3DH first message), 2 = whisper (subsequent)';

------------------------------------------------------------------
-- register_device_bundle: allocate this device's number + upsert its bundle
------------------------------------------------------------------
create or replace function public.register_device_bundle(
  p_device_id         text,
  p_registration_id   integer,
  p_identity_pub      bytea,
  p_signed_prekey_id  integer,
  p_signed_prekey_pub bytea,
  p_signed_prekey_sig bytea
)
returns integer
language plpgsql volatile security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_num integer;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  -- Reuse this device's number if it re-registers; otherwise allocate next.
  select device_num into v_num from public.signal_key_bundles
   where user_id = v_uid and device_id = p_device_id;

  if v_num is null then
    select coalesce(max(device_num), 0) + 1 into v_num
      from public.signal_key_bundles where user_id = v_uid;
  end if;

  insert into public.signal_key_bundles (
    user_id, device_id, device_num, registration_id, identity_pub,
    signed_prekey_id, signed_prekey_pub, signed_prekey_sig, updated_at
  ) values (
    v_uid, p_device_id, v_num, p_registration_id, p_identity_pub,
    p_signed_prekey_id, p_signed_prekey_pub, p_signed_prekey_sig, now()
  )
  on conflict (user_id, device_id) do update set
    device_num       = excluded.device_num,
    registration_id  = excluded.registration_id,
    identity_pub     = excluded.identity_pub,
    signed_prekey_id = excluded.signed_prekey_id,
    signed_prekey_pub= excluded.signed_prekey_pub,
    signed_prekey_sig= excluded.signed_prekey_sig,
    updated_at       = now();

  return v_num;
end;
$$;

grant execute on function public.register_device_bundle(text,integer,bytea,integer,bytea,bytea) to authenticated;

------------------------------------------------------------------
-- fetch_prekey_bundles: one bundle per device of the target, consuming one
-- one-time prekey each. Target may be the caller or the caller's spouse.
------------------------------------------------------------------
create or replace function public.fetch_prekey_bundles(p_target_user uuid)
returns table (
  device_num          integer,
  registration_id     integer,
  identity_pub        bytea,
  signed_prekey_id    integer,
  signed_prekey_pub   bytea,
  signed_prekey_sig   bytea,
  one_time_prekey_id  integer,
  one_time_prekey_pub bytea
)
language plpgsql volatile security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  r     record;
  v_otp record;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  -- Self, or a member of the caller's active couple.
  if p_target_user <> v_uid and not exists (
    select 1 from public.couples c
     where c.status = 'active'
       and v_uid in (c.member_a, c.member_b)
       and p_target_user in (c.member_a, c.member_b)
  ) then
    raise exception 'not_permitted';
  end if;

  for r in
    select b.device_num, b.registration_id, b.identity_pub,
           b.signed_prekey_id, b.signed_prekey_pub, b.signed_prekey_sig
      from public.signal_key_bundles b
     where b.user_id = p_target_user and b.device_num is not null
  loop
    -- Atomically claim one unused one-time prekey for this device.
    update public.signal_one_time_prekeys o
       set consumed_at = now()
     where o.user_id = p_target_user
       and o.device_num = r.device_num
       and o.prekey_id = (
         select o2.prekey_id from public.signal_one_time_prekeys o2
          where o2.user_id = p_target_user
            and o2.device_num = r.device_num
            and o2.consumed_at is null
          order by o2.prekey_id
          limit 1
          for update skip locked
       )
    returning o.prekey_id, o.pub into v_otp;

    device_num          := r.device_num;
    registration_id     := r.registration_id;
    identity_pub        := r.identity_pub;
    signed_prekey_id    := r.signed_prekey_id;
    signed_prekey_pub   := r.signed_prekey_pub;
    signed_prekey_sig   := r.signed_prekey_sig;
    one_time_prekey_id  := v_otp.prekey_id;   -- null when exhausted
    one_time_prekey_pub := v_otp.pub;
    return next;
    v_otp := null;
  end loop;
end;
$$;

grant execute on function public.fetch_prekey_bundles(uuid) to authenticated;
