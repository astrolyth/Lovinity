-- "Ameen together" on the Dua for today card (design: Duas.dc.html).
-- One Ameen per person per local day; the spouse gets a content-free push.

create table if not exists public.dua_ameens (
  id        uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  user_id   uuid not null references public.users(id) on delete cascade,
  day       date not null,
  said_at   timestamptz not null default now(),
  unique (user_id, day)
);
create index if not exists dua_ameens_couple_day_idx on public.dua_ameens (couple_id, day desc);

alter table public.dua_ameens enable row level security;

drop policy if exists dua_ameens_select on public.dua_ameens;
create policy dua_ameens_select on public.dua_ameens
  for select using (public.is_couple_member(couple_id));
drop policy if exists dua_ameens_insert on public.dua_ameens;
create policy dua_ameens_insert on public.dua_ameens
  for insert with check (user_id = auth.uid() and public.is_couple_member(couple_id));

grant select, insert on public.dua_ameens to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    execute 'alter publication supabase_realtime add table public.dua_ameens';
  end if;
end $$;

create or replace function public.notify_dua_ameen()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_spouse uuid;
  v_name   text;
begin
  select case when member_a = new.user_id then member_b else member_a end
    into v_spouse from public.couples where id = new.couple_id;
  if v_spouse is null then return new; end if;
  select nullif(btrim(display_name), '') into v_name
    from public.users where id = new.user_id;
  perform public.dispatch_push(
    v_spouse, 'dua',
    left(coalesce(v_name, 'Your partner'), 60) || ' said Ameen 🤲',
    'Say Ameen together on today''s dua'
  );
  return new;
end;
$$;
revoke execute on function public.notify_dua_ameen() from public, anon, authenticated;

drop trigger if exists on_dua_ameen_insert on public.dua_ameens;
create trigger on_dua_ameen_insert
  after insert on public.dua_ameens
  for each row execute function public.notify_dua_ameen();
