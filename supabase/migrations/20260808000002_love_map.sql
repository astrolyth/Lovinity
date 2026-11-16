-- "How well do you know your spouse?" — make the feature possible at all.
--
-- As modelled, it cannot work. `love_map_answers` stores a `guess` and an
-- `is_correct` flag, but NOTHING stores the spouse's actual answer -- so there
-- is nothing to compare a guess against and no way for `is_correct` to ever be
-- computed. It also has no `subject_id`, so a guess does not record who it was
-- about; in a two-person game that is recoverable by elimination, but it makes
-- the row meaningless on its own and blocks any future "guess about either of
-- us" mode.
--
-- Two additions: a place to put the truth, and a link from guess to truth.

-- Link a guess to the truth it is about.
--
-- MUST come before the policies below: `love_map_truths_read` references
-- `love_map_answers.subject_id`, and Postgres resolves column references when
-- the policy is created, not when it is first evaluated.
alter table public.love_map_answers
  add column if not exists subject_id uuid references public.users(id) on delete cascade;

create index if not exists love_map_answers_lookup_idx
  on public.love_map_answers (couple_id, quiz_id, subject_id);

create table if not exists public.love_map_truths (
  id          uuid primary key default gen_random_uuid(),
  couple_id   uuid not null references public.couples(id) on delete cascade,
  quiz_id     uuid not null references public.love_map_quizzes(id) on delete cascade,
  -- Whose answer this is. The subject answers about themselves; the spouse
  -- guesses it.
  subject_id  uuid not null references public.users(id) on delete cascade,
  answer      text not null,
  created_at  timestamptz not null default now(),
  unique (couple_id, quiz_id, subject_id)
);

create index if not exists love_map_truths_couple_idx
  on public.love_map_truths (couple_id, quiz_id);

alter table public.love_map_truths enable row level security;
grant select, insert, update, delete on public.love_map_truths to authenticated;

-- Postgres has no `create policy if not exists`, so drop first. Keeps the
-- migration re-runnable against a database where an earlier attempt applied
-- some of it.
drop policy if exists love_map_truths_read on public.love_map_truths;
drop policy if exists love_map_truths_write on public.love_map_truths;
drop policy if exists love_map_truths_update on public.love_map_truths;
drop policy if exists love_map_answers_read on public.love_map_answers;
drop policy if exists love_map_answers_insert on public.love_map_answers;
drop policy if exists love_map_answers_update on public.love_map_answers;
drop policy if exists love_map_answers_delete on public.love_map_answers;

-- The reveal gate, and the whole reason this table is not covered by the blanket
-- couple policy: the guesser must not be able to read the answer they are about
-- to guess. Visible only to the subject, or to a partner who has already
-- committed a guess for that exact question.
create policy love_map_truths_read on public.love_map_truths
  for select using (
    public.is_couple_member(couple_id)
    and (
      subject_id = auth.uid()
      or exists (
        select 1 from public.love_map_answers a
        where a.couple_id = love_map_truths.couple_id
          and a.quiz_id = love_map_truths.quiz_id
          and a.subject_id = love_map_truths.subject_id
          and a.guesser_id = auth.uid()
      )
    )
  );

-- You may only ever record the truth about yourself.
create policy love_map_truths_write on public.love_map_truths
  for insert with check (
    public.is_couple_member(couple_id) and subject_id = auth.uid()
  );

create policy love_map_truths_update on public.love_map_truths
  for update using (
    public.is_couple_member(couple_id) and subject_id = auth.uid()
  ) with check (
    public.is_couple_member(couple_id) and subject_id = auth.uid()
  );

-- Guesses are written as yourself only; otherwise a player could forge a guess
-- in their spouse's name and unlock the truth above without playing.
drop policy if exists love_map_answers_couple_rls on public.love_map_answers;

create policy love_map_answers_read on public.love_map_answers
  for select using (public.is_couple_member(couple_id));

create policy love_map_answers_insert on public.love_map_answers
  for insert with check (
    public.is_couple_member(couple_id) and guesser_id = auth.uid()
  );

-- Grading happens after the reveal, by the guesser, on their own row.
create policy love_map_answers_update on public.love_map_answers
  for update using (
    public.is_couple_member(couple_id) and guesser_id = auth.uid()
  ) with check (
    public.is_couple_member(couple_id) and guesser_id = auth.uid()
  );

create policy love_map_answers_delete on public.love_map_answers
  for delete using (
    public.is_couple_member(couple_id) and guesser_id = auth.uid()
  );

-- Approval gate on the question library, mirroring
-- 20260803000001_daily_content_approved_only.sql. These questions are generated
-- rather than hand-written, and an unreviewed prompt reaching a couple is the
-- failure this prevents.
alter table public.love_map_quizzes
  add column if not exists approved boolean not null default false;

drop policy if exists love_map_quizzes_read on public.love_map_quizzes;
create policy love_map_quizzes_read on public.love_map_quizzes
  for select using (approved);

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      execute 'alter publication supabase_realtime add table public.love_map_truths';
    exception
      when duplicate_object then null;
    end;
  end if;
end $$;
