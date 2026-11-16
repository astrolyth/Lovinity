-- psql assertion script for 20261116000002_wall_media.sql (rolled back).
-- Run: psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/wall_media_test.sql
begin;
-- storage blocks direct DELETE via a trigger; skip triggers (RLS still applies) to test the policy.
set local session_replication_role = replica;

insert into auth.users (id) values
  ('77777777-0000-0000-0000-00000000000a'),
  ('77777777-0000-0000-0000-00000000000b'),
  ('77777777-0000-0000-0000-00000000000c');
insert into public.couples (id, member_a, member_b) values (
  '77777777-1111-0000-0000-000000000001',
  '77777777-0000-0000-0000-00000000000a',
  '77777777-0000-0000-0000-00000000000b');

-- (a) member A posts a photo with no url/note; (b) empty row is rejected
set role authenticated;
set local request.jwt.claim.sub = '77777777-0000-0000-0000-00000000000a';
insert into public.feed_items (id, couple_id, added_by, source, media_url, media_mime)
values ('77777777-2222-0000-0000-000000000001',
        '77777777-1111-0000-0000-000000000001',
        '77777777-0000-0000-0000-00000000000a', 'photo',
        '77777777-1111-0000-0000-000000000001/77777777-2222-0000-0000-000000000001/media.jpg',
        'image/jpeg');
do $$
begin
  raise notice 'PASS: member inserted a photo item without url or note';
  begin
    insert into public.feed_items (couple_id, added_by)
    values ('77777777-1111-0000-0000-000000000001',
            '77777777-0000-0000-0000-00000000000a');
    raise exception 'FAIL: empty item accepted';
  exception when check_violation then
    raise notice 'PASS: empty item rejected';
  end;
  begin
    insert into public.feed_items (couple_id, added_by, source, media_url, media_mime)
    values ('77777777-1111-0000-0000-000000000001',
            '77777777-0000-0000-0000-00000000000a', 'video', 'x/y/media.mp4', 'image/png');
    raise exception 'FAIL: bad mime accepted';
  exception when check_violation then
    raise notice 'PASS: bad media_mime rejected';
  end;
end $$;

-- (c) storage: member inserts; outsider denied
insert into storage.objects (bucket_id, name, owner)
values ('wall-media', '77777777-1111-0000-0000-000000000001/x/media.jpg',
        '77777777-0000-0000-0000-00000000000a');
reset role;
set role authenticated;
set local request.jwt.claim.sub = '77777777-0000-0000-0000-00000000000c';
do $$
begin
  if exists (select 1 from storage.objects where bucket_id = 'wall-media') then
    raise exception 'FAIL: outsider can read wall-media';
  end if;
  begin
    insert into storage.objects (bucket_id, name, owner)
    values ('wall-media', '77777777-1111-0000-0000-000000000001/y/media.jpg',
            '77777777-0000-0000-0000-00000000000c');
    raise exception 'FAIL: outsider inserted';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: outsider cannot read or insert wall-media';
end $$;
reset role;

-- spouse B reads but cannot delete A's object (d)
set role authenticated;
set local request.jwt.claim.sub = '77777777-0000-0000-0000-00000000000b';
do $$
declare n int;
begin
  if not exists (select 1 from storage.objects where bucket_id = 'wall-media') then
    raise exception 'FAIL: spouse cannot read';
  end if;
  delete from storage.objects where bucket_id = 'wall-media'; get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: spouse deleted author object'; end if;
  raise notice 'PASS: spouse reads but cannot delete author object';
end $$;
reset role;

set role authenticated;
set local request.jwt.claim.sub = '77777777-0000-0000-0000-00000000000a';
do $$
declare n int;
begin
  delete from storage.objects where bucket_id = 'wall-media'; get diagnostics n = row_count;
  if n <> 1 then raise exception 'FAIL: author could not delete'; end if;
  raise notice 'PASS: author deleted own object';
end $$;
reset role;

rollback;
