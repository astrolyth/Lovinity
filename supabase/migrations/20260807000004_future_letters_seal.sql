-- Seal future letters server-side until their unlock date.
--
-- A future letter is a surprise: you write to your spouse now and it opens on
-- an anniversary, a reunion, an Eid, years away. The bulk RLS loop in
-- 20260712000002 gave `future_letters` the same blanket policy as every other
-- couple table -- `for all using (is_couple_member(couple_id))` -- which means
-- the recipient can `select` the row, and the ciphertext, the moment it is
-- written. The unlock date was enforced only by the client choosing not to
-- decrypt.
--
-- That is not a seal. It holds against a spouse using the app as intended and
-- fails against anyone willing to call the REST endpoint directly. For a
-- feature whose entire value is anticipation, "you could have peeked" is the
-- same as "it was never sealed".
--
-- Layered defence, and both layers are needed:
--
--   * THIS MIGRATION stops the ciphertext being delivered at all before
--     `unlock_at`. The author still sees their own letters (they wrote them,
--     and they must be able to review or delete them).
--   * E2E ENCRYPTION (lib/core/crypto/letter_crypto.dart) means that even a
--     row obtained some other way -- a backup, a compromised service key --
--     is opaque without the couple's letter key, which never leaves the
--     devices.
--
-- Neither alone is sufficient: RLS alone trusts the server, encryption alone
-- lets the recipient hold the ciphertext and wait for a key they will
-- eventually be given.

drop policy if exists future_letters_couple_rls on public.future_letters;

-- Read: authors always see their own; everyone else in the couple only once
-- the letter has unlocked.
create policy future_letters_read on public.future_letters
  for select using (
    public.is_couple_member(couple_id)
    and (
      author_id = auth.uid()
      or unlock_at <= now()
    )
  );

-- Write: only as yourself, only into your own couple. `author_id` is pinned to
-- the caller so a letter cannot be attributed to the spouse.
create policy future_letters_insert on public.future_letters
  for insert with check (
    public.is_couple_member(couple_id)
    and author_id = auth.uid()
  );

-- Update: the author may revise a letter that has not yet opened. Once it is
-- open, it is part of the couple's history and is not rewritten.
--
-- The recipient needs exactly one write: stamping `unlocked_at` when they open
-- it. That is allowed only for letters that have actually unlocked, so it
-- cannot be used to pry one open early.
create policy future_letters_update on public.future_letters
  for update using (
    public.is_couple_member(couple_id)
    and (
      (author_id = auth.uid() and unlock_at > now())
      or unlock_at <= now()
    )
  ) with check (
    public.is_couple_member(couple_id)
  );

-- Delete: the author may withdraw a letter that has not yet opened.
create policy future_letters_delete on public.future_letters
  for delete using (
    public.is_couple_member(couple_id)
    and author_id = auth.uid()
    and unlock_at > now()
  );

-- `unlock_at` in the past at write time would make the "sealed" letter open
-- immediately, which is a confusing way to write an ordinary message and an
-- easy way to fool yourself into thinking a seal applied.
alter table public.future_letters
  drop constraint if exists future_letters_unlock_future;

-- NOT VALID: existing rows (if any) are left alone; only new and updated rows
-- are checked. A historical row with a past unlock date is not a reason for
-- this migration to fail.
alter table public.future_letters
  add constraint future_letters_unlock_future
  check (unlock_at > created_at) not valid;
