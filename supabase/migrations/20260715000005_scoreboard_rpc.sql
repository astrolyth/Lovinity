-- Cycle-aware couple scoreboard, computed server-side so each member's own
-- cycle exemptions apply without exposing private cycle rows to the spouse.
create or replace function public.get_couple_scoreboard(p_window_days integer default 30)
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
  v_to      := current_date - 1;                  -- completed days only
  v_from    := v_to - (p_window_days - 1);
  v_members := array[v_couple.member_a, v_couple.member_b];

  foreach m in array v_members loop
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

grant execute on function public.get_couple_scoreboard(integer) to authenticated;
