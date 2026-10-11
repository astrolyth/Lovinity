-- Plain psql assertion script for 20260802000003_question_queue.sql.
-- Run with:
--   PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f supabase/tests/question_queue_test.sql

begin;

insert into auth.users (id) values
  ('99999999-3000-0000-0000-00000000000a'),
  ('99999999-3000-0000-0000-00000000000b');

insert into public.couples (id, member_a, member_b)
values ('99999999-3000-0000-0000-0000000000c1',
        '99999999-3000-0000-0000-00000000000a',
        '99999999-3000-0000-0000-00000000000b');

-- Isolate from the seeded pool: drop everything, insert a known set.
delete from public.question_answers;
delete from public.daily_content;
delete from public.daily_questions;
insert into public.daily_questions (id, question, category, language, status, source) values
  ('99999999-3000-0000-0000-0000000000d1', 'Q1', 'playful', 'en', 'approved', 'seed'),
  ('99999999-3000-0000-0000-0000000000d2', 'Q2', 'deen', 'en', 'approved', 'seed'),
  ('99999999-3000-0000-0000-0000000000d3', 'Q3', 'future', 'en', 'pending', 'generated');

-- 1. Both partners resolve the SAME question.
do $$
declare a_q uuid; b_q uuid;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','99999999-3000-0000-0000-00000000000a',true);
  select id into a_q from public.get_current_question();
  perform set_config('request.jwt.claim.sub','99999999-3000-0000-0000-00000000000b',true);
  select id into b_q from public.get_current_question();
  if a_q is null or a_q <> b_q then
    raise exception 'FAIL: partners disagree on current question (% vs %)', a_q, b_q;
  end if;
  raise notice 'PASS: both partners resolve the same question';
end $$;
reset role;

-- 2. A 'pending' question is never selected.
do $$
declare picked uuid;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','99999999-3000-0000-0000-00000000000a',true);
  select id into picked from public.get_current_question();
  if picked = '99999999-3000-0000-0000-0000000000d3' then
    raise exception 'FAIL: a pending question was served to a couple';
  end if;
  raise notice 'PASS: pending questions are excluded';
end $$;
reset role;

-- 3. ONE answer does not advance the queue; BOTH does.
do $$
declare first_q uuid; still_q uuid; next_q uuid;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','99999999-3000-0000-0000-00000000000a',true);
  select id into first_q from public.get_current_question();

  insert into public.question_answers (couple_id, question_id, author_id, answer)
  values ('99999999-3000-0000-0000-0000000000c1', first_q,
          '99999999-3000-0000-0000-00000000000a', 'a answer');

  select id into still_q from public.get_current_question();
  if still_q <> first_q then
    raise exception 'FAIL: queue advanced after only one partner answered';
  end if;
  raise notice 'PASS: one answer does not advance the queue';

  insert into public.question_answers (couple_id, question_id, author_id, answer)
  values ('99999999-3000-0000-0000-0000000000c1', first_q,
          '99999999-3000-0000-0000-00000000000b', 'b answer');

  select id into next_q from public.get_current_question();
  if next_q = first_q then
    raise exception 'FAIL: queue did not advance after both partners answered';
  end if;
  raise notice 'PASS: queue advances once both partners answered';
end $$;
reset role;

-- 4. Exhausted queue returns zero rows (not an error).
do $$
declare remaining uuid; n int;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','99999999-3000-0000-0000-00000000000a',true);
  select id into remaining from public.get_current_question();
  insert into public.question_answers (couple_id, question_id, author_id, answer)
  values ('99999999-3000-0000-0000-0000000000c1', remaining,
          '99999999-3000-0000-0000-00000000000a', 'a'),
         ('99999999-3000-0000-0000-0000000000c1', remaining,
          '99999999-3000-0000-0000-00000000000b', 'b');

  select count(*) into n from public.get_current_question();
  if n <> 0 then
    raise exception 'FAIL: exhausted queue returned % rows, expected 0', n;
  end if;
  raise notice 'PASS: exhausted queue returns zero rows';
end $$;
reset role;

