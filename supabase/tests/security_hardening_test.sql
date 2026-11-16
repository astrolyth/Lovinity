-- Plain psql assertion script for 20261115000001_security_hardening.sql.
-- Same conventions as push_notifications_test.sql: DO blocks RAISE on
-- failure, fixtures live in one transaction that is rolled back, and
-- auth.uid() is simulated with `set role authenticated` + jwt claim so RLS
-- and grants are really enforced.
--
-- Run with:
--   PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f supabase/tests/security_hardening_test.sql
--
-- Not covered here: the advisory lock in accept_pairing_invite (needs two
-- concurrent sessions; a single psql script can't race itself).

begin;

-- Fixtures: A (husband) + B (wife) paired, C unrelated.
insert into auth.users (id) values
  ('88888888-0000-0000-0000-00000000000a'),
  ('88888888-0000-0000-0000-00000000000b'),
  ('88888888-0000-0000-0000-00000000000c');
update public.users set gender = 'male'
  where id in ('88888888-0000-0000-0000-00000000000a', '88888888-0000-0000-0000-00000000000c');
update public.users set gender = 'female'
  where id = '88888888-0000-0000-0000-00000000000b';

insert into public.couples (id, member_a, member_b)
values ('88888888-1111-0000-0000-000000000001',
        '88888888-0000-0000-0000-00000000000a', '88888888-0000-0000-0000-00000000000b');

-- B: a PRIVATE cycle record covering yesterday, and one prayer logged earlier.
insert into public.cycle_records (user_id, couple_id, started_on, ended_on, visibility)
values ('88888888-0000-0000-0000-00000000000b', '88888888-1111-0000-0000-000000000001',
        (now() at time zone 'UTC')::date - 1, (now() at time zone 'UTC')::date - 1, 'private');
insert into public.prayer_logs (couple_id, user_id, date, prayer)
values ('88888888-1111-0000-0000-000000000001', '88888888-0000-0000-0000-00000000000b',
        (now() at time zone 'UTC')::date - 2, 'fajr');

-- ------------------------------------------------------------------
-- 1. A signed-in user cannot call dispatch_push.
-- ------------------------------------------------------------------
set role authenticated;
set local request.jwt.claim.sub = '88888888-0000-0000-0000-00000000000a';
do $$
begin
  perform public.dispatch_push('88888888-0000-0000-0000-00000000000c', 'chat', 'x', 'y');
  raise exception 'FAIL: authenticated user could call dispatch_push';
exception when insufficient_privilege then
  raise notice 'PASS: dispatch_push is not callable by authenticated';
end $$;

-- ------------------------------------------------------------------
-- 2. A member cannot rewrite the couple row.
-- ------------------------------------------------------------------
do $$
begin
  update public.couples set member_b = '88888888-0000-0000-0000-00000000000c'
   where id = '88888888-1111-0000-0000-000000000001';
  raise exception 'FAIL: member could update couples';
exception when insufficient_privilege then
  raise notice 'PASS: couples is read-only for members';
end $$;

-- ------------------------------------------------------------------
-- 3. The husband's view of the wife's scoreboard ignores her PRIVATE cycle
--    record (yesterday counts as due); her own view still exempts it.
-- ------------------------------------------------------------------
do $$
declare v_due int;
begin
  select due into v_due from public.get_couple_scoreboard(1)
   where member_id = '88888888-0000-0000-0000-00000000000b';
  if v_due <> 5 then
    raise exception 'FAIL: spouse view leaked a private exemption (due=%)', v_due;
  end if;
  raise notice 'PASS: spouse scoreboard does not reveal private cycle days';
end $$;
reset role;

set role authenticated;
set local request.jwt.claim.sub = '88888888-0000-0000-0000-00000000000b';
do $$
declare v_due int;
begin
  select due into v_due from public.get_couple_scoreboard(1)
   where member_id = '88888888-0000-0000-0000-00000000000b';
  if v_due <> 0 then
    raise exception 'FAIL: own scoreboard lost the private exemption (due=%)', v_due;
  end if;
  raise notice 'PASS: own scoreboard still exempts private cycle days';
end $$;
reset role;

-- ------------------------------------------------------------------
-- 5. A spouse can read but not delete the other's prayer log, and nobody
--    can write messages directly.
-- ------------------------------------------------------------------
set role authenticated;
set local request.jwt.claim.sub = '88888888-0000-0000-0000-00000000000a';
do $$
declare v_seen int;
begin
  select count(*) into v_seen from public.prayer_logs
   where user_id = '88888888-0000-0000-0000-00000000000b';
  if v_seen <> 1 then
    raise exception 'FAIL: spouse cannot read partner prayer log (saw %)', v_seen;
  end if;
  delete from public.prayer_logs where user_id = '88888888-0000-0000-0000-00000000000b';
end $$;
reset role;

do $$
begin
  if (select count(*) from public.prayer_logs
       where user_id = '88888888-0000-0000-0000-00000000000b') <> 1 then
    raise exception 'FAIL: spouse deleted the partner''s prayer log';
  end if;
  raise notice 'PASS: spouse reads but cannot delete partner prayer logs';
end $$;

set role authenticated;
set local request.jwt.claim.sub = '88888888-0000-0000-0000-00000000000a';
do $$
begin
  insert into public.messages (conversation_id, couple_id, sender_id, sender_device_num)
  values (gen_random_uuid(), '88888888-1111-0000-0000-000000000001',
          '88888888-0000-0000-0000-00000000000a', 1);
  raise exception 'FAIL: direct insert into messages was allowed';
exception when insufficient_privilege then
  raise notice 'PASS: messages cannot be written directly';
end $$;
reset role;

rollback;
