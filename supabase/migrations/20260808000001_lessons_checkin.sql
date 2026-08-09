-- Co-studied lessons: check-in questions, and a reveal gate on the answers.
--
-- `learning_lessons` had nowhere to store the two check-in questions, so the
-- feature had nothing to render. And `learning_progress` carried only the
-- blanket `is_couple_member(couple_id)` policy from the bulk loop in
-- 20260712000002, which means each spouse could read the other's answers the
-- instant they were written.
--
-- That second point is the important one. The product promise is that you each
-- answer, and then you compare. If you can read your spouse's answer first, the
-- check-in doesn't fail loudly -- it quietly stops being a check-in and becomes
-- copying. Hiding the answer in the widget is not a fix: the row is already on
-- the device, and anyone calling the REST endpoint sees it. So the gate lives
-- here.

alter table public.learning_lessons
  add column if not exists questions jsonb not null default '[]'::jsonb;

-- Exactly two questions, or none at all. Two is the product promise; silently
-- accepting one or five would let seeded content drift out of the shape the UI
-- is built around.
alter table public.learning_lessons
  drop constraint if exists learning_lessons_questions_shape;
alter table public.learning_lessons
  add constraint learning_lessons_questions_shape
  check (
    jsonb_typeof(questions) = 'array'
    and jsonb_array_length(questions) in (0, 2)
  );

-- Has the caller finished this lesson?
--
-- SECURITY DEFINER is required, not stylistic. The reveal policy below needs to
-- look at `learning_progress` in order to decide who may read
-- `learning_progress`, and an inline sub-select does exactly that -- which
-- re-triggers the policy on the inner query and Postgres rejects the whole
-- thing with "infinite recursion detected in policy" (42P17). Running the
-- lookup as the function owner steps outside RLS and breaks the cycle, the same
-- way `is_couple_member` does for couple membership.
--
-- Safe despite bypassing RLS: it takes no user-controlled identity, answers
-- only about `auth.uid()`, and returns a boolean rather than any row content.
create or replace function public.has_completed_lesson(
  p_couple_id uuid,
  p_lesson_id uuid
)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.learning_progress
    where couple_id = p_couple_id
      and lesson_id = p_lesson_id
      and user_id = auth.uid()
      and completed_at is not null
  );
$$;

grant execute on function public.has_completed_lesson(uuid, uuid) to authenticated;

drop policy if exists learning_progress_couple_rls on public.learning_progress;
drop policy if exists learning_progress_read on public.learning_progress;
drop policy if exists learning_progress_insert on public.learning_progress;
drop policy if exists learning_progress_update on public.learning_progress;
drop policy if exists learning_progress_delete on public.learning_progress;

-- Read: your own progress always. Your spouse's only once YOU have completed
-- that same lesson -- which is precisely the moment comparing answers becomes
-- the point rather than a shortcut.
create policy learning_progress_read on public.learning_progress
  for select using (
    public.is_couple_member(couple_id)
    and (
      user_id = auth.uid()
      or public.has_completed_lesson(couple_id, lesson_id)
    )
  );

-- Write: only ever as yourself. Without pinning `user_id` to the caller, one
-- spouse could submit answers under the other's name and unlock the reveal
-- without having answered anything.
create policy learning_progress_insert on public.learning_progress
  for insert with check (
    public.is_couple_member(couple_id) and user_id = auth.uid()
  );

create policy learning_progress_update on public.learning_progress
  for update using (
    public.is_couple_member(couple_id) and user_id = auth.uid()
  ) with check (
    public.is_couple_member(couple_id) and user_id = auth.uid()
  );

create policy learning_progress_delete on public.learning_progress
  for delete using (
    public.is_couple_member(couple_id) and user_id = auth.uid()
  );

create index if not exists learning_progress_couple_lesson_idx
  on public.learning_progress (couple_id, lesson_id);

-- The lesson library is only worth serving once it has been reviewed. Lessons
-- are hand-authored rather than generated (they make religious claims), but the
-- flag keeps the serving path identical to the other content libraries.
alter table public.learning_lessons
  add column if not exists approved boolean not null default false;

drop policy if exists learning_lessons_read on public.learning_lessons;
create policy learning_lessons_read on public.learning_lessons
  for select using (approved);
