-- Plan screen (design: Plan.dc.html).
--   calendar_events.assignee_id  "Who" on a plan: null = together, else one spouse.
--   grocery_items.buyer_id       "Who is buying it"; null = whoever added it.
-- Both must name a member of the row's own couple (trigger below), so a row
-- can't point at someone outside the couple.

alter table public.calendar_events
  add column if not exists assignee_id uuid references public.users(id) on delete set null;
alter table public.grocery_items
  add column if not exists buyer_id uuid references public.users(id) on delete set null;

create or replace function public.ensure_member_column()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid uuid := (to_jsonb(new) ->> tg_argv[0])::uuid;
begin
  if v_uid is not null and not exists (
    select 1 from public.couples c
     where c.id = new.couple_id and v_uid in (c.member_a, c.member_b)
  ) then
    raise exception '% must be a member of the couple', tg_argv[0];
  end if;
  return new;
end;
$$;
revoke execute on function public.ensure_member_column() from public, anon, authenticated;

drop trigger if exists calendar_events_assignee_member on public.calendar_events;
create trigger calendar_events_assignee_member
  before insert or update of assignee_id on public.calendar_events
  for each row execute function public.ensure_member_column('assignee_id');

drop trigger if exists grocery_items_buyer_member on public.grocery_items;
create trigger grocery_items_buyer_member
  before insert or update of buyer_id on public.grocery_items
  for each row execute function public.ensure_member_column('buyer_id');
