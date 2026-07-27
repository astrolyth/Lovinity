-- Plain psql assertion script for 20260726000001_push_notifications.sql.
-- pgTAP is not installed on this local stack, so assertions are expressed as
-- DO blocks that RAISE EXCEPTION on failure (psql -v ON_ERROR_STOP=1 makes
-- that a non-zero exit) and RAISE NOTICE 'PASS: ...' on success.
--
-- Fixtures (throwaway auth.users/public.users/couple rows) are created
-- inside a single transaction that is ROLLBACK'd at the end, so nothing
-- leaks into the running dev DB. auth.uid() is simulated the same way
-- PostgREST does it: `set role authenticated; set local
-- request.jwt.claim.sub = '<uuid>';` -- this also means RLS is genuinely
-- enforced (authenticated/anon do not have BYPASSRLS), unlike testing as
-- the postgres superuser.
--
-- Run with:
--   PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f supabase/tests/push_notifications_test.sql

begin;

-- ------------------------------------------------------------------
-- Fixtures: three unrelated users, A+B paired, C left out.
-- ------------------------------------------------------------------
insert into auth.users (id) values
  ('99999999-0000-0000-0000-00000000000a'),
  ('99999999-0000-0000-0000-00000000000b'),
  ('99999999-0000-0000-0000-00000000000c');

do $$
begin
  if (select count(*) from public.users where id in (
        '99999999-0000-0000-0000-00000000000a',
        '99999999-0000-0000-0000-00000000000b',
        '99999999-0000-0000-0000-00000000000c')) <> 3 then
    raise exception 'FAIL: handle_new_auth_user did not backfill public.users for fixtures';
  end if;
  raise notice 'PASS: fixture users created';
end $$;

insert into public.couples (member_a, member_b)
values ('99999999-0000-0000-0000-00000000000a', '99999999-0000-0000-0000-00000000000b');

-- ------------------------------------------------------------------
-- 1. dispatch_push with empty/absent private.push_config is a silent no-op.
-- ------------------------------------------------------------------
do $$
begin
  if exists (select 1 from private.push_config) then
    raise exception 'ABORT: private.push_config already has a row -- test assumes empty config';
  end if;

  perform public.dispatch_push(
    '99999999-0000-0000-0000-00000000000a', 'chat', 'title', 'body'
  );
  raise notice 'PASS: dispatch_push no-op with absent push_config (no exception)';
exception when others then
  raise exception 'FAIL: dispatch_push raised with empty config: %', sqlerrm;
end $$;

-- ------------------------------------------------------------------
-- 2. dispatch_push still never raises even when a (bogus) config row
--    exists -- exercises the pg_net-error-swallowing branch.
-- ------------------------------------------------------------------
insert into private.push_config (function_url, dispatch_secret)
values ('http://127.0.0.1:1/unreachable', 'test-secret');

do $$
begin
  perform public.dispatch_push(
    '99999999-0000-0000-0000-00000000000a', 'chat', 'title', 'body'
  );
  raise notice 'PASS: dispatch_push swallowed pg_net error/unreachable url (no exception)';
exception when others then
  raise exception 'FAIL: dispatch_push raised with a configured-but-bad url: %', sqlerrm;
end $$;

delete from private.push_config;

-- ------------------------------------------------------------------
-- 3. register_push_token: upsert on token reassigns ownership across
--    accounts (prevents cross-account push leak from a shared/reused
--    device token).
-- ------------------------------------------------------------------
set role authenticated;
set local request.jwt.claim.sub = '99999999-0000-0000-0000-00000000000a';
select public.register_push_token('shared-tok', 'ios');
reset role;

do $$
declare v_owner uuid; v_platform text; v_count int;
begin
  select user_id, platform into v_owner, v_platform
    from public.device_push_tokens where token = 'shared-tok';
  select count(*) into v_count from public.device_push_tokens where token = 'shared-tok';
  if v_count <> 1 or v_owner <> '99999999-0000-0000-0000-00000000000a' or v_platform <> 'ios' then
    raise exception 'FAIL: register_push_token did not create token owned by A (owner=%, platform=%, count=%)', v_owner, v_platform, v_count;
  end if;
  raise notice 'PASS: register_push_token created shared-tok owned by A';
end $$;

set role authenticated;
set local request.jwt.claim.sub = '99999999-0000-0000-0000-00000000000b';
select public.register_push_token('shared-tok', 'android');
reset role;

