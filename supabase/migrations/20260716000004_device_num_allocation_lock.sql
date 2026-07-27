------------------------------------------------------------------
-- register_device_bundle: serialize per-user device_num allocation
--
-- The previous version (20260716000003) read
--   select coalesce(max(device_num), 0) + 1 into v_num ...
-- with no lock. If two brand-new device_ids for the same user register
-- concurrently (e.g. onboarding finishes on phone and Mac at nearly the
-- same moment), both transactions can read the same max(device_num)
-- before either commits, so both compute the same v_num. The upsert's
-- conflict target is (user_id, device_id), so the second insert does not
-- take the upsert path -- it collides with the separate unique index
-- signal_bundles_user_devicenum_idx (user_id, device_num) and raises a
-- duplicate-key error instead of allocating the next number.
--
-- Fix: take a per-user advisory lock, scoped to this transaction, before
-- reading the current max. Concurrent callers for the same user_id then
-- serialize on the max()+upsert sequence, so each gets a distinct
-- device_num. Do NOT remove this lock to "simplify" the function -- the
-- race it closes is real and was observed as a review finding.
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

  -- Serialize device_num allocation per user for the rest of this
  -- transaction. See the comment above for why this is required.
  perform pg_advisory_xact_lock(hashtext(v_uid::text));

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
