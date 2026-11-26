-- Pairing codes: unguessable and not brute-forceable.
--
-- 1. generate_invite_code drew from random(), a seedable non-crypto PRNG.
--    It now draws from pgcrypto's gen_random_bytes, with rejection sampling
--    so every one of the 30 symbols is equally likely (256 % 30 != 0).
-- 2. accept_pairing_invite let one account try codes without limit. A wrong
--    code is now logged in private.invite_attempts and an account gets
--    10 wrong codes per hour. The wrong-code path RETURNS NULL instead of
--    raising, because a raise would roll back the logged attempt; the client
--    (PairingRepository.acceptInvite) maps a null row to invite_not_found.

create table if not exists private.invite_attempts (
  user_id uuid not null references auth.users (id) on delete cascade,
  at      timestamptz not null default now()
);
create index if not exists invite_attempts_user_at
  on private.invite_attempts (user_id, at);

create or replace function public.generate_invite_code()
returns text
language plpgsql
set search_path = ''
as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTVWXYZ23456789';
  result   text := '';
  b        integer;
begin
  while length(result) < 6 loop
    b := get_byte(extensions.gen_random_bytes(1), 0);
    if b < 240 then  -- 240 = 8 * 30, the largest unbiased range
      result := result || substr(alphabet, 1 + b % 30, 1);
    end if;
  end loop;
  return result;
end;
$$;
revoke execute on function public.generate_invite_code() from public, anon, authenticated;

create or replace function public.accept_pairing_invite(p_code text)
returns public.couples
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_invite  public.pairing_invites%rowtype;
  v_a       uuid;
  v_b       uuid;
  v_couple  public.couples%rowtype;
  v_my_gender      text;
  v_inviter_gender text;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  if (select count(*) from private.invite_attempts
       where user_id = v_uid and at > now() - interval '1 hour') >= 10 then
    raise exception 'too_many_attempts';
  end if;

  select * into v_invite from public.pairing_invites
   where code = upper(trim(p_code)) for update;
  if not found then
    insert into private.invite_attempts (user_id) values (v_uid);
    delete from private.invite_attempts where at < now() - interval '1 day';
    return null;  -- not a raise: that would roll back the attempt above
  end if;
  if v_invite.consumed_at is not null then raise exception 'invite_already_used'; end if;
  if v_invite.expires_at < now() then raise exception 'invite_expired'; end if;
  if v_invite.inviter_id = v_uid then raise exception 'cannot_pair_with_self'; end if;

  if v_invite.inviter_id < v_uid then
    v_a := v_invite.inviter_id; v_b := v_uid;
  else
    v_a := v_uid; v_b := v_invite.inviter_id;
  end if;

  -- Two accepts touching the same user (A accepts B's invite while C accepts
  -- A's) must not both pass the "not already paired" checks below. Lock both
  -- users in a fixed order so concurrent calls serialize without deadlock.
  perform pg_advisory_xact_lock(hashtext('pair:' || v_a::text));
  perform pg_advisory_xact_lock(hashtext('pair:' || v_b::text));

  if exists (select 1 from public.couples
             where v_uid in (member_a, member_b) and status = 'active') then
    raise exception 'already_paired';
  end if;
  if exists (select 1 from public.couples
             where v_invite.inviter_id in (member_a, member_b) and status = 'active') then
    raise exception 'inviter_already_paired';
  end if;

  select gender into v_my_gender      from public.users where id = v_uid;
  select gender into v_inviter_gender from public.users where id = v_invite.inviter_id;
  if v_my_gender is null or v_inviter_gender is null then
    raise exception 'gender_required';
  end if;
  if v_my_gender = v_inviter_gender then
    raise exception 'same_gender_pairing';
  end if;

  update public.pairing_invites
     set consumed_at = now(), consumed_by = v_uid
   where code = v_invite.code;

  insert into public.couples (member_a, member_b)
       values (v_a, v_b) returning * into v_couple;
  return v_couple;
end;
$$;

