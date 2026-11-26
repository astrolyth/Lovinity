-- Our Wall (shared feed): per-operation RLS, an update guard, data checks
-- and spouse push triggers for feed_items / feed_comments / feed_reactions.
-- Spec: docs/superpowers/specs/2026-10-08-our-wall-design.md

------------------------------------------------------------------
-- 1. Normalise any existing rows so the new checks apply cleanly.
------------------------------------------------------------------
update public.feed_items set url = null
  where url is not null and (url !~* '^https?://' or length(url) > 2048);
update public.feed_items set note = null where note is not null and length(btrim(note)) = 0;
delete from public.feed_items where url is null and note is null;
update public.feed_items set source = null
  where source is not null and source not in ('youtube', 'instagram', 'tiktok', 'article', 'note');
update public.feed_items set collection = null
  where collection is not null and collection not in ('recipes', 'places', 'home', 'funny', 'deen');
update public.feed_items set note = left(note, 1000) where length(note) > 1000;
update public.feed_items set title = left(title, 300) where length(title) > 300;
update public.feed_items set description = left(description, 1000) where length(description) > 1000;
delete from public.feed_comments where length(btrim(body)) = 0;
update public.feed_comments set body = left(body, 1000) where length(body) > 1000;
delete from public.feed_reactions
  where reaction not in ('heart', 'laugh', 'fire', 'dua', 'wow', 'star');

------------------------------------------------------------------
-- 2. Data checks.
------------------------------------------------------------------
alter table public.feed_items
  add constraint feed_items_url_check
    check (url is null or (url ~* '^https?://' and length(url) <= 2048)),
  add constraint feed_items_source_check
    check (source is null or source in ('youtube', 'instagram', 'tiktok', 'article', 'note')),
  add constraint feed_items_collection_check
    check (collection is null or collection in ('recipes', 'places', 'home', 'funny', 'deen')),
  add constraint feed_items_note_len check (note is null or length(note) <= 1000),
  add constraint feed_items_title_len check (title is null or length(title) <= 300),
  add constraint feed_items_description_len
    check (description is null or length(description) <= 1000),
  add constraint feed_items_has_content
    check (url is not null or (note is not null and length(btrim(note)) > 0));

alter table public.feed_comments
  add constraint feed_comments_body_len
    check (length(btrim(body)) between 1 and 1000);

alter table public.feed_reactions
  add constraint feed_reactions_reaction_check
    check (reaction in ('heart', 'laugh', 'fire', 'dua', 'wow', 'star'));

------------------------------------------------------------------
-- 3. Per-operation RLS (replaces the blanket `for all` couple policy).
------------------------------------------------------------------
drop policy if exists feed_items_couple_rls on public.feed_items;
drop policy if exists feed_comments_couple_rls on public.feed_comments;
drop policy if exists feed_reactions_couple_rls on public.feed_reactions;

create policy feed_items_select on public.feed_items
  for select using (public.is_couple_member(couple_id));
create policy feed_items_insert on public.feed_items
  for insert with check (public.is_couple_member(couple_id) and added_by = auth.uid());
-- Either spouse may pin or file an item; feed_items_guard limits WHAT changes.
create policy feed_items_update on public.feed_items
  for update using (public.is_couple_member(couple_id))
  with check (public.is_couple_member(couple_id));
create policy feed_items_delete on public.feed_items
  for delete using (public.is_couple_member(couple_id) and added_by = auth.uid());

create policy feed_comments_select on public.feed_comments
  for select using (public.is_couple_member(couple_id));
create policy feed_comments_insert on public.feed_comments
  for insert with check (
    public.is_couple_member(couple_id)
    and author_id = auth.uid()
    and exists (select 1 from public.feed_items i
                where i.id = item_id and i.couple_id = feed_comments.couple_id)
  );
create policy feed_comments_delete on public.feed_comments
  for delete using (public.is_couple_member(couple_id) and author_id = auth.uid());

create policy feed_reactions_select on public.feed_reactions
  for select using (public.is_couple_member(couple_id));
create policy feed_reactions_insert on public.feed_reactions
  for insert with check (
    public.is_couple_member(couple_id)
    and user_id = auth.uid()
    and exists (select 1 from public.feed_items i
                where i.id = item_id and i.couple_id = feed_reactions.couple_id)
  );
create policy feed_reactions_delete on public.feed_reactions
  for delete using (public.is_couple_member(couple_id) and user_id = auth.uid());

------------------------------------------------------------------
-- 4. Update guard: only is_pinned and collection may change after posting.
--    RLS cannot compare OLD vs NEW, so this lives in a trigger.
------------------------------------------------------------------
create or replace function public.feed_items_guard_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (new.id, new.couple_id, new.added_by, new.url, new.title, new.description,
      new.image_url, new.source, new.media_url, new.media_mime, new.note,
      new.created_at)
     is distinct from
     (old.id, old.couple_id, old.added_by, old.url, old.title, old.description,
      old.image_url, old.source, old.media_url, old.media_mime, old.note,
      old.created_at) then
    raise exception 'feed_items: only is_pinned and collection can change after posting'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists feed_items_guard on public.feed_items;
create trigger feed_items_guard
  before update on public.feed_items
  for each row execute function public.feed_items_guard_update();

------------------------------------------------------------------
-- 5. Spouse push on new items and comments (never on reactions).
--    dispatch_push is best-effort and never raises.
------------------------------------------------------------------
create or replace function public.notify_wall_item()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_spouse uuid;
  v_name   text;
begin
  select case when member_a = new.added_by then member_b else member_a end
    into v_spouse
    from public.couples where id = new.couple_id;
  if v_spouse is null then
    return new;
  end if;
  select nullif(btrim(display_name), '') into v_name
    from public.users where id = new.added_by;
  perform public.dispatch_push(
    v_spouse, 'wall',
    left(coalesce(v_name, 'Your partner'), 60) || ' shared something',
    'New on your Wall 💛'
  );
  return new;
end;
$$;

create or replace function public.notify_wall_comment()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_spouse uuid;
  v_name   text;
begin
  select case when member_a = new.author_id then member_b else member_a end
    into v_spouse
    from public.couples where id = new.couple_id;
  if v_spouse is null then
    return new;
  end if;
  select nullif(btrim(display_name), '') into v_name
    from public.users where id = new.author_id;
  perform public.dispatch_push(
    v_spouse, 'wall',
    left(coalesce(v_name, 'Your partner'), 60) || ' replied',
    'New comment on your Wall'
  );
  return new;
end;
$$;

drop trigger if exists on_feed_item_insert on public.feed_items;
create trigger on_feed_item_insert
  after insert on public.feed_items
  for each row execute function public.notify_wall_item();

drop trigger if exists on_feed_comment_insert on public.feed_comments;
create trigger on_feed_comment_insert
  after insert on public.feed_comments
  for each row execute function public.notify_wall_comment();

revoke execute on function public.feed_items_guard_update() from public, anon, authenticated;
revoke execute on function public.notify_wall_item() from public, anon, authenticated;
revoke execute on function public.notify_wall_comment() from public, anon, authenticated;
