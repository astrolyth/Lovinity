-- Plain psql assertion script for 20261118000001_invite_code_hardening.sql
-- and 20261118000002_chat_media_size_limit.sql. Same conventions as
-- security_hardening_test.sql: DO blocks RAISE on failure, fixtures live in
-- one transaction that is rolled back.
--
-- Run with:
--   PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f supabase/tests/invite_code_hardening_test.sql

begin;

insert into auth.users (id) values ('99999999-0000-0000-0000-00000000000a');

-- 1. Codes are 6 symbols from the unambiguous alphabet.
do $$
declare c text;
begin
  for i in 1..200 loop
    c := public.generate_invite_code();
    if c !~ '^[ABCDEFGHJKMNPQRSTVWXYZ23456789]{6}$' then
      raise exception 'FAIL: bad invite code %', c;
    end if;
  end loop;
  raise notice 'PASS: invite codes use the 6-symbol alphabet';
end $$;

set local role authenticated;
set local request.jwt.claim.sub = '99999999-0000-0000-0000-00000000000a';

-- 2. A wrong code returns no couple (not a raise), ten times.
do $$
begin
  for i in 1..10 loop
    if (public.accept_pairing_invite('NOPE' || i)).id is not null then
      raise exception 'FAIL: wrong code returned a couple';
    end if;
  end loop;
  raise notice 'PASS: wrong codes return no couple';
end $$;

-- 3. The 11th try within the hour is refused.
do $$
begin
  perform public.accept_pairing_invite('NOPE11');
  raise exception 'FAIL: 11th wrong code was not rate-limited';
exception when raise_exception then
  if sqlerrm <> 'too_many_attempts' then raise; end if;
  raise notice 'PASS: 11th wrong code hits too_many_attempts';
end $$;

-- 4. Users can't see or clear their attempt log.
do $$
begin
  perform 1 from private.invite_attempts;
  raise exception 'FAIL: authenticated can read private.invite_attempts';
exception when insufficient_privilege then
  raise notice 'PASS: invite_attempts is not readable by users';
end $$;
reset role;

-- 5. chat-media has a size cap.
do $$
begin
  if (select file_size_limit from storage.buckets where id = 'chat-media') is null then
    raise exception 'FAIL: chat-media has no file_size_limit';
  end if;
  raise notice 'PASS: chat-media is size-capped';
end $$;

rollback;
