-- Question queue: questions are drawn from a per-couple queue that advances
-- only when BOTH partners have answered, instead of being assigned per
-- calendar date. Also adds a review-queue status so AI-generated questions
-- (see supabase/functions/generate-questions) never reach a couple until a
-- human approves them.
--
-- get_daily_content() is deliberately NOT modified -- verse and hadith stay
-- date-based. Only the question feature moves to the queue.

alter table public.daily_questions
  add column if not exists status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  add column if not exists source text not null default 'generated'
    check (source in ('seed', 'generated')),
  add column if not exists created_at timestamptz not null default now();

-- The pre-existing seeded questions are already in circulation: preserve
-- today's behavior exactly by approving them.
update public.daily_questions
   set status = 'approved', source = 'seed'
 where source = 'generated' and created_at <= now();

create index if not exists daily_questions_status_idx
  on public.daily_questions(status);
