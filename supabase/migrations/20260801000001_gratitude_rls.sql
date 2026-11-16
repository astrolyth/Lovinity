-- Tighten gratitude_notes privacy: own rows always; spouse reads only
-- revealed rows. The generic couple RLS policy let a partner read/update/
-- delete an unrevealed note directly with their own JWT -- the client-side
-- filter in GratitudeRepository.watchAll was never a substitute for this.
drop policy if exists gratitude_notes_couple_rls on public.gratitude_notes;

create policy gratitude_notes_own on public.gratitude_notes
  for all
  using (author_id = auth.uid())
  with check (author_id = auth.uid() and public.is_couple_member(couple_id));

create policy gratitude_notes_spouse_revealed_read on public.gratitude_notes
  for select
  using (
    reveal_to_spouse
    and public.is_couple_member(couple_id)
    and author_id <> auth.uid()
  );
