-- Plain psql assertion script for 20261116000003_letters_and_gender_guards.sql.
-- Same conventions as security_hardening_test.sql: DO blocks RAISE on
-- failure, everything rolls back, auth.uid() simulated via jwt claim.
--
-- Run with:
--   PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f supabase/tests/letters_gender_guards_test.sql

begin;

-- Fixtures: A (husband) + B (wife) paired; D unpaired.
insert into auth.users (id) values
  ('77777777-0000-0000-0000-00000000000a'),
  ('77777777-0000-0000-0000-00000000000b'),
  ('77777777-0000-0000-0000-00000000000d');
update public.users set gender = 'male'
  where id in ('77777777-0000-0000-0000-00000000000a', '77777777-0000-0000-0000-00000000000d');
update public.users set gender = 'female'
  where id = '77777777-0000-0000-0000-00000000000b';
insert into public.couples (id, member_a, member_b)
values ('77777777-1111-0000-0000-000000000001',
        '77777777-0000-0000-0000-00000000000a', '77777777-0000-0000-0000-00000000000b');

-- A letter from A to B that has already unlocked (created in the past so the
-- unlock_at > created_at check holds).
insert into public.future_letters
  (id, couple_id, author_id, recipient_id, body_ciphertext, unlock_at, created_at)
values ('77777777-2222-0000-0000-000000000001', '77777777-1111-0000-0000-000000000001',
        '77777777-0000-0000-0000-00000000000a', '77777777-0000-0000-0000-00000000000b',
        '\x01'::bytea, now() - interval '1 day', now() - interval '2 days');

set role authenticated;
set local request.jwt.claim.sub = '77777777-0000-0000-0000-00000000000b';

-- 1. The recipient can still mark an unlocked letter as opened.
do $$
declare n int;
begin
  update public.future_letters set unlocked_at = now()
   where id = '77777777-2222-0000-0000-000000000001';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FAIL: recipient could not mark the letter opened'; end if;
  raise notice 'PASS: recipient can stamp unlocked_at';
end $$;

-- 2. The recipient cannot rewrite the letter's body.
do $$
begin
  update public.future_letters set body_ciphertext = '\x02'::bytea
   where id = '77777777-2222-0000-0000-000000000001';
  raise exception 'FAIL: recipient rewrote body_ciphertext';
exception when insufficient_privilege then
  raise notice 'PASS: body_ciphertext is not updatable';
end $$;

-- 3. ...nor claim authorship or re-seal it.
do $$
begin
  update public.future_letters set author_id = '77777777-0000-0000-0000-00000000000b'
   where id = '77777777-2222-0000-0000-000000000001';
  raise exception 'FAIL: recipient changed author_id';
exception when insufficient_privilege then
  raise notice 'PASS: author_id is not updatable';
end $$;

do $$
begin
  update public.future_letters set unlock_at = now() + interval '1 year'
   where id = '77777777-2222-0000-0000-000000000001';
  raise exception 'FAIL: recipient re-sealed the letter';
exception when insufficient_privilege then
  raise notice 'PASS: unlock_at is not updatable';
end $$;

-- 4. A paired user cannot change their gender.
set local request.jwt.claim.sub = '77777777-0000-0000-0000-00000000000a';
do $$
begin
  update public.users set gender = 'female'
   where id = '77777777-0000-0000-0000-00000000000a';
  raise exception 'FAIL: paired user changed gender';
exception when check_violation then
  raise notice 'PASS: gender is locked while paired';
end $$;

-- 5. ...but other profile fields still update.
do $$
declare n int;
begin
  update public.users set display_name = 'A'
   where id = '77777777-0000-0000-0000-00000000000a';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FAIL: paired user could not update display_name'; end if;
  raise notice 'PASS: other profile fields still update';
end $$;

-- 6. An unpaired user can still correct their gender.
set local request.jwt.claim.sub = '77777777-0000-0000-0000-00000000000d';
do $$
declare n int;
begin
  update public.users set gender = 'female'
   where id = '77777777-0000-0000-0000-00000000000d';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FAIL: unpaired user could not change gender'; end if;
  raise notice 'PASS: unpaired user can change gender';
end $$;

reset role;
rollback;
