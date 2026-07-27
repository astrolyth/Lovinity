create table public.user_preferences (
  user_id     uuid primary key references public.users(id) on delete cascade,
  prefs       jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);

alter table public.user_preferences enable row level security;
create policy user_prefs_own on public.user_preferences
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update on public.user_preferences to authenticated;
