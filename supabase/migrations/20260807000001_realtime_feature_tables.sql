-- Realtime registration for the couple-feature tables.
--
-- `20260712000002_full_schema.sql` creates tables for the shared calendar,
-- meal planning, groceries, recipes, future letters, co-studied lessons and
-- the love-map game, but registers NONE of them for realtime. Every one of
-- those features is built on `.stream()`, and an unpublished table produces
-- the worst possible failure mode: the initial fetch succeeds, so the screen
-- renders correctly and then silently never updates again. A spouse ticks a
-- grocery item and the other spouse's list simply never changes. That reads
-- as "the app is laggy", not as a missing publication, so it is registered up
-- front rather than rediscovered per feature.
--
-- Follows `20260716000001_realtime_missing_tables.sql`: swallow only
-- `duplicate_object` so a genuine failure still surfaces.

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

  foreach t in array array[
    'calendar_events',
    'meal_plans',
    'recipes',
    'grocery_lists',
    'future_letters',
    'learning_progress',
    'love_map_answers'
  ] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception
      when duplicate_object then null; -- already published
    end;
  end loop;
end $$;

-- Deletes must reach the client for anything the user can remove from a
-- shared, live view -- a calendar event cancelled on one device has to vanish
-- on the other. Postgres's default replica identity sends only the primary key
-- on DELETE, which Supabase Realtime cannot match against a `couple_id`
-- filter, so the delete is dropped and the row lingers on the peer until a
-- manual refetch. `full` includes the old row so the filter can match.
alter table public.calendar_events  replica identity full;
alter table public.recipes          replica identity full;
alter table public.grocery_lists    replica identity full;
