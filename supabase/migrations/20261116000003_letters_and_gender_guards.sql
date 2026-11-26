-- 1. Future letters: after unlock, future_letters_update let either spouse
--    rewrite ANY column (body_ciphertext, author_id, unlock_at). The app only
--    ever stamps unlocked_at (LetterRepository.markOpened), so that is the one
--    column members may update. RLS still decides WHICH rows.
revoke update on public.future_letters from authenticated;
grant update (unlocked_at) on public.future_letters to authenticated;

-- 2. Gender: pairing (no same-gender couples) and cycle tracking (wife only)
--    trust users.gender, but users_update_self let a paired user change it.
--    Lock it while the user belongs to a couple; setting it the first time,
--    or changing it before pairing, still works.
create or replace function public.users_guard_gender()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.gender is not null
     and new.gender is distinct from old.gender
     and exists (
       select 1 from public.couples c
        where new.id in (c.member_a, c.member_b)
     ) then
    raise exception 'gender_locked' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists users_guard_gender on public.users;
create trigger users_guard_gender
  before update of gender on public.users
  for each row execute function public.users_guard_gender();

revoke execute on function public.users_guard_gender() from public, anon, authenticated;
