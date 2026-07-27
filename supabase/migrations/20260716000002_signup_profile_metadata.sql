-- Copy the profile captured at sign-up (name, gender, madhhab) from auth
-- metadata into public.users.
--
-- With "Confirm email" enabled, signUp returns no session, so the client
-- cannot write public.users itself (RLS needs auth.uid()). The form passes the
-- profile as signUp metadata instead and this trigger persists it server-side
-- at auth.users insert.
--
-- Values are validated here so a bad/hostile client value can't trip the
-- CHECK constraints and fail the signup outright:
--   gender  -> 'male' | 'female', else null (user then lands on onboarding)
--   madhhab -> 'shafi' | 'hanafi', else 'shafi'
--
-- OTP sign-ups send no metadata, so they still arrive with gender null and are
-- routed to the onboarding screen, as before.

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gender  text := new.raw_user_meta_data->>'gender';
  v_madhhab text := new.raw_user_meta_data->>'madhhab';
begin
  insert into public.users (id, display_name, gender, madhhab)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', ''),
    case when v_gender in ('male', 'female') then v_gender else null end,
    case when v_madhhab in ('shafi', 'hanafi') then v_madhhab else 'shafi' end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
