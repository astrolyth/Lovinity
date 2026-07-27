-- Realtime: register tables the app subscribes to via `.stream()` that were
-- omitted from the original supabase_realtime registration (Section 9 of
-- 20260712000002_full_schema.sql).
--
-- `couples` is the important one: PairingRepository.watchCurrentCouple streams
-- it, and currentCoupleProvider feeds the prayer log, scoreboard and daily
-- content. Without publication membership the stream never settles, so the
-- couple flickers to null and those cards churn / render empty.
--
-- Unlike the original block, this only swallows `duplicate_object` (already
-- registered) so a genuine failure surfaces instead of passing silently.

do $$
declare
  t text;
begin
  if not exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    raise notice 'supabase_realtime publication not found; skipping realtime registration';
    return;
  end if;

  foreach t in array array['couples', 'cycle_records', 'duas'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception
      when duplicate_object then null; -- already published
    end;
  end loop;
end $$;
