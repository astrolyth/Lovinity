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

-- The couple's current question: the first APPROVED question they have not
-- both answered, in an order derived deterministically from the couple id --
-- so both partners resolve the same question with no stored cursor, and
-- different couples get a different sequence. Returns zero rows when the
-- couple has answered every approved question.
create or replace function public.get_current_question()
returns table (
  id uuid,
  question text,
  category text,
  language text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_couple uuid := public.current_couple();
begin
  if v_couple is null then raise exception 'no_couple'; end if;

  return query
  select q.id, q.question, q.category, q.language
    from public.daily_questions q
   where q.status = 'approved'
     and (
       select count(distinct qa.author_id)
         from public.question_answers qa
        where qa.couple_id = v_couple
          and qa.question_id = q.id
     ) < 2
   -- hashtext is deterministic for a given input, so this ordering is stable
   -- across calls and identical for both partners. q.id breaks ties.
   order by hashtext(v_couple::text || q.id::text), q.id
   limit 1;
end;
$$;

grant execute on function public.get_current_question() to authenticated;
