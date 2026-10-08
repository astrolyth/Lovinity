-- Plain psql assertion script for 20261008000001_our_wall.sql.
-- Same conventions as push_notifications_test.sql: pgTAP is not installed,
-- so DO blocks RAISE EXCEPTION on failure and RAISE NOTICE 'PASS: ...' on
-- success. Fixtures live in one transaction that is rolled back at the end.
-- auth.uid() is simulated like PostgREST: `set role authenticated;
-- set local request.jwt.claim.sub = '<uuid>';` so RLS is really enforced.
--
-- Run with:
--   PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f supabase/tests/our_wall_test.sql

begin;

-- Fixtures: A + B paired, C an outsider.
insert into auth.users (id) values
  ('88888888-0000-0000-0000-00000000000a'),
  ('88888888-0000-0000-0000-00000000000b'),
  ('88888888-0000-0000-0000-00000000000c');
update public.users set display_name = 'Aisha'
  where id = '88888888-0000-0000-0000-00000000000a';
insert into public.couples (id, member_a, member_b) values (
  '88888888-1111-0000-0000-000000000001',
  '88888888-0000-0000-0000-00000000000a',
  '88888888-0000-0000-0000-00000000000b');

-- ------------------------------------------------------------------
-- 1. A posts an item, a comment and a reaction as themself.
-- ------------------------------------------------------------------
set role authenticated;
set local request.jwt.claim.sub = '88888888-0000-0000-0000-00000000000a';
insert into public.feed_items (id, couple_id, added_by, url, title, source, note)
values ('88888888-2222-0000-0000-000000000001',
        '88888888-1111-0000-0000-000000000001',
        '88888888-0000-0000-0000-00000000000a',
        'https://youtu.be/abc', 'A video', 'youtube', 'after Fajr?');
insert into public.feed_comments (id, item_id, couple_id, author_id, body)
values ('88888888-3333-0000-0000-000000000001',
        '88888888-2222-0000-0000-000000000001',
        '88888888-1111-0000-0000-000000000001',
        '88888888-0000-0000-0000-00000000000a', 'first!');
insert into public.feed_reactions (item_id, user_id, reaction, couple_id)
values ('88888888-2222-0000-0000-000000000001',
        '88888888-0000-0000-0000-00000000000a', 'heart',
        '88888888-1111-0000-0000-000000000001');
reset role;

do $$
begin
  if not exists (select 1 from public.feed_items where id = '88888888-2222-0000-0000-000000000001')
     or not exists (select 1 from public.feed_comments where id = '88888888-3333-0000-0000-000000000001')
     or not exists (select 1 from public.feed_reactions where item_id = '88888888-2222-0000-0000-000000000001') then
    raise exception 'FAIL: member could not post item/comment/reaction';
  end if;
  raise notice 'PASS: member posts item, comment and reaction (push trigger did not break insert)';
end $$;

-- ------------------------------------------------------------------
-- 2. Nobody can post as someone else.
-- ------------------------------------------------------------------
set role authenticated;
set local request.jwt.claim.sub = '88888888-0000-0000-0000-00000000000a';
do $$
begin
  insert into public.feed_items (couple_id, added_by, note)
  values ('88888888-1111-0000-0000-000000000001', '88888888-0000-0000-0000-00000000000b', 'spoof');
  raise exception 'FAIL: inserted a feed item as another user';
exception when insufficient_privilege then
  raise notice 'PASS: cannot insert a feed item as your spouse';
end $$;
do $$
begin
  insert into public.feed_comments (item_id, couple_id, author_id, body)
  values ('88888888-2222-0000-0000-000000000001', '88888888-1111-0000-0000-000000000001',
          '88888888-0000-0000-0000-00000000000b', 'spoof');
  raise exception 'FAIL: inserted a comment as another user';
exception when insufficient_privilege then
  raise notice 'PASS: cannot comment as your spouse';
