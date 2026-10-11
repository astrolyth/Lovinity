-- Let the service role operate the content approval gates.
--
-- `20260808000001` and `20260808000002` added `approved` flags to the lesson
-- and love-map libraries, and `20260808000003` to date ideas, each with a
-- policy that serves approved rows only. That closes the gate correctly for
-- end users -- but the bulk grant loop in 20260712000002 only ever granted
-- these tables to `authenticated`, so NO role could read an unapproved row or
-- flip the flag. The gate had no handle on the inside: content could be
-- inserted and then never reviewed, except by connecting as the Postgres
-- superuser.
--
-- `service_role` is the role that back-office tooling, the generation edge
-- function and review scripts authenticate as. It already bypasses RLS; what
-- it lacked was the table-level privilege. Granting it here is what makes the
-- approval workflow operable, and it is also what lets the integration tests
-- assert that an unapproved row is genuinely withheld from a normal client.
--
-- Deliberately scoped to the content libraries. The couple-scoped tables are
-- NOT included: a couple's letters, answers and plans are theirs, and there is
-- no review workflow that needs to read them.

grant select, insert, update, delete on public.learning_lessons  to service_role;
grant select, insert, update, delete on public.love_map_quizzes  to service_role;
grant select, insert, update, delete on public.date_ideas        to service_role;

-- The pre-existing content libraries have the same gap. Included so "review
-- content" means one role everywhere rather than a per-table surprise.
grant select, insert, update, delete on public.daily_questions   to service_role;
grant select, insert, update, delete on public.verses            to service_role;
grant select, insert, update, delete on public.hadiths           to service_role;
grant select, insert, update, delete on public.duas_library      to service_role;
