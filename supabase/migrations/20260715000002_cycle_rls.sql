-- Tighten cycle_records privacy: own rows always; spouse reads only shared rows.
drop policy if exists cycle_records_couple_rls on public.cycle_records;

create policy cycle_records_own on public.cycle_records
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and public.is_couple_member(couple_id));

create policy cycle_records_spouse_shared_read on public.cycle_records
  for select
  using (
    visibility = 'shared'
    and public.is_couple_member(couple_id)
    and user_id <> auth.uid()
  );
