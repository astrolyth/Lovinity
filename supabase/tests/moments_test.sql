-- psql assertion script for 20261118000003_moments.sql (rolled back).
-- Run: psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/moments_test.sql
begin;

insert into auth.users (id) values
  ('66666666-0000-0000-0000-00000000000a'),
  ('66666666-0000-0000-0000-00000000000b'),
  ('66666666-0000-0000-0000-00000000000c');
insert into public.couples (id, member_a, member_b) values (
  '66666666-1111-0000-0000-000000000001',
  '66666666-0000-0000-0000-00000000000a',
  '66666666-0000-0000-0000-00000000000b');
update public.users set timezone = 'UTC'
 where id in ('66666666-0000-0000-0000-00000000000a', '66666666-0000-0000-0000-00000000000b');

-- 1. Member A sends; path outside the couple folder and bad mime rejected.
set local role authenticated;
set local request.jwt.claim.sub = '66666666-0000-0000-0000-00000000000a';
insert into public.moments (id, couple_id, sender_id, media_path, media_mime)
values ('66666666-2222-0000-0000-000000000001',
        '66666666-1111-0000-0000-000000000001',
        '66666666-0000-0000-0000-00000000000a',
        '66666666-1111-0000-0000-000000000001/66666666-2222-0000-0000-000000000001/media.jpg',
        'image/jpeg');
do $$
begin
  begin
    insert into public.moments (couple_id, sender_id, media_path, media_mime)
    values ('66666666-1111-0000-0000-000000000001', '66666666-0000-0000-0000-00000000000a',
            'someone-else/x/media.jpg', 'image/jpeg');
    raise exception 'FAIL: path outside couple folder accepted';
  exception when check_violation then
    raise notice 'PASS: path outside couple folder rejected';
  end;
  begin
    insert into public.moments (couple_id, sender_id, media_path, media_mime)
    values ('66666666-1111-0000-0000-000000000001', '66666666-0000-0000-0000-00000000000a',
            '66666666-1111-0000-0000-000000000001/x/media.png', 'image/png');
    raise exception 'FAIL: bad mime accepted';
  exception when check_violation then
    raise notice 'PASS: bad mime rejected';
  end;
  begin
    insert into public.moments (couple_id, sender_id, media_path, media_mime)
    values ('66666666-1111-0000-0000-000000000001', '66666666-0000-0000-0000-00000000000b',
            '66666666-1111-0000-0000-000000000001/x/media.jpg', 'image/jpeg');
    raise exception 'FAIL: inserted as someone else';
  exception when insufficient_privilege then
    raise notice 'PASS: cannot send as spouse';
  end;
  -- Sender marking own moment viewed is a no-op.
  perform public.mark_moment_viewed('66666666-2222-0000-0000-000000000001');
  if (select viewed_at from public.moments where id = '66666666-2222-0000-0000-000000000001') is not null then
    raise exception 'FAIL: sender marked own moment viewed';
  end if;
  raise notice 'PASS: sender cannot mark own moment viewed';
end $$;

-- 2. Outsider sees nothing.
set local request.jwt.claim.sub = '66666666-0000-0000-0000-00000000000c';
do $$
begin
  if exists (select 1 from public.moments) then
    raise exception 'FAIL: outsider can read moments';
  end if;
  raise notice 'PASS: outsider sees no moments';
end $$;

-- 3. Spouse sees it and marks it viewed; cannot delete it.
set local request.jwt.claim.sub = '66666666-0000-0000-0000-00000000000b';
do $$
begin
  perform public.mark_moment_viewed('66666666-2222-0000-0000-000000000001');
  if (select viewed_at from public.moments where id = '66666666-2222-0000-0000-000000000001') is null then
    raise exception 'FAIL: spouse could not mark viewed';
  end if;
  delete from public.moments where id = '66666666-2222-0000-0000-000000000001';
  if not exists (select 1 from public.moments where id = '66666666-2222-0000-0000-000000000001') then
    raise exception 'FAIL: spouse deleted sender''s moment';
  end if;
  raise notice 'PASS: spouse marks viewed, cannot delete';
end $$;

-- 4. Clients cannot fire nudges.
do $$
begin
  begin
    perform public.send_moment_nudges();
    raise exception 'FAIL: client fired nudges';
  exception when insufficient_privilege then
    raise notice 'PASS: send_moment_nudges is server-only';
  end;
end $$;

reset role;

-- 5. Nudge targets: A just sent (skipped), B nudged at 12:00 UTC, nobody at 03:00,
--    B skipped once opted out.
do $$
declare
  noon timestamptz := date_trunc('day', now()) + interval '12 hours';
  v uuid[];
begin
  update public.moments set created_at = noon - interval '10 minutes'
   where id = '66666666-2222-0000-0000-000000000001';
  select array_agg(t) into v from public.moment_nudge_targets(noon) t
   where t in ('66666666-0000-0000-0000-00000000000a', '66666666-0000-0000-0000-00000000000b');
  if v is distinct from array['66666666-0000-0000-0000-00000000000b'::uuid] then
    raise exception 'FAIL: noon targets %', v;
  end if;
  if exists (select 1 from public.moment_nudge_targets(date_trunc('day', now()) + interval '3 hours') t
              where t in ('66666666-0000-0000-0000-00000000000a', '66666666-0000-0000-0000-00000000000b')) then
    raise exception 'FAIL: nudged at 3am';
  end if;
  insert into public.user_preferences (user_id, prefs)
  values ('66666666-0000-0000-0000-00000000000b', '{"moment_nudges": false}');
  if exists (select 1 from public.moment_nudge_targets(noon) t
              where t = '66666666-0000-0000-0000-00000000000b') then
    raise exception 'FAIL: opted-out user nudged';
  end if;
  if not exists (select 1 from cron.job where jobname = 'moment-nudges' and schedule = '0 * * * *') then
    raise exception 'FAIL: cron job missing';
  end if;
  raise notice 'PASS: nudge targets respect recent sends, waking hours, opt-out; cron scheduled';
end $$;

rollback;
