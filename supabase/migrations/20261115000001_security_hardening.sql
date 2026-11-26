-- Security hardening from the 2026-11-15 audit.
--   1. dispatch_push was callable by any signed-in user (Postgres grants
--      EXECUTE to PUBLIC by default), so anyone could push any text to anyone.
--   2. couples_update_members let a member rewrite member_a/member_b/status.
--      The app never updates couples, so the right is removed outright.
--   3. get_couple_scoreboard exempted days from PRIVATE cycle records in the
--      spouse's row too, so varying p_window_days revealed the private cycle
--      days one by one. The spouse's row now only uses shared records.
--   4. accept_pairing_invite could put one user in two active couples when
--      two accepts involving the same user ran at once.
--   5. Personal (owner-authored) couple tables let either spouse update or
--      delete the other's rows; messages/conversations accepted direct writes
--      that only the SECURITY DEFINER RPCs should make.

------------------------------------------------------------------
-- 1. dispatch_push and friends: internal only.
------------------------------------------------------------------
revoke execute on function public.dispatch_push(uuid, text, text, text)
  from public, anon, authenticated;
revoke execute on function public.notify_pairing_active() from public, anon, authenticated;
-- Only called from create_pairing_invite (SECURITY DEFINER), never as an RPC.
revoke execute on function public.generate_invite_code() from public, anon, authenticated;

------------------------------------------------------------------
-- 2. couples: read-only for members; rows change only via SECURITY DEFINER RPCs.
------------------------------------------------------------------
drop policy if exists couples_update_members on public.couples;
revoke update on public.couples from authenticated;

------------------------------------------------------------------
-- 3. Scoreboard: same as 20260806000001 except the cycle exemption filter.
------------------------------------------------------------------
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
  v_pc      integer;
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
    select u.timezone into v_tz from public.users u where u.id = m;
    begin
      v_today := (now() at time zone coalesce(v_tz, 'UTC'))::date;
    exception when others then
      v_today := coalesce(p_today, current_date);
    end;

    v_to   := v_today - 1;
    v_from := v_to - (p_window_days - 1);

    v_prayed := 0; v_due := 0; v_cur := 0; v_longest := 0; v_run := 0; v_broken := false;
    v_day := v_to;
    while v_day >= v_from loop
      -- Own row: every cycle record counts. Spouse's row: only records the
      -- owner shared, so the numbers reveal nothing RLS would hide.
      select exists (
        select 1 from public.cycle_records c
        where c.user_id = m
          and (m = v_uid or c.visibility = 'shared')
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

------------------------------------------------------------------
-- 4. accept_pairing_invite: serialize on both users.
------------------------------------------------------------------
create or replace function public.accept_pairing_invite(p_code text)
returns public.couples
language plpgsql volatile security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_invite  public.pairing_invites%rowtype;
  v_a       uuid;
  v_b       uuid;
  v_couple  public.couples%rowtype;
  v_my_gender      text;
  v_inviter_gender text;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select * into v_invite from public.pairing_invites
   where code = upper(trim(p_code)) for update;
  if not found then raise exception 'invite_not_found'; end if;
  if v_invite.consumed_at is not null then raise exception 'invite_already_used'; end if;
  if v_invite.expires_at < now() then raise exception 'invite_expired'; end if;
  if v_invite.inviter_id = v_uid then raise exception 'cannot_pair_with_self'; end if;

  if v_invite.inviter_id < v_uid then
    v_a := v_invite.inviter_id; v_b := v_uid;
  else
    v_a := v_uid; v_b := v_invite.inviter_id;
  end if;

  -- Two accepts touching the same user (A accepts B's invite while C accepts
  -- A's) must not both pass the "not already paired" checks below. Lock both
  -- users in a fixed order so concurrent calls serialize without deadlock.
  perform pg_advisory_xact_lock(hashtext('pair:' || v_a::text));
  perform pg_advisory_xact_lock(hashtext('pair:' || v_b::text));

  if exists (select 1 from public.couples
             where v_uid in (member_a, member_b) and status = 'active') then
    raise exception 'already_paired';
  end if;
  if exists (select 1 from public.couples
             where v_invite.inviter_id in (member_a, member_b) and status = 'active') then
    raise exception 'inviter_already_paired';
  end if;

  select gender into v_my_gender      from public.users where id = v_uid;
  select gender into v_inviter_gender from public.users where id = v_invite.inviter_id;
  if v_my_gender is null or v_inviter_gender is null then
    raise exception 'gender_required';
  end if;
  if v_my_gender = v_inviter_gender then
    raise exception 'same_gender_pairing';
  end if;

  update public.pairing_invites
     set consumed_at = now(), consumed_by = v_uid
   where code = v_invite.code;

  insert into public.couples (member_a, member_b)
       values (v_a, v_b) returning * into v_couple;
  return v_couple;
end;
$$;

grant execute on function public.accept_pairing_invite(text) to authenticated;

------------------------------------------------------------------
-- 5a. Personal tables: members read, only the author writes. Genuinely
--     shared tables (calendar, grocery, budgets, plans, ...) keep the
--     blanket couple policy on purpose.
------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('prayer_logs',            'prayer_logs_couple',            'user_id'),
      ('question_answers',       'question_answers_couple_rls',   'author_id'),
      ('conflict_logs',          'conflict_logs_couple_rls',      'author_id'),
      ('trust_vault_items',      'trust_vault_items_couple_rls',  'added_by'),
      ('mood_checkins',          'mood_checkins_couple_rls',      'user_id'),
      ('quran_progress',         'quran_progress_couple_rls',     'user_id'),
      ('hifdh_recitations',      'hifdh_recitations_couple_rls',  'user_id'),
      ('love_language_profiles', 'love_language_profiles_couple_rls', 'user_id'),
      ('ramadan_logs',           'ramadan_logs_couple_rls',       'user_id'),
      ('sadaqah_entries',        'sadaqah_entries_couple_rls',    'user_id'),
      ('dhikr_contributions',    'dhikr_contributions_couple_rls','user_id'),
      ('presence_taps',          'presence_taps_couple_rls',      'sender_id'),
      ('message_reactions',      'message_reactions_couple_rls',  'user_id')
    ) as t(tbl, old_policy, owner_col)
  loop
    execute format('drop policy if exists %I on public.%I', r.old_policy, r.tbl);
    execute format(
      'create policy %I on public.%I for select using (public.is_couple_member(couple_id))',
      r.tbl || '_select', r.tbl);
    execute format(
      'create policy %I on public.%I for insert with check (public.is_couple_member(couple_id) and %I = auth.uid())',
      r.tbl || '_insert', r.tbl, r.owner_col);
    execute format(
      'create policy %I on public.%I for update using (%I = auth.uid()) with check (public.is_couple_member(couple_id) and %I = auth.uid())',
      r.tbl || '_update', r.tbl, r.owner_col, r.owner_col);
    execute format(
      'create policy %I on public.%I for delete using (%I = auth.uid())',
      r.tbl || '_delete', r.tbl, r.owner_col);
  end loop;
end $$;

------------------------------------------------------------------
-- 5b. messages / conversations are written only by send_message,
--     mark_delivered, mark_read and get_or_create_conversation.
------------------------------------------------------------------
revoke insert, update, delete on public.messages from authenticated;
revoke insert, update, delete on public.conversations from authenticated;
