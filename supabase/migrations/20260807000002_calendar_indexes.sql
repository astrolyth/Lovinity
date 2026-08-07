-- Shared calendar: index for Hijri-anchored event lookup.
--
-- NOTE: `(couple_id, starts_at)` is ALREADY indexed by
-- `calendar_couple_starts_idx` (20260712000002_full_schema.sql:211). Do not
-- add another -- a second identical btree is written on every insert and
-- update while serving no read that the first one doesn't already serve.
--
-- What is genuinely missing is a way to find the events that follow the
-- Islamic calendar. Those cannot be resolved by `starts_at` at all: a
-- Hijri-anchored event's stored Gregorian date is only where the series began,
-- and its next occurrence drifts ~11 days earlier each Gregorian year. The
-- reminder scheduler therefore has to pull them out and resolve each one
-- client-side, and a partial index keeps that pull cheap and small.

create index if not exists calendar_events_hijri_idx
  on public.calendar_events (couple_id)
  where hijri_anchor is not null;
