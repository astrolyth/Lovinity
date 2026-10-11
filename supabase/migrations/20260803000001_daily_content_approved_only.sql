-- Close the second, unfiltered path around the question review queue.
--
-- 20260802000003_question_queue.sql added a `status` column to
-- daily_questions so AI-generated questions (supabase/functions/
-- generate-questions) land as 'pending' and never reach a couple until a
-- human approves them. `get_current_question()` -- the queue RPC the app now
-- reads -- filters on `status = 'approved'`.
--
-- `get_daily_content()` did NOT. Its question pick was a bare
--     select id into v_qod from public.daily_questions order by random();
-- with no status filter at all, so the moment the generator runs it starts
-- writing unreviewed questions into daily_content.question_id, and any build
-- still reading that field renders them. Worse than merely "unapproved": a
-- question a human explicitly REJECTED stays in the table and remains
-- equally selectable. Measured against the local DB with one 'pending' and
-- one 'rejected' row present, 400 samples of that exact statement produced
-- 55 unapproved picks.
--
-- This recreates the function with `where status = 'approved'` on that one
-- select. NOTHING else about it changes: verse and hadith stay date-based
-- and unfiltered, the deterministic per-(couple, date) seed is untouched,
-- and the fast path / upsert behave exactly as before.
--
-- daily_content.question_id itself is left in place and still hydrated --
-- retiring it is a separate follow-up. This migration only removes the
-- hazard.

create or replace function public.get_daily_content(p_date date default null)
returns table (
  the_date date,
  verse_id uuid,
  hadith_id uuid,
  question_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple  uuid := public.current_couple();
  v_date    date := coalesce(p_date, current_date);
  v_verse   uuid;
  v_hadith  uuid;
  v_qod     uuid;
  v_seed    integer;
  v_row     public.daily_content%rowtype;
begin
  if v_couple is null then
    raise exception 'no_couple';
  end if;

  -- Fast path: already assigned for this couple + date.
  select * into v_row from public.daily_content
    where couple_id = v_couple and daily_content.date = v_date;

  if found then
    the_date := v_row.date;
    verse_id := v_row.verse_id;
    hadith_id := v_row.hadith_id;
    question_id := v_row.question_id;
    return next;
    return;
  end if;

  -- Deterministic per (couple, date) so both members always see the same picks
  -- even if they call this at the same time. hashtext handles the seed.
  v_seed := abs(hashtext(v_couple::text || v_date::text));
  perform setseed(least(0.99999, greatest(0, (v_seed::double precision / 2147483648.0))));

  select id into v_verse from public.verses order by random() limit 1;
  select id into v_hadith from public.hadiths order by random() limit 1;
  -- The review queue applies here too: only human-approved questions are
  -- eligible. 'pending' (awaiting review) and 'rejected' (refused by a
  -- human) are both excluded. v_qod stays null when nothing is approved,
  -- which is the same shape this already produced for an empty library.
  select id into v_qod from public.daily_questions
    where daily_questions.status = 'approved'
    order by random() limit 1;

  insert into public.daily_content (couple_id, date, verse_id, hadith_id, question_id)
    values (v_couple, v_date, v_verse, v_hadith, v_qod)
    on conflict (couple_id, date) do update set
      verse_id = excluded.verse_id,
      hadith_id = excluded.hadith_id,
      question_id = excluded.question_id
    returning * into v_row;

  the_date := v_row.date;
  verse_id := v_row.verse_id;
  hadith_id := v_row.hadith_id;
  question_id := v_row.question_id;
  return next;
end;
$$;

grant execute on function public.get_daily_content(date) to authenticated;
