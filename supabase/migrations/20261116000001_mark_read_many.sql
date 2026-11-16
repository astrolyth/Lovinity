-- Read receipts in one call. Opening the chat used to send one mark_read RPC
-- per unread message, all at once (300 unread after a week away = 300
-- requests). mark_read_many takes every id in one request; same guards as
-- mark_read (20260718000001): only a couple member who is not the sender may
-- set receipts, and an already-read message is left alone.
create or replace function public.mark_read_many(p_message_ids uuid[])
returns void
language plpgsql volatile security definer
set search_path = public
as $$
begin
  update public.messages
     set read_at = now(), delivered_at = coalesce(delivered_at, now())
   where id = any(p_message_ids)
     and read_at is null
     and public.is_couple_member(couple_id)
     and sender_id <> auth.uid();
end;
$$;

revoke execute on function public.mark_read_many(uuid[]) from public, anon;
grant execute on function public.mark_read_many(uuid[]) to authenticated;

-- The app no longer calls the one-message version.
drop function if exists public.mark_read(uuid);
