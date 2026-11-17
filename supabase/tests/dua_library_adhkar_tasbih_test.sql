-- Assertions for 20261116000004_dua_library_adhkar_tasbih.sql.
-- Run with:
--   PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f supabase/tests/dua_library_adhkar_tasbih_test.sql

begin;

-- Fixtures: A (husband) + B (wife) paired; C + D are an outsider couple.
insert into auth.users (id) values
  ('88888888-0000-0000-0000-00000000000a'),
  ('88888888-0000-0000-0000-00000000000b'),
  ('88888888-0000-0000-0000-00000000000c'),
  ('88888888-0000-0000-0000-00000000000d');
update public.users set gender = 'male'
  where id in ('88888888-0000-0000-0000-00000000000a', '88888888-0000-0000-0000-00000000000c');
update public.users set gender = 'female'
  where id in ('88888888-0000-0000-0000-00000000000b', '88888888-0000-0000-0000-00000000000d');
insert into public.couples (id, member_a, member_b) values
  ('88888888-1111-0000-0000-000000000001',
   '88888888-0000-0000-0000-00000000000a', '88888888-0000-0000-0000-00000000000b'),
  ('88888888-1111-0000-0000-000000000002',
   '88888888-0000-0000-0000-00000000000c', '88888888-0000-0000-0000-00000000000d');

insert into public.duas_library (title, arabic_text, translation, status, source, source_id) values
  ('pending', 'x', 'x', 'pending',  'test', 't-pending'),
  ('approved', 'x', 'x', 'approved', 'test', 't-approved');

insert into public.dhikr_counters (id, couple_id, title, target, period, starts_at) values
  ('88888888-2222-0000-0000-000000000001', '88888888-1111-0000-0000-000000000001',
   'weekly', 100, 'weekly', now() - interval '10 days'),
  ('88888888-2222-0000-0000-000000000002', '88888888-1111-0000-0000-000000000001',
   'once', 100, 'once', now() - interval '10 days');
insert into public.dhikr_contributions (counter_id, couple_id, user_id, count, logged_at)
select c, '88888888-1111-0000-0000-000000000001', '88888888-0000-0000-0000-00000000000a', n, t
from (values
  ('88888888-2222-0000-0000-000000000001'::uuid, 5, now() - interval '9 days'),
  ('88888888-2222-0000-0000-000000000001'::uuid, 7, now() - interval '1 day'),
  ('88888888-2222-0000-0000-000000000002'::uuid, 5, now() - interval '9 days'),
  ('88888888-2222-0000-0000-000000000002'::uuid, 7, now() - interval '1 day')) v(c, n, t);

set role authenticated;
set local request.jwt.claim.sub = '88888888-0000-0000-0000-00000000000a';

-- 1. Library only shows approved rows.
do $$
begin
  if (select count(*) from public.duas_library where source_id = 't-pending') <> 0 then
    raise exception 'FAIL: pending library row is visible';
  end if;
  if (select count(*) from public.duas_library where source_id = 't-approved') <> 1 then
    raise exception 'FAIL: approved library row is not visible';
  end if;
  raise notice 'PASS: library read is approved-only';
end $$;

-- 2. Own completion inserts once; a duplicate violates the unique key.
do $$
begin
  insert into public.adhkar_completions (couple_id, user_id, local_date, set)
  values ('88888888-1111-0000-0000-000000000001', '88888888-0000-0000-0000-00000000000a',
          current_date, 'morning');
  begin
    insert into public.adhkar_completions (couple_id, user_id, local_date, set)
    values ('88888888-1111-0000-0000-000000000001', '88888888-0000-0000-0000-00000000000a',
            current_date, 'morning');
    raise exception 'FAIL: duplicate completion accepted';
  exception when unique_violation then
    raise notice 'PASS: completion inserts once, duplicate rejected';
  end;
end $$;

-- 3. Cannot complete on behalf of the partner.
do $$
begin
  insert into public.adhkar_completions (couple_id, user_id, local_date, set)
  values ('88888888-1111-0000-0000-000000000001', '88888888-0000-0000-0000-00000000000b',
          current_date, 'evening');
  raise exception 'FAIL: inserted a completion as the partner';
exception when insufficient_privilege then
  raise notice 'PASS: cannot insert a completion for the partner';
end $$;

-- 5. No UPDATE grant on completions.
do $$
begin
  update public.adhkar_completions set completed_at = now() - interval '1 day';
  raise exception 'FAIL: completion was updatable';
exception when insufficient_privilege then
  raise notice 'PASS: completions are not updatable';
end $$;

-- 6. Totals only count the current period window.
do $$
declare w bigint; o bigint;
begin
  select total into w from public.dhikr_counter_totals('88888888-2222-0000-0000-000000000001')
   where user_id = '88888888-0000-0000-0000-00000000000a';
  select total into o from public.dhikr_counter_totals('88888888-2222-0000-0000-000000000002')
   where user_id = '88888888-0000-0000-0000-00000000000a';
  if w is distinct from 7 then raise exception 'FAIL: weekly total % <> 7', w; end if;
  if o is distinct from 12 then raise exception 'FAIL: once total % <> 12', o; end if;
  raise notice 'PASS: dhikr_counter_totals respects the period window';
end $$;

-- 7. Seed "Morning dhikr" is rejected (duplicates fitrahive): 19 morning items.
do $$
declare n bigint;
begin
  select count(*) into n from public.duas_library where category = 'morning';
  if n <> 19 then raise exception 'FAIL: % approved morning rows <> 19', n; end if;
  raise notice 'PASS: morning set has 19 approved items';
end $$;

-- 4a. Partner can read A's completion.
set local request.jwt.claim.sub = '88888888-0000-0000-0000-00000000000b';
do $$
begin
  if (select count(*) from public.adhkar_completions) <> 1 then
    raise exception 'FAIL: partner cannot read the completion';
  end if;
  raise notice 'PASS: partner reads completion';
end $$;

-- 4b. Outsider sees nothing.
set local request.jwt.claim.sub = '88888888-0000-0000-0000-00000000000c';
do $$
begin
  if (select count(*) from public.adhkar_completions) <> 0 then
    raise exception 'FAIL: outsider can read the completion';
  end if;
  raise notice 'PASS: outsider reads 0 completions';
end $$;

-- 8. repeat_count must be >= 1.
reset role;
do $$
begin
  insert into public.duas_library (title, arabic_text, translation, repeat_count)
  values ('zero', 'x', 'x', 0);
  raise exception 'FAIL: repeat_count 0 accepted';
exception when check_violation then
  raise notice 'PASS: repeat_count 0 rejected';
end $$;

rollback;
