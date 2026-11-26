-- Cycle screen "How are you today?" mood chips (design: Cycle.dc.html).
-- One row per wife per local day. Same privacy as cycle_records: only she
-- writes, her husband reads a day only when she shares it.

create table if not exists public.cycle_moods (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.users(id) on delete cascade,
  couple_id  uuid not null references public.couples(id) on delete cascade,
  day        date not null,
  moods      text[] not null default '{}'
             check (moods <@ array['calm','energetic','tired','cramps','headache','low']::text[]),
  shared     boolean not null default false,
  updated_at timestamptz not null default now(),
  unique (user_id, day)
);
create index if not exists cycle_moods_couple_day_idx on public.cycle_moods (couple_id, day desc);

alter table public.cycle_moods enable row level security;

drop policy if exists cycle_moods_own on public.cycle_moods;
create policy cycle_moods_own on public.cycle_moods
  for all
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and public.is_couple_member(couple_id)
    and exists (select 1 from public.users u where u.id = auth.uid() and u.gender = 'female')
  );

drop policy if exists cycle_moods_spouse_shared_read on public.cycle_moods;
create policy cycle_moods_spouse_shared_read on public.cycle_moods
  for select using (shared and public.is_couple_member(couple_id) and user_id <> auth.uid());

grant select, insert, update, delete on public.cycle_moods to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    execute 'alter publication supabase_realtime add table public.cycle_moods';
  end if;
end $$;
