drop function if exists public.send_message(integer, jsonb);

create or replace function public.send_message(
  p_sender_device_num integer,
  p_envelopes jsonb,
  p_message_id uuid default null
)
returns table (message_id uuid, created_at timestamptz)
language plpgsql volatile security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_cid  uuid;
  v_conv uuid;
  v_msg  public.messages%rowtype;
  e      jsonb;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select id into v_cid from public.couples
    where v_uid in (member_a, member_b) and status = 'active' limit 1;
  if v_cid is null then raise exception 'not_paired'; end if;

  select id into v_conv from public.conversations where couple_id = v_cid;
  if v_conv is null then
    insert into public.conversations (couple_id) values (v_cid) returning id into v_conv;
  end if;

  insert into public.messages (id, conversation_id, couple_id, sender_id, sender_device_num)
    values (coalesce(p_message_id, gen_random_uuid()), v_conv, v_cid, v_uid, p_sender_device_num)
    returning * into v_msg;

  for e in select * from jsonb_array_elements(p_envelopes) loop
    if (e->>'recipient_id')::uuid not in (
      select member_a from public.couples where id = v_cid
      union
      select member_b from public.couples where id = v_cid
    ) then
      raise exception 'invalid_recipient';
    end if;
    insert into public.message_envelopes
      (message_id, couple_id, sender_id, sender_device_num,
       recipient_id, recipient_device_num, cipher_type, ciphertext)
    values (
      v_msg.id, v_cid, v_uid, p_sender_device_num,
      (e->>'recipient_id')::uuid, (e->>'recipient_device_num')::int,
      (e->>'cipher_type')::smallint, decode(e->>'ciphertext', 'hex')
    );
  end loop;

  update public.conversations set last_message_at = v_msg.created_at where id = v_conv;
  message_id := v_msg.id; created_at := v_msg.created_at; return next;
end;
$$;
grant execute on function public.send_message(integer, jsonb, uuid) to authenticated;
