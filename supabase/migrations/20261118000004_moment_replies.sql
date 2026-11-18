-- Moment replies: quick emoji reactions and short comments on a moment.
-- One table, exactly one of emoji/body per row.

create table public.moment_replies (
  id          uuid primary key default gen_random_uuid(),
  moment_id   uuid not null references public.moments(id) on delete cascade,
  couple_id   uuid not null references public.couples(id) on delete cascade,
  author_id   uuid not null references public.users(id) on delete cascade,
  emoji       text check (emoji in ('❤️', '😂', '😮', '😢', '🔥', '🤲')),
  body        text check (body is null or length(btrim(body)) between 1 and 300),
  created_at  timestamptz not null default now(),
  constraint moment_replies_one_kind check ((emoji is null) <> (body is null))
);

create index moment_replies_moment_idx on public.moment_replies (moment_id, created_at);
create index moment_replies_couple_idx on public.moment_replies (couple_id);
-- One of each emoji per person per moment (tapping again removes it).
create unique index moment_replies_one_emoji
  on public.moment_replies (moment_id, author_id, emoji) where emoji is not null;

alter table public.moment_replies enable row level security;

create policy moment_replies_select on public.moment_replies
  for select using (public.is_couple_member(couple_id));
-- couple_id must be the moment's own couple, so a reply can't leak across couples.
create policy moment_replies_insert on public.moment_replies
  for insert with check (
    author_id = auth.uid()
    and public.is_couple_member(couple_id)
    and exists (select 1 from public.moments m
                 where m.id = moment_id and m.couple_id = moment_replies.couple_id)
  );
create policy moment_replies_delete on public.moment_replies
  for delete using (author_id = auth.uid());

grant select, insert, delete on public.moment_replies to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    execute 'alter publication supabase_realtime add table public.moment_replies';
  end if;
end $$;

-- Push the spouse. Canned copy only, never the comment text.
create or replace function public.notify_moment_reply()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_spouse uuid;
  v_name   text;
begin
  select case when member_a = new.author_id then member_b else member_a end
    into v_spouse
    from public.couples where id = new.couple_id;
  if v_spouse is null then
    return new;
  end if;
  select nullif(btrim(display_name), '') into v_name
    from public.users where id = new.author_id;
  perform public.dispatch_push(
    v_spouse, 'moment',
    left(coalesce(v_name, 'Your partner'), 60)
      || case when new.emoji is not null then ' reacted ' || new.emoji
              else ' replied' end,
    'On your moment 📸'
  );
  return new;
end;
$$;

drop trigger if exists on_moment_reply_insert on public.moment_replies;
create trigger on_moment_reply_insert
  after insert on public.moment_replies
  for each row execute function public.notify_moment_reply();
