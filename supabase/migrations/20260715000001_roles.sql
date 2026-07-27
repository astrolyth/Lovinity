-- Roles: gender on users, same-gender pairing rejection.
alter table public.users
  add column if not exists gender text
    check (gender in ('male','female'));

-- Recreate accept_pairing_invite with a gender-difference guard.
create or replace function public.accept_pairing_invite(p_code text)
returns public.couples
language plpgsql volatile security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_invite  public.pairing_invites%rowtype;
  v_a       uuid;
  v_b       uuid;
  v_couple  public.couples%rowtype;
  v_my_gender      text;
  v_inviter_gender text;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select * into v_invite from public.pairing_invites
   where code = upper(trim(p_code)) for update;
  if not found then raise exception 'invite_not_found'; end if;
  if v_invite.consumed_at is not null then raise exception 'invite_already_used'; end if;
  if v_invite.expires_at < now() then raise exception 'invite_expired'; end if;
  if v_invite.inviter_id = v_uid then raise exception 'cannot_pair_with_self'; end if;

  if exists (select 1 from public.couples
             where v_uid in (member_a, member_b) and status = 'active') then
    raise exception 'already_paired';
  end if;
  if exists (select 1 from public.couples
             where v_invite.inviter_id in (member_a, member_b) and status = 'active') then
    raise exception 'inviter_already_paired';
  end if;

  select gender into v_my_gender      from public.users where id = v_uid;
  select gender into v_inviter_gender from public.users where id = v_invite.inviter_id;
  if v_my_gender is null or v_inviter_gender is null then
    raise exception 'gender_required';
  end if;
  if v_my_gender = v_inviter_gender then
    raise exception 'same_gender_pairing';
  end if;

  if v_invite.inviter_id < v_uid then
    v_a := v_invite.inviter_id; v_b := v_uid;
  else
    v_a := v_uid; v_b := v_invite.inviter_id;
  end if;

  update public.pairing_invites
     set consumed_at = now(), consumed_by = v_uid
   where code = v_invite.code;

  insert into public.couples (member_a, member_b)
       values (v_a, v_b) returning * into v_couple;
  return v_couple;
end;
$$;

grant execute on function public.accept_pairing_invite(text) to authenticated;
