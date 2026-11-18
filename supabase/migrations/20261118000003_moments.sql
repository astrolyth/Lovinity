-- Moments: live-camera photo / 3-second video updates between spouses, plus
-- an hourly push nudge during each member's waking hours.
-- Paths (bucket 'moments'): <couple_id>/<moment_id>/media.jpg|media.mp4, video thumb .../thumb.jpg

create table public.moments (
  id          uuid primary key default gen_random_uuid(),
  couple_id   uuid not null references public.couples(id) on delete cascade,
  sender_id   uuid not null references public.users(id) on delete cascade,
  media_path  text not null,
  media_mime  text not null
              check (media_mime in ('image/jpeg', 'video/mp4', 'video/quicktime')),
  thumb_path  text,
  caption     text check (caption is null or length(caption) <= 120),
  viewed_at   timestamptz,
  created_at  timestamptz not null default now(),
  -- Paths must live under the couple's own folder.
  constraint moments_path_in_couple
    check (split_part(media_path, '/', 1) = couple_id::text
           and (thumb_path is null or split_part(thumb_path, '/', 1) = couple_id::text))
);

create index moments_couple_created_idx on public.moments (couple_id, created_at desc);
create index moments_sender_created_idx on public.moments (sender_id, created_at desc);

alter table public.moments enable row level security;

create policy moments_select on public.moments
  for select using (public.is_couple_member(couple_id));
create policy moments_insert on public.moments
  for insert with check (sender_id = auth.uid() and public.is_couple_member(couple_id));
create policy moments_delete on public.moments
  for delete using (sender_id = auth.uid());
-- No update policy: viewed_at changes only through mark_moment_viewed.

grant select, insert, delete on public.moments to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    execute 'alter publication supabase_realtime add table public.moments';
  end if;
end $$;

------------------------------------------------------------------
-- Recipient marks a moment seen (Snapchat-style "opened"). Senders cannot
-- mark their own; already-seen keeps the first view time.
------------------------------------------------------------------
create or replace function public.mark_moment_viewed(p_id uuid)
returns void
language plpgsql volatile security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  update public.moments
     set viewed_at = now()
   where id = p_id
     and viewed_at is null
     and sender_id <> auth.uid()
     and public.is_couple_member(couple_id);
end;
$$;

grant execute on function public.mark_moment_viewed(uuid) to authenticated;

------------------------------------------------------------------
-- Storage: private bucket. 10 MB comfortably fits a 3 s 720p clip.
------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('moments', 'moments', false, 10485760,
        array['image/jpeg', 'video/mp4', 'video/quicktime'])
on conflict (id) do nothing;

create policy moments_media_select on storage.objects
  for select using (
    bucket_id = 'moments'
    and public.is_couple_member((storage.foldername(name))[1]::uuid)
  );

create policy moments_media_insert on storage.objects
  for insert with check (
    bucket_id = 'moments'
    and public.is_couple_member((storage.foldername(name))[1]::uuid)
  );

create policy moments_media_delete on storage.objects
  for delete using (
    bucket_id = 'moments'
    and owner = auth.uid()
    and public.is_couple_member((storage.foldername(name))[1]::uuid)
  );

------------------------------------------------------------------
-- Push the spouse on every new moment. Content-free copy only.
------------------------------------------------------------------
create or replace function public.notify_moment()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_spouse uuid;
  v_name   text;
begin
  select case when member_a = new.sender_id then member_b else member_a end
    into v_spouse
    from public.couples where id = new.couple_id;
  if v_spouse is null then
    return new;
  end if;
  select nullif(btrim(display_name), '') into v_name
    from public.users where id = new.sender_id;
  perform public.dispatch_push(
    v_spouse, 'moment',
    left(coalesce(v_name, 'Your partner'), 60) || ' sent a moment',
    'Tap to see what they''re up to 📸'
  );
  return new;
end;
$$;

drop trigger if exists on_moment_insert on public.moments;
create trigger on_moment_insert
  after insert on public.moments
  for each row execute function public.notify_moment();

------------------------------------------------------------------
-- Hourly nudge: members of active couples, 09:00–21:59 in their own
-- timezone (unknown/invalid tz => UTC), who haven't sent a moment in the
-- last 55 minutes and haven't turned prefs.moment_nudges off.
------------------------------------------------------------------
create or replace function public.moment_nudge_targets(p_now timestamptz default now())
returns setof uuid
language sql stable security definer
set search_path = public
as $$
  select m.uid
    from public.couples c
    cross join lateral (values (c.member_a), (c.member_b)) as m(uid)
    join public.users u on u.id = m.uid
    left join pg_timezone_names tz on tz.name = u.timezone
    left join public.user_preferences p on p.user_id = m.uid
   where c.status = 'active'
     and coalesce((p.prefs->>'moment_nudges')::boolean, true)
     and extract(hour from p_now at time zone coalesce(tz.name, 'UTC')) between 9 and 21
     and not exists (
       select 1 from public.moments mo
        where mo.sender_id = m.uid
          and mo.created_at > p_now - interval '55 minutes'
     );
$$;

create or replace function public.send_moment_nudges()
returns integer
language plpgsql volatile security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_n   integer := 0;
begin
  for v_uid in select public.moment_nudge_targets() loop
    perform public.dispatch_push(
      v_uid, 'moment_nudge',
      'What are you up to?',
      'Send your partner a quick moment 📸'
    );
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- Server-only: no client can trigger a nudge storm.
revoke all on function public.moment_nudge_targets(timestamptz) from public, anon, authenticated;
revoke all on function public.send_moment_nudges() from public, anon, authenticated;

create extension if not exists pg_cron;

-- Named job: re-running updates rather than duplicates it.
select cron.schedule('moment-nudges', '0 * * * *', $$select public.send_moment_nudges()$$);
