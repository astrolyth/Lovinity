-- Split roster discovery from the handshake.
--
-- fetch_prekey_bundles(user) consumed a one-time prekey for EVERY device on
-- every call, and encryptFor called it on every send just to learn the device
-- roster -- so an established conversation drained the prekey pool. Roster
-- lookup must consume nothing; only an actual X3DH handshake may consume.

drop function if exists public.fetch_prekey_bundles(uuid);

-- Non-consuming roster.
create or replace function public.list_devices(p_target_user uuid)
returns table (device_num integer)
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  if p_target_user <> v_uid and not exists (
    select 1 from public.couples c
     where c.status = 'active'
       and v_uid in (c.member_a, c.member_b)
       and p_target_user in (c.member_a, c.member_b)
  ) then
    raise exception 'not_permitted';
  end if;

  return query
    select b.device_num
      from public.signal_key_bundles b
     where b.user_id = p_target_user
       and b.device_num is not null
     order by b.device_num;
end;
$$;

grant execute on function public.list_devices(uuid) to authenticated;

-- Single-device bundle; consumes exactly one one-time prekey for THAT device.
create or replace function public.fetch_prekey_bundle(
  p_target_user uuid,
  p_device_num  integer
)
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

  if p_target_user <> v_uid and not exists (
    select 1 from public.couples c
     where c.status = 'active'
       and v_uid in (c.member_a, c.member_b)
       and p_target_user in (c.member_a, c.member_b)
  ) then
    raise exception 'not_permitted';
  end if;

  select b.device_num, b.registration_id, b.identity_pub,
         b.signed_prekey_id, b.signed_prekey_pub, b.signed_prekey_sig
    into r
    from public.signal_key_bundles b
   where b.user_id = p_target_user and b.device_num = p_device_num;

  if not found then return; end if;

  update public.signal_one_time_prekeys o
     set consumed_at = now()
   where o.user_id = p_target_user
     and o.device_num = p_device_num
     and o.prekey_id = (
       select o2.prekey_id from public.signal_one_time_prekeys o2
        where o2.user_id = p_target_user
          and o2.device_num = p_device_num
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
end;
$$;

grant execute on function public.fetch_prekey_bundle(uuid, integer) to authenticated;
