-- Local-dev seed users.
-- Runs automatically after `supabase db reset`.
-- DO NOT deploy this seed to a production project — the password hashes are known.
--
-- Test accounts:
--   ridwan@lovinity.test   / password123
--   aisha@lovinity.test    / password123
--   khadijah@lovinity.test / password123
--   naziha@lovinity.test   / password123

do $$
declare
  v_ridwan_id   uuid := '00000000-0000-0000-0000-000000000001';
  v_aisha_id    uuid := '00000000-0000-0000-0000-000000000002';
  v_khadijah_id uuid := '00000000-0000-0000-0000-000000000003';
  v_naziha_id   uuid := '00000000-0000-0000-0000-000000000004';
begin
  -- auth.users: bcrypt-hash the password with pgcrypto.
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
  ) values
    ('00000000-0000-0000-0000-000000000000', v_ridwan_id,
     'authenticated', 'authenticated',
     'ridwan@lovinity.test',
     crypt('password123', gen_salt('bf')),
     now(),
     '{"provider":"email","providers":["email"]}'::jsonb,
     '{"display_name":"Ridwan"}'::jsonb,
     now(), now(),
     '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', v_aisha_id,
     'authenticated', 'authenticated',
     'aisha@lovinity.test',
     crypt('password123', gen_salt('bf')),
     now(),
     '{"provider":"email","providers":["email"]}'::jsonb,
     '{"display_name":"Aisha"}'::jsonb,
     now(), now(),
     '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', v_khadijah_id,
     'authenticated', 'authenticated',
     'khadijah@lovinity.test',
     crypt('password123', gen_salt('bf')),
     now(),
     '{"provider":"email","providers":["email"]}'::jsonb,
     '{"display_name":"Khadijah"}'::jsonb,
     now(), now(),
     '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', v_naziha_id,
     'authenticated', 'authenticated',
     'naziha@lovinity.test',
     crypt('password123', gen_salt('bf')),
     now(),
     '{"provider":"email","providers":["email"]}'::jsonb,
     '{"display_name":"Naziha"}'::jsonb,
     now(), now(),
     '', '', '', '')
  on conflict (id) do nothing;

  -- auth.identities: password login uses the "email" provider identity.
  insert into auth.identities (
    provider_id, user_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  )
  select
    u.id::text,
    u.id,
    jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
    'email',
    now(), now(), now()
  from auth.users u
  where u.id in (v_ridwan_id, v_aisha_id, v_khadijah_id, v_naziha_id)
  on conflict (provider, provider_id) do nothing;

  -- public.users is populated by the on_auth_user_created trigger,
  -- but the trigger only fires on new inserts and won't have picked up
  -- display_name if the row already exists — sync a friendly name now.
  update public.users
     set display_name = 'Ridwan',   timezone = 'Europe/London'
   where id = v_ridwan_id;
  update public.users
     set display_name = 'Aisha',    timezone = 'Asia/Karachi'
   where id = v_aisha_id;
  update public.users
     set display_name = 'Khadijah', timezone = 'America/New_York'
   where id = v_khadijah_id;
  update public.users
     set display_name = 'Naziha', timezone = 'America/New_York'
   where id = v_naziha_id;
end $$;