-- 5. Two different couples get different orderings.
--
-- The whole justification for a cursorless queue is that
-- `order by hashtext(couple_id || q.id)` gives each couple its own sequence
-- while staying stable for both partners. Cases 1-4 all use a single couple,
-- so a regression to a couple-independent `order by q.id` would pass every
-- one of them. This is the case that catches it: with a couple-independent
-- ordering, all N couples resolve to the SAME first question and the
-- distinct count collapses to 1.
--
-- Asserted as "not all couples agree" rather than against a hardcoded
-- expected ordering, so the test doesn't depend on hashtext's exact output.
delete from public.question_answers;
delete from public.daily_content;
delete from public.daily_questions;
insert into public.daily_questions (id, question, category, language, status, source) values
  ('99999999-3000-0000-0000-0000000000e1', 'E1', 'playful', 'en', 'approved', 'seed'),
  ('99999999-3000-0000-0000-0000000000e2', 'E2', 'deen', 'en', 'approved', 'seed'),
  ('99999999-3000-0000-0000-0000000000e3', 'E3', 'future', 'en', 'approved', 'seed'),
  ('99999999-3000-0000-0000-0000000000e4', 'E4', 'reflective', 'en', 'approved', 'seed');

-- 8 more couples. member_a < member_b is a table check constraint, hence the
-- odd/even id pairing.
do $$
declare i int; ua uuid; ub uuid;
begin
  for i in 1..8 loop
    ua := ('99999999-4000-0000-0000-' || lpad((i * 2 - 1)::text, 12, '0'))::uuid;
    ub := ('99999999-4000-0000-0000-' || lpad((i * 2)::text, 12, '0'))::uuid;
    insert into auth.users (id) values (ua), (ub);
    insert into public.couples (id, member_a, member_b)
      values (('99999999-4001-0000-0000-' || lpad(i::text, 12, '0'))::uuid, ua, ub);
  end loop;
end $$;

do $$
declare i int; picked uuid; picks uuid[] := '{}'; distinct_n int;
begin
  set local role authenticated;
  for i in 1..8 loop
    perform set_config(
      'request.jwt.claim.sub',
      ('99999999-4000-0000-0000-' || lpad((i * 2 - 1)::text, 12, '0')),
      true);
    select id into picked from public.get_current_question();
    if picked is null then
      raise exception 'FAIL: couple % resolved no question from a 4-question approved pool', i;
    end if;
    picks := picks || picked;
  end loop;

  select count(distinct x) into distinct_n from unnest(picks) x;
  if distinct_n < 2 then
    raise exception
      'FAIL: all 8 couples resolved the same first question (%) -- the '
      'ordering is not couple-dependent', picks[1];
  end if;
  raise notice 'PASS: different couples get different orderings (% distinct first questions across 8 couples)', distinct_n;
end $$;
reset role;

-- 6. get_daily_content never serves an unapproved question.
--
-- Mirrors case 2, but against the OTHER path into daily_questions. Until
-- 20260803000001 this select had no status filter at all, so the review
-- queue that all of get_current_question's gating exists to enforce was
-- bypassed entirely by daily_content.question_id -- including for questions
-- a human had explicitly REJECTED, which stay in the table and were equally
-- selectable. Covers both unapproved statuses.
insert into public.daily_questions (id, question, category, language, status, source) values
  ('99999999-3000-0000-0000-0000000000e8', 'E8 pending', 'playful', 'en', 'pending', 'generated'),
  ('99999999-3000-0000-0000-0000000000e9', 'E9 rejected', 'playful', 'en', 'rejected', 'generated');

do $$
declare i int; qid uuid; st text;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','99999999-3000-0000-0000-00000000000a',true);
  -- One call per date: the pick is seeded per (couple, date), so sampling
  -- many dates samples many different draws from the pool. A single date
  -- would only ever exercise one seed.
  for i in 1..60 loop
    select question_id into qid
      from public.get_daily_content((date '2026-01-01' + i));
    if qid is not null then
      select status into st from public.daily_questions where id = qid;
      if st <> 'approved' then
        raise exception
          'FAIL: get_daily_content served a ''%'' question (%) on date %',
          st, qid, (date '2026-01-01' + i);
      end if;
    end if;
  end loop;
  raise notice 'PASS: get_daily_content excludes pending and rejected questions';
end $$;
reset role;

-- 6b. With NOTHING approved, get_daily_content must hand back a null
-- question rather than falling back to an unapproved one.
delete from public.daily_content;
delete from public.daily_questions where status = 'approved';

do $$
declare i int; qid uuid; st text;
begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub','99999999-3000-0000-0000-00000000000a',true);
  for i in 1..40 loop
    select question_id into qid
      from public.get_daily_content((date '2027-01-01' + i));
    if qid is not null then
      select status into st from public.daily_questions where id = qid;
      raise exception
        'FAIL: with no approved questions, get_daily_content still served a ''%'' question (%)',
        st, qid;
    end if;
  end loop;
  raise notice 'PASS: an all-unapproved pool yields a null question, not a fallback';
end $$;
reset role;

rollback;
