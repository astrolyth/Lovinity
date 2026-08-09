-- Halal date ideas: a reviewed library, plus what each couple saves from it.
--
-- Two tables because they have genuinely different lifetimes and audiences: the
-- library is shared content behind an approval gate, and the saves are private
-- couple data. Folding them together would either expose one couple's plans to
-- everyone or force the library to be duplicated per couple.
--
-- Long-distance couples are served by `setting = 'virtual'` here plus the
-- existing `watch_together_sessions` table for the synchronised-media part,
-- rather than a second parallel mechanism.

create table if not exists public.date_ideas (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  description text not null,
  -- Where it happens. 'virtual' is what makes this usable while apart.
  setting     text not null default 'home'
              check (setting in ('home', 'out', 'virtual')),
  category    text,
  -- Rough planning effort and spend, so a tired Tuesday and a planned weekend
  -- surface different suggestions.
  effort      text not null default 'low'
              check (effort in ('low', 'medium', 'high')),
  cost_band   text not null default 'free'
              check (cost_band in ('free', 'low', 'medium', 'high')),
  approved    boolean not null default false,
  created_at  timestamptz not null default now()
);

create index if not exists date_ideas_browse_idx
  on public.date_ideas (setting, effort) where approved;

alter table public.date_ideas enable row level security;
grant select on public.date_ideas to authenticated;

-- Approval gate, as with the other content libraries: these are generated
-- suggestions, and an unreviewed one reaching a couple is the failure mode.
create policy date_ideas_read on public.date_ideas
  for select using (approved);

create table if not exists public.date_idea_saves (
  id           uuid primary key default gen_random_uuid(),
  couple_id    uuid not null references public.couples(id) on delete cascade,
  idea_id      uuid not null references public.date_ideas(id) on delete cascade,
  saved_by     uuid not null references public.users(id) on delete cascade,
  -- Set when the couple schedules it; null means saved but not yet planned.
  planned_for  date,
  completed_at timestamptz,
  notes        text,
  created_at   timestamptz not null default now(),
  unique (couple_id, idea_id)
);

create index if not exists date_idea_saves_couple_idx
  on public.date_idea_saves (couple_id, planned_for);

alter table public.date_idea_saves enable row level security;
grant select, insert, update, delete on public.date_idea_saves to authenticated;

-- Standard couple scoping: either spouse may save, plan, or complete a date.
-- Deliberately NOT author-scoped -- planning a date together is the point.
create policy date_idea_saves_couple_rls on public.date_idea_saves
  for all
  using (public.is_couple_member(couple_id))
  with check (public.is_couple_member(couple_id));

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      execute 'alter publication supabase_realtime add table public.date_idea_saves';
    exception
      when duplicate_object then null;
    end;
  end if;
end $$;

alter table public.date_idea_saves replica identity full;
