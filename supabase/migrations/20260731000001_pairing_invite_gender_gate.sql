-- create_pairing_invite had no gender check, unlike accept_pairing_invite --
-- a not-yet-onboarded account (gender still null, e.g. created via
-- passwordless OTP sign-in) could generate/share an invite code that could
-- never actually be accepted, since accept_pairing_invite rejects it with
-- 'gender_required'. Gate invite creation the same way acceptance already is.

create or replace function public.create_pairing_invite()
returns table(code text, expires_at timestamptz)
language plpgsql volatile security definer
set search_path = public
as $$
declare
  v_code   text;
  v_uid    uuid := auth.uid();
  v_exists boolean;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  if not exists (
    select 1 from public.users where id = v_uid and gender is not null
  ) then
    raise exception 'gender_required';
  end if;

  -- caller must not already be in a couple
  if exists (
    select 1 from public.couples
     where v_uid in (member_a, member_b)
       and status = 'active'
  ) then
    raise exception 'already_paired';
  end if;

  -- invalidate any of caller's still-active invites
  update public.pairing_invites p
     set expires_at = now()
   where p.inviter_id = v_uid
     and p.consumed_at is null
     and p.expires_at > now();

  -- retry until we find a unique code (astronomically unlikely to loop more than once)
  loop
    v_code := public.generate_invite_code();
    select true into v_exists
      from public.pairing_invites p where p.code = v_code;
    exit when v_exists is null;
    v_exists := null;
  end loop;

  insert into public.pairing_invites (code, inviter_id, expires_at)
       values (v_code, v_uid, now() + interval '10 minutes');

  code := v_code;
  expires_at := now() + interval '10 minutes';
  return next;
end;
$$;

grant execute on function public.create_pairing_invite() to authenticated;
