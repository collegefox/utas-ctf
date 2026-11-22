-- CYBERKIDS: migration after running supabase_setup.sql
-- Run once in Supabase > SQL Editor.

-- Allow the public app to read only shared competition settings and public questions.
drop policy if exists "public_read_main_settings" on public.settings;
create policy "public_read_main_settings"
on public.settings for select to anon, authenticated
using (key = 'main');

drop policy if exists "public_read_questions" on public.questions;
create policy "public_read_questions"
on public.questions for select to anon, authenticated
using (true);

grant select on public.settings to anon, authenticated;
grant select on public.questions to anon, authenticated;

-- Atomic registration: the unique name_key constraint prevents duplicate names
-- even if two devices attempt registration at the same time.
create or replace function public.register_participant(
  p_name text,
  p_team text default null,
  p_icon text default null,
  p_age_group text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_name text;
  v_key text;
begin
  v_name := trim(coalesce(p_name, ''));
  v_key := lower(regexp_replace(v_name, '\s+', ' ', 'g'));

  if length(v_name) < 1 or length(v_name) > 80 then
    raise exception 'Invalid participant name';
  end if;

  insert into public.participants(name, name_key, team, icon, age_group)
  values (v_name, v_key, nullif(trim(coalesce(p_team, '')), ''), p_icon, p_age_group)
  on conflict (name_key) do nothing
  returning id into v_id;

  if v_id is null then
    raise unique_violation using message = 'Participant already registered';
  end if;

  return v_id;
end;
$$;

revoke all on function public.register_participant(text, text, text, text) from public;
grant execute on function public.register_participant(text, text, text, text) to anon, authenticated;

-- Public submissions must be tied to a successfully registered participant.
drop policy if exists "public_submit_results" on public.results;
create policy "public_submit_results"
on public.results for insert to anon
with check (
  participant_id is not null
  and points >= 0
  and correct_answers >= 0
  and total_questions >= correct_answers
);

-- Authenticated administrators may add manually pasted results.
drop policy if exists "authenticated_insert_results" on public.results;
create policy "authenticated_insert_results"
on public.results for insert to authenticated
with check (true);

-- Restrict administrative database access to users explicitly marked as admin
-- in Supabase Auth app_metadata (not every signed-in user).
drop policy if exists "authenticated_read_results" on public.results;
create policy "authenticated_read_results"
on public.results for select to authenticated
using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "authenticated_insert_results" on public.results;
create policy "authenticated_insert_results"
on public.results for insert to authenticated
with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "authenticated_manage_participants" on public.participants;
create policy "authenticated_manage_participants"
on public.participants for all to authenticated
using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "authenticated_manage_settings" on public.settings;
create policy "authenticated_manage_settings"
on public.settings for all to authenticated
using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "authenticated_manage_questions" on public.questions;
create policy "authenticated_manage_questions"
on public.questions for all to authenticated
using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- After creating the administrator in Authentication > Users, run this
-- separately after replacing the email address:
-- update auth.users
-- set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"admin"}'::jsonb
-- where email = 'admin@example.com';
