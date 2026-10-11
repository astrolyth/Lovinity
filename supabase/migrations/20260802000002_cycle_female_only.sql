-- Only a female-gendered user may create a cycle_records row -- cycle
-- tracking (starting/ending a period) is the wife's alone; the RLS in
-- 20260715000002_cycle_rls.sql was couple-membership-based only and didn't
-- stop a male-gendered partner from inserting one. The app already hides
-- the start/end controls from a male account in the UI (isWifeProvider
-- gate on HomeScreen and CycleScreen), but nothing enforced it server-side.
--
-- Mirrors the gender-check style already used for pairing
-- (accept_pairing_invite / create_pairing_invite in 20260715000001_roles.sql
-- and 20260731000001_pairing_invite_gender_gate.sql): a plain `exists`
-- lookup against public.users.gender.
--
-- Extends cycle_records_own's WITH CHECK rather than replacing the whole
-- RLS surface, so:
--   * cycle_records_own's read/update/delete behavior for a row's owner is
--     unchanged -- a legitimate cycle record's owner is always the wife
--     (gender never changes retroactively), so her existing start/end flow
--     (insert then later update to set ended_on) still passes this check.
--   * cycle_records_spouse_shared_read (the partner's read access to
--     `visibility = 'shared'` rows) is untouched -- it's a separate SELECT
--     policy this migration does not touch.
drop policy if exists cycle_records_own on public.cycle_records;

create policy cycle_records_own on public.cycle_records
  for all
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and public.is_couple_member(couple_id)
    and exists (
      select 1 from public.users u
       where u.id = auth.uid()
         and u.gender = 'female'
    )
  );
