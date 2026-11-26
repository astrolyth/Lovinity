-- Dua library review columns, daily adhkar completions, tasbih-together totals.

-- 1. Library: review workflow + adhkar metadata. Existing rows are the seed.
alter table public.duas_library
  add column status       text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  add column source       text default 'seed',
  add column source_id    text,
  add column repeat_count int  not null default 1,
  add column benefit      text,
  add column tags         text[] not null default '{}',
  add column sort_order   int  not null default 0;

update public.duas_library set status = 'approved', source = 'seed', source_id = id::text;

create unique index duas_library_source_uidx on public.duas_library (source, source_id);

drop policy duas_library_read on public.duas_library;
create policy duas_library_read on public.duas_library
  for select using (status = 'approved');

-- 2. Adhkar completions: one row per user, day and set. Insert/delete only.
create table public.adhkar_completions (
  id           uuid primary key default gen_random_uuid(),
  couple_id    uuid not null references public.couples(id) on delete cascade,
  user_id      uuid not null references public.users(id) on delete cascade,
  local_date   date not null,
  set          text not null check (set in ('morning', 'evening', 'after_prayer')),
  completed_at timestamptz not null default now(),
  unique (user_id, local_date, set)
);

alter table public.adhkar_completions enable row level security;

create policy adhkar_completions_select on public.adhkar_completions
  for select using (public.is_couple_member(couple_id));
create policy adhkar_completions_insert on public.adhkar_completions
  for insert with check (user_id = auth.uid() and public.is_couple_member(couple_id));
create policy adhkar_completions_delete on public.adhkar_completions
  for delete using (user_id = auth.uid());

grant select, insert, delete on public.adhkar_completions to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      execute 'alter publication supabase_realtime add table public.adhkar_completions';
    exception
      when duplicate_object then null;
    end;
  end if;
end $$;

-- 3. Per-user totals for a counter's current period. Security invoker, so the
-- dhikr_contributions RLS keeps it couple-scoped.
create function public.dhikr_counter_totals(p_counter_id uuid)
returns table (user_id uuid, total bigint)
language sql stable security invoker set search_path = public
as $$
  select d.user_id, sum(d.count)::bigint
  from public.dhikr_counters c
  join public.dhikr_contributions d on d.counter_id = c.id
  where c.id = p_counter_id
    and d.logged_at >= case c.period
      when 'once' then c.starts_at
      else c.starts_at + floor(extract(epoch from now() - c.starts_at) / extract(epoch from
             case c.period when 'daily' then interval '1 day'
                           when 'weekly' then interval '7 days'
                           else interval '30 days' end))
           * case c.period when 'daily' then interval '1 day'
                           when 'weekly' then interval '7 days'
                           else interval '30 days' end
    end
  group by d.user_id;
$$;

revoke execute on function public.dhikr_counter_totals(uuid) from public, anon;
grant execute on function public.dhikr_counter_totals(uuid) to authenticated;
