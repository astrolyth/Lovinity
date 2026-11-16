-- Normalise the shared shopping list from a jsonb array to one row per item.
--
-- `grocery_lists.items` is a jsonb array (`[{name, qty, checked}]`). A "live
-- shopping list" means both spouses tick things off at the same time, in a
-- shop, on two phones. Updating one element of a jsonb array requires reading
-- the whole array, changing one entry and writing the whole array back — so
-- two concurrent ticks race, and the second write silently discards the first.
-- The item pops back unchecked and the couple buys it twice. That is a lost
-- update, and with a shared list it is the expected case, not a rare one.
--
-- Row-per-item removes the race by construction: two ticks touch two rows and
-- cannot overwrite each other. It also makes realtime useful (a single item
-- toggling emits one small change instead of the entire list) and lets RLS and
-- indexes work at item granularity.
--
-- `grocery_lists` is kept as the list header (title, ownership, timestamps).

create table if not exists public.grocery_items (
  id          uuid primary key default gen_random_uuid(),
  list_id     uuid not null references public.grocery_lists(id) on delete cascade,
  couple_id   uuid not null references public.couples(id) on delete cascade,
  name        text not null,
  qty         text,
  checked     boolean not null default false,
  -- Who ticked it, so the UI can say "Aisha got this" rather than just
  -- greying the row out.
  checked_by  uuid references public.users(id) on delete set null,
  checked_at  timestamptz,
  position    integer not null default 0,
  created_by  uuid not null references public.users(id) on delete cascade,
  created_at  timestamptz not null default now()
);

create index if not exists grocery_items_list_idx
  on public.grocery_items (list_id, position);
create index if not exists grocery_items_couple_idx
  on public.grocery_items (couple_id);

-- Matches the couple-scoped policy the bulk loop in 20260712000002 applies to
-- every other couple table, so behaviour is uniform across the schema.
alter table public.grocery_items enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'grocery_items'
      and policyname = 'grocery_items_couple_rls'
  ) then
    create policy grocery_items_couple_rls on public.grocery_items
      for all
      using (public.is_couple_member(couple_id))
      with check (public.is_couple_member(couple_id));
  end if;
end $$;

grant select, insert, update, delete on public.grocery_items to authenticated;

-- Migrate any existing jsonb items across. `grocery_lists.items` is left in
-- place rather than dropped: this runs against a live database, and dropping
-- the source column in the same migration that reads it leaves no way back if
-- the backfill turns out to be wrong. It is dead weight, not a hazard.
insert into public.grocery_items (list_id, couple_id, name, qty, checked, created_by, position)
select
  gl.id,
  gl.couple_id,
  coalesce(nullif(item->>'name', ''), 'Item'),
  item->>'qty',
  coalesce((item->>'checked')::boolean, false),
  c.member_a,
  (ord - 1)::integer
from public.grocery_lists gl
join public.couples c on c.id = gl.couple_id
cross join lateral jsonb_array_elements(
  case when jsonb_typeof(gl.items) = 'array' then gl.items else '[]'::jsonb end
) with ordinality as t(item, ord)
where not exists (
  select 1 from public.grocery_items gi where gi.list_id = gl.id
);

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      execute 'alter publication supabase_realtime add table public.grocery_items';
    exception
      when duplicate_object then null;
    end;
  end if;
end $$;

-- Deletes must reach the peer device: removing an item from a shared list has
-- to make it disappear on the other phone, and the default replica identity
-- sends only the primary key, which Realtime cannot match against a couple_id
-- filter.
alter table public.grocery_items replica identity full;
