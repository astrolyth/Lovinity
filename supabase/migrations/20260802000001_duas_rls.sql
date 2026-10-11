-- Tighten duas privacy: own rows always; spouse reads only shared rows.
-- The generic couple RLS policy let a partner read/update/delete a
-- private dua directly with their own JWT -- the client-side filter in
-- duasProvider was never a substitute for this.
drop policy if exists duas_couple_rls on public.duas;

create policy duas_own on public.duas
  for all
  using (author_id = auth.uid())
  with check (author_id = auth.uid() and public.is_couple_member(couple_id));

create policy duas_spouse_shared_read on public.duas
  for select
  using (
    visibility = 'shared'
    and public.is_couple_member(couple_id)
    and author_id <> auth.uid()
  );

-- duas_own above restricts writes to the author, which is correct for
-- privacy but would silently break "mark partner's shared dua as
-- answered" -- an existing, legitimate feature the client relies on
-- (DuaRepository.setAnswered/setUnanswered are called from the dua list
-- for any visible dua, not just the caller's own). Re-open exactly that
-- one path, with minimum necessary privilege: only the answered-related
-- columns move, only for couple members, and only when the target dua
-- is the caller's own OR shared -- a partner still cannot touch a
-- private dua through this RPC.
create or replace function public.set_dua_answered(
  p_dua_id uuid,
  p_answered boolean,
  p_note text default null
)
returns void
language plpgsql volatile security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  update public.duas d
     set is_answered   = p_answered,
         answered_at   = case when p_answered then now() else null end,
         answered_note = case when p_answered then p_note else null end
   where d.id = p_dua_id
     and public.is_couple_member(d.couple_id)
     and (d.author_id = v_uid or d.visibility = 'shared');

  if not found then
    raise exception 'dua_not_found_or_not_permitted';
  end if;
end;
$$;

grant execute on function public.set_dua_answered(uuid, boolean, text) to authenticated;