end $$;
do $$
begin
  insert into public.feed_reactions (item_id, user_id, reaction, couple_id)
  values ('88888888-2222-0000-0000-000000000001', '88888888-0000-0000-0000-00000000000b',
          'fire', '88888888-1111-0000-0000-000000000001');
  raise exception 'FAIL: inserted a reaction as another user';
exception when insufficient_privilege then
  raise notice 'PASS: cannot react as your spouse';
end $$;
reset role;

-- ------------------------------------------------------------------
-- 3. Spouse B can pin + file, but cannot delete or edit A's content.
-- ------------------------------------------------------------------
set role authenticated;
set local request.jwt.claim.sub = '88888888-0000-0000-0000-00000000000b';
update public.feed_items set is_pinned = true, collection = 'recipes'
  where id = '88888888-2222-0000-0000-000000000001';
delete from public.feed_items where id = '88888888-2222-0000-0000-000000000001';
delete from public.feed_comments where id = '88888888-3333-0000-0000-000000000001';
do $$
begin
  update public.feed_items set note = 'edited by spouse'
    where id = '88888888-2222-0000-0000-000000000001';
  raise exception 'FAIL: spouse edited the note';
exception when insufficient_privilege then
  raise notice 'PASS: spouse cannot edit item content';
end $$;
reset role;

do $$
declare r record;
begin
  select is_pinned, collection into r from public.feed_items
    where id = '88888888-2222-0000-0000-000000000001';
  if not found then
    raise exception 'FAIL: spouse deleted the other''s item';
  end if;
  if not exists (select 1 from public.feed_comments where id = '88888888-3333-0000-0000-000000000001') then
    raise exception 'FAIL: spouse deleted the other''s comment';
  end if;
  if r.is_pinned is distinct from true or r.collection is distinct from 'recipes' then
    raise exception 'FAIL: spouse could not pin/file (pinned=%, collection=%)', r.is_pinned, r.collection;
  end if;
  raise notice 'PASS: spouse can pin and file but not delete';
end $$;

-- Even the author cannot change the url after posting.
set role authenticated;
set local request.jwt.claim.sub = '88888888-0000-0000-0000-00000000000a';
do $$
begin
  update public.feed_items set url = 'https://evil.example'
    where id = '88888888-2222-0000-0000-000000000001';
  raise exception 'FAIL: url changed after posting';
exception when insufficient_privilege then
  raise notice 'PASS: url is immutable';
end $$;
reset role;

-- ------------------------------------------------------------------
-- 4. Outsider C sees nothing and cannot post into the couple.
-- ------------------------------------------------------------------
set role authenticated;
set local request.jwt.claim.sub = '88888888-0000-0000-0000-00000000000c';
do $$
declare n int;
begin
  select count(*) into n from public.feed_items
    where couple_id = '88888888-1111-0000-0000-000000000001';
  if n <> 0 then raise exception 'FAIL: outsider can read % wall items', n; end if;
  select count(*) into n from public.feed_comments
    where couple_id = '88888888-1111-0000-0000-000000000001';
  if n <> 0 then raise exception 'FAIL: outsider can read % comments', n; end if;
  raise notice 'PASS: outsider sees nothing';
end $$;
do $$
begin
  insert into public.feed_items (couple_id, added_by, note)
  values ('88888888-1111-0000-0000-000000000001', '88888888-0000-0000-0000-00000000000c', 'hi');
  raise exception 'FAIL: outsider posted into the couple';
exception when insufficient_privilege then
  raise notice 'PASS: outsider cannot post';
end $$;
reset role;

-- ------------------------------------------------------------------
-- 5. Data checks (as superuser: checks apply regardless of RLS).
-- ------------------------------------------------------------------
do $$
begin
  insert into public.feed_items (couple_id, added_by, url)
  values ('88888888-1111-0000-0000-000000000001', '88888888-0000-0000-0000-00000000000a', 'ftp://x.example');
  raise exception 'FAIL: non-http url accepted';
