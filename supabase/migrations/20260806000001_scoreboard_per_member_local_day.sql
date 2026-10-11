-- Anchor each couple member's scoreboard window on THEIR OWN local day.
--
-- 20260720000001 fixed the first half of this bug: the window used to be
-- anchored on the database's UTC current_date, so it was wrong for every
-- non-UTC user. It accepted the CLIENT's local today (`p_today`) instead.
--
-- But it then applied that single caller-supplied date to BOTH members. The
-- caller's "today" is not their spouse's today. For a couple ten hours apart
-- (Toronto / Dhaka), when the husband opens the app:
--
--   * the window ends at HIS today - 1, so the wife's most recently COMPLETED
--     day is excluded entirely -- prayers she finished are simply not counted;
--   * and the day the window does end on is, for her, still in progress. It is
--     scored as a completed day, so her 2-of-5-so-far reads as a failed day.
--     `v_run` resets and `v_broken` is set -- her current streak is shown as
--     BROKEN on his screen while her own screen shows it intact.
--
-- Same class of falsehood the prayer log itself had: a row that exists and is
-- correct is presented as absence. Streaks are the most damaging place for it,
-- because a broken streak is a claim about someone's practice.
--
-- Fix: derive each member's local day from their own `users.timezone` inside
-- the loop. `p_today` is kept in the signature (so the existing Dart caller and
-- its RPC contract are untouched) but is now only a fallback for a member whose
-- timezone is null or unrecognised.
--
-- Signature is unchanged, so no drop/recreate dance is needed here -- but note
-- the PGRST203 lesson from the previous migration: any future change to the
-- ARGUMENT LIST must drop the old overload first.

create or replace function public.get_couple_scoreboard(
  p_window_days integer default 30,
  p_today       date default null
)
returns table (
  member_id      uuid,
  prayed         integer,
  due            integer,
  current_streak integer,
  longest_streak integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_couple  public.couples%rowtype;
  v_members uuid[];
  v_tz      text;
  v_today   date;
  v_from    date;
  v_to      date;
  v_day     date;
  m         uuid;
  v_exempt  boolean;
  v_pc      integer;   -- prayed count that day
  v_prayed  integer;
  v_due     integer;
  v_cur     integer;
  v_longest integer;
  v_run     integer;
  v_broken  boolean;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select * into v_couple from public.couples
    where v_uid in (member_a, member_b) and status = 'active' limit 1;
  if not found then raise exception 'not_paired'; end if;

  p_window_days := least(greatest(coalesce(p_window_days, 30), 1), 366);
  v_members := array[v_couple.member_a, v_couple.member_b];

  foreach m in array v_members loop
    -- Each member's own local day. `now() at time zone <bad zone>` raises,
    -- and a single corrupt profile row must not take down the whole
    -- scoreboard, so fall back to the caller's date on any failure.
    select u.timezone into v_tz from public.users u where u.id = m;
    begin
      v_today := (now() at time zone coalesce(v_tz, 'UTC'))::date;
    exception when others then
      v_today := coalesce(p_today, current_date);
    end;

    -- Completed days only, relative to THIS member's local day.
    v_to   := v_today - 1;
    v_from := v_to - (p_window_days - 1);

    v_prayed := 0; v_due := 0; v_cur := 0; v_longest := 0; v_run := 0; v_broken := false;
    v_day := v_to;
    while v_day >= v_from loop
      select exists (
        select 1 from public.cycle_records c
        where c.user_id = m
          and c.started_on <= v_day
          and (c.ended_on is null or c.ended_on >= v_day)
      ) into v_exempt;

      if not v_exempt then
        select count(*) into v_pc from public.prayer_logs pl
          where pl.user_id = m and pl.date = v_day and pl.status = 'prayed';
        v_due := v_due + 5;
        v_prayed := v_prayed + v_pc;
        if v_pc >= 5 then
          v_run := v_run + 1;
          if v_run > v_longest then v_longest := v_run; end if;
          if not v_broken then v_cur := v_run; end if;
        else
          v_run := 0;
          v_broken := true;
        end if;
      end if;

      v_day := v_day - 1;
    end loop;

    member_id := m; prayed := v_prayed; due := v_due;
    current_streak := v_cur; longest_streak := v_longest;
    return next;
  end loop;
end;
$$;

grant execute on function public.get_couple_scoreboard(integer, date) to authenticated;