do $$
declare v_owner uuid; v_platform text; v_count int;
begin
  select count(*) into v_count from public.device_push_tokens where token = 'shared-tok';
  select user_id, platform into v_owner, v_platform
    from public.device_push_tokens where token = 'shared-tok';
  if v_count <> 1 or v_owner <> '99999999-0000-0000-0000-00000000000b' or v_platform <> 'android' then
    raise exception 'FAIL: register_push_token did not reassign shared-tok to B (owner=%, platform=%, count=%)', v_owner, v_platform, v_count;
  end if;
  raise notice 'PASS: register_push_token reassigned shared-tok from A to B, no duplicate row';
end $$;

-- ------------------------------------------------------------------
-- 4. unregister_push_token deletes only a token owned by the caller.
-- ------------------------------------------------------------------
set role authenticated;
set local request.jwt.claim.sub = '99999999-0000-0000-0000-00000000000a';
select public.unregister_push_token('shared-tok'); -- A no longer owns it (B does) -> no-op
reset role;

do $$
declare v_count int;
begin
  select count(*) into v_count from public.device_push_tokens where token = 'shared-tok';
  if v_count <> 1 then
    raise exception 'FAIL: unregister_push_token by non-owner deleted the row (count=%)', v_count;
  end if;
  raise notice 'PASS: unregister_push_token is a no-op for a token you do not own';
end $$;

set role authenticated;
set local request.jwt.claim.sub = '99999999-0000-0000-0000-00000000000b';
select public.unregister_push_token('shared-tok'); -- B owns it -> deletes
reset role;

do $$
declare v_count int;
begin
  select count(*) into v_count from public.device_push_tokens where token = 'shared-tok';
  if v_count <> 0 then
    raise exception 'FAIL: unregister_push_token by owner did not delete the row (count=%)', v_count;
  end if;
  raise notice 'PASS: unregister_push_token deletes a token owned by the caller';
end $$;

-- ------------------------------------------------------------------
-- 5. RLS blocks reading another user's tokens.
-- ------------------------------------------------------------------
set role authenticated;
set local request.jwt.claim.sub = '99999999-0000-0000-0000-00000000000a';
select public.register_push_token('tok-a', 'ios');
reset role;

set role authenticated;
set local request.jwt.claim.sub = '99999999-0000-0000-0000-00000000000b';
select public.register_push_token('tok-b', 'android');
reset role;

set role authenticated;
set local request.jwt.claim.sub = '99999999-0000-0000-0000-00000000000a';
do $$
declare v_count int; v_other_count int;
begin
  select count(*) into v_count from public.device_push_tokens; -- RLS-filtered view as A
  select count(*) into v_other_count from public.device_push_tokens
    where user_id = '99999999-0000-0000-0000-00000000000b';
  if v_count <> 1 then
    raise exception 'FAIL: RLS select as A returned % rows, expected 1 (own only)', v_count;
  end if;
  if v_other_count <> 0 then
    raise exception 'FAIL: RLS did not block A from seeing B''s token (count=%)', v_other_count;
  end if;
  raise notice 'PASS: RLS restricts device_push_tokens select to own rows';
end $$;
reset role;

-- ------------------------------------------------------------------
-- 6. send_message with p_notify_kind='silent' still inserts message +
--    envelope and never raises, even though push is unconfigured.
-- ------------------------------------------------------------------
do $$
begin
  if exists (select 1 from private.push_config) then
    raise exception 'ABORT: private.push_config unexpectedly non-empty before send_message tests';
  end if;
end $$;

-- Each send_message call below uses a unique ciphertext marker so we can
-- verify the resulting rows via a join, without needing to pass a returned
-- message_id across separate psql statements.
set role authenticated;
set local request.jwt.claim.sub = '99999999-0000-0000-0000-00000000000a';
do $$
declare v_msg_id uuid;
begin
  select message_id into v_msg_id from public.send_message(
    1,
    jsonb_build_array(jsonb_build_object(
      'recipient_id', '99999999-0000-0000-0000-00000000000b',
      'recipient_device_num', 1,
      'cipher_type', 3,
      'ciphertext', 'ab'
    )),
    null,
    'silent'
  );
  if v_msg_id is null then
    raise exception 'FAIL: send_message(silent) did not return a message_id';
  end if;
