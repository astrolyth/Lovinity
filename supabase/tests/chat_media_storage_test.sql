-- Plain psql assertion script for 20260729000001_chat_media_storage.sql.
-- Same style as supabase/tests/push_notifications_test.sql: DO blocks that
-- RAISE EXCEPTION on failure and RAISE NOTICE 'PASS: ...' on success, run
-- inside a transaction that is ROLLBACK'd at the end.
--
-- Run with:
--   PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f supabase/tests/chat_media_storage_test.sql

begin;

-- ------------------------------------------------------------------
-- Fixtures: three unrelated users, A+B paired, C left out.
-- ------------------------------------------------------------------
insert into auth.users (id) values
  ('99999999-2000-0000-0000-00000000000a'),
  ('99999999-2000-0000-0000-00000000000b'),
  ('99999999-2000-0000-0000-00000000000c');

insert into public.couples (id, member_a, member_b)
values ('99999999-2000-0000-0000-0000000000c1',
        '99999999-2000-0000-0000-00000000000a',
        '99999999-2000-0000-0000-00000000000b');

-- ------------------------------------------------------------------
-- 1. Couple member A can insert an object under their own couple's path.
-- ------------------------------------------------------------------
set role authenticated;
set local request.jwt.claim.sub = '99999999-2000-0000-0000-00000000000a';

insert into storage.objects (bucket_id, name)
values ('chat-media', '99999999-2000-0000-0000-0000000000c1/msg-1');

do $$
begin
  if not exists (
    select 1 from storage.objects
    where bucket_id = 'chat-media'
      and name = '99999999-2000-0000-0000-0000000000c1/msg-1'
  ) then
    raise exception 'FAIL: couple member A could not insert under their own couple path';
  end if;
  raise notice 'PASS: couple member A inserted an object under their couple path';
end $$;

reset role;

-- ------------------------------------------------------------------
-- 2. The spouse (B) can read the same object.
-- ------------------------------------------------------------------
set role authenticated;
set local request.jwt.claim.sub = '99999999-2000-0000-0000-00000000000b';

do $$
begin
  if not exists (
    select 1 from storage.objects
    where bucket_id = 'chat-media'
      and name = '99999999-2000-0000-0000-0000000000c1/msg-1'
  ) then
    raise exception 'FAIL: spouse B could not read the couple''s attachment object';
  end if;
  raise notice 'PASS: spouse B read the couple''s attachment object';
end $$;

reset role;

-- ------------------------------------------------------------------
-- 3. An outsider (C) cannot read the couple's object.
-- ------------------------------------------------------------------
set role authenticated;
set local request.jwt.claim.sub = '99999999-2000-0000-0000-00000000000c';

do $$
begin
  if exists (
    select 1 from storage.objects
    where bucket_id = 'chat-media'
      and name = '99999999-2000-0000-0000-0000000000c1/msg-1'
  ) then
    raise exception 'FAIL: outsider C could read another couple''s attachment object';
  end if;
  raise notice 'PASS: outsider C cannot read another couple''s attachment object';
end $$;

-- ------------------------------------------------------------------
-- 4. An outsider (C) cannot insert into the couple's path.
-- ------------------------------------------------------------------
do $$
begin
  insert into storage.objects (bucket_id, name)
  values ('chat-media', '99999999-2000-0000-0000-0000000000c1/msg-2');
  -- If we get here, RLS did NOT block the insert -- that is the failure.
  raise exception 'RLS_DID_NOT_BLOCK';
exception
  when others then
    if sqlerrm = 'RLS_DID_NOT_BLOCK' then
      raise exception 'FAIL: outsider C was able to insert into another couple''s path';
    end if;
    raise notice 'PASS: outsider C cannot insert into another couple''s path (%)', sqlerrm;
end $$;

reset role;

rollback;
