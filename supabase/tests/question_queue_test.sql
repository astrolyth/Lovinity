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

rollback;