exception when check_violation then raise notice 'PASS: non-http url rejected';
end $$;
do $$
begin
  insert into public.feed_items (couple_id, added_by)
  values ('88888888-1111-0000-0000-000000000001', '88888888-0000-0000-0000-00000000000a');
  raise exception 'FAIL: item with no url and no note accepted';
exception when check_violation then raise notice 'PASS: empty item rejected';
end $$;
do $$
begin
  insert into public.feed_items (couple_id, added_by, note)
  values ('88888888-1111-0000-0000-000000000001', '88888888-0000-0000-0000-00000000000a', '   ');
  raise exception 'FAIL: blank note accepted';
exception when check_violation then raise notice 'PASS: blank note rejected';
end $$;
do $$
begin
  insert into public.feed_items (couple_id, added_by, note, collection)
  values ('88888888-1111-0000-0000-000000000001', '88888888-0000-0000-0000-00000000000a', 'x', 'bogus');
  raise exception 'FAIL: unknown collection accepted';
exception when check_violation then raise notice 'PASS: unknown collection rejected';
end $$;
do $$
begin
  insert into public.feed_items (couple_id, added_by, note, source)
  values ('88888888-1111-0000-0000-000000000001', '88888888-0000-0000-0000-00000000000a', 'x', 'myspace');
  raise exception 'FAIL: unknown source accepted';
exception when check_violation then raise notice 'PASS: unknown source rejected';
end $$;
do $$
begin
  insert into public.feed_items (couple_id, added_by, note)
  values ('88888888-1111-0000-0000-000000000001', '88888888-0000-0000-0000-00000000000a', repeat('x', 1001));
  raise exception 'FAIL: 1001-char note accepted';
exception when check_violation then raise notice 'PASS: over-long note rejected';
end $$;
do $$
begin
  insert into public.feed_comments (item_id, couple_id, author_id, body)
  values ('88888888-2222-0000-0000-000000000001', '88888888-1111-0000-0000-000000000001',
          '88888888-0000-0000-0000-00000000000a', '  ');
  raise exception 'FAIL: blank comment accepted';
exception when check_violation then raise notice 'PASS: blank comment rejected';
end $$;
do $$
begin
  insert into public.feed_reactions (item_id, user_id, reaction, couple_id)
  values ('88888888-2222-0000-0000-000000000001', '88888888-0000-0000-0000-00000000000a',
          'thumbs', '88888888-1111-0000-0000-000000000001');
  raise exception 'FAIL: unknown reaction accepted';
exception when check_violation then raise notice 'PASS: unknown reaction rejected';
end $$;

-- ------------------------------------------------------------------
-- 6. Triggers exist; the author can delete their own content.
-- ------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'on_feed_item_insert')
     or not exists (select 1 from pg_trigger where tgname = 'on_feed_comment_insert')
     or not exists (select 1 from pg_trigger where tgname = 'feed_items_guard') then
    raise exception 'FAIL: wall triggers missing';
  end if;
  raise notice 'PASS: wall triggers installed';
end $$;

set role authenticated;
set local request.jwt.claim.sub = '88888888-0000-0000-0000-00000000000a';
delete from public.feed_comments where id = '88888888-3333-0000-0000-000000000001';
delete from public.feed_items where id = '88888888-2222-0000-0000-000000000001';
reset role;
do $$
begin
  if exists (select 1 from public.feed_items where id = '88888888-2222-0000-0000-000000000001')
     or exists (select 1 from public.feed_comments where id = '88888888-3333-0000-0000-000000000001')
     or exists (select 1 from public.feed_reactions where item_id = '88888888-2222-0000-0000-000000000001') then
    raise exception 'FAIL: author could not delete their own content';
  end if;
  raise notice 'PASS: author deletes own item (reactions cascade) and comment';
end $$;

rollback;