exception when others then
  raise exception 'FAIL: send_message(silent) raised: %', sqlerrm;
end $$;
reset role;

do $$
declare v_msg_count int; v_env_count int;
begin
  select count(*) into v_env_count from public.message_envelopes where ciphertext = decode('ab', 'hex');
  select count(*) into v_msg_count from public.messages m
    join public.message_envelopes e on e.message_id = m.id
   where e.ciphertext = decode('ab', 'hex');
  if v_msg_count <> 1 or v_env_count <> 1 then
    raise exception 'FAIL: send_message(silent) did not insert message+envelope (msg=%, env=%)', v_msg_count, v_env_count;
  end if;
  raise notice 'PASS: send_message with p_notify_kind=silent inserts message+envelope, no exception, push unconfigured';
end $$;

-- ------------------------------------------------------------------
-- 7. send_message with the DEFAULT notify kind ('message') also never
--    raises when push is unconfigured -- this is the core
--    graceful-degradation guarantee, not just the silent path.
-- ------------------------------------------------------------------
set role authenticated;
set local request.jwt.claim.sub = '99999999-0000-0000-0000-00000000000a';
do $$
declare v_msg_id uuid;
begin
  select message_id into v_msg_id from public.send_message(
    1,
    jsonb_build_array(jsonb_build_object(
      'recipient_id', '99999999-0000-0000-0000-00000000000b',
      'recipient_device_num', 1,
      'cipher_type', 3,
      'ciphertext', 'cd'
    ))
  ); -- p_message_id and p_notify_kind both default; notify_kind defaults to 'message'
  if v_msg_id is null then
    raise exception 'FAIL: send_message with default notify kind did not return a message_id';
  end if;
  raise notice 'PASS: send_message with default p_notify_kind=message does not raise when push is unconfigured';
end $$;
reset role;

-- Also confirm the OLD 3-arg call shape still resolves (trailing default
-- param added, existing callers unaffected).
set role authenticated;
set local request.jwt.claim.sub = '99999999-0000-0000-0000-00000000000a';
do $$
declare v_msg_id uuid;
begin
  select message_id into v_msg_id from public.send_message(
    1,
    jsonb_build_array(jsonb_build_object(
      'recipient_id', '99999999-0000-0000-0000-00000000000b',
      'recipient_device_num', 1,
      'cipher_type', 3,
      'ciphertext', 'ef'
    )),
    gen_random_uuid()
  ); -- exactly 3 positional args, as the pre-existing Dart caller sends
  if v_msg_id is null then
    raise exception 'FAIL: 3-arg send_message call did not resolve/return a message_id';
  end if;
  raise notice 'PASS: pre-existing 3-arg send_message call shape still resolves';
end $$;
reset role;

-- ------------------------------------------------------------------
-- 8. Pairing trigger: transitioning a couple's status INTO 'active' does
--    not raise (push unconfigured). We cannot assert an HTTP call was
--    made without a live pg_net worker/mock endpoint, so this checks the
--    documented behaviour we CAN verify at the SQL level: the trigger
--    fires and dispatch_push's no-op path keeps the UPDATE succeeding.
-- ------------------------------------------------------------------
do $$
declare v_status text;
begin
  update public.couples set status = 'archived'
   where member_a = '99999999-0000-0000-0000-00000000000a'
     and member_b = '99999999-0000-0000-0000-00000000000b';

  update public.couples set status = 'active' -- transition INTO active fires the trigger
   where member_a = '99999999-0000-0000-0000-00000000000a'
     and member_b = '99999999-0000-0000-0000-00000000000b'
  returning status into v_status;

  if v_status <> 'active' then
    raise exception 'FAIL: couple status update did not take effect';
  end if;
  raise notice 'PASS: couples status transition to active fires on_couple_active trigger without raising (push unconfigured)';
exception when others then
  raise exception 'FAIL: pairing-active transition raised: %', sqlerrm;
end $$;

-- NOTE (untestable at this level): that dispatch_push's net.http_post call
-- actually reaches an edge function, and that the pairing trigger notifies
-- BOTH member_a and member_b, would require a live pg_net worker plus a
-- mock HTTP endpoint (or instrumenting dispatch_push itself) to observe --
-- out of scope for a plain SQL assertion script. The code path for "call
-- dispatch_push twice, once per member" is a straight-line, un-branching
-- two-line block in notify_pairing_active() and was read-verified instead.

rollback;
