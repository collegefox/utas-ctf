-- CYBERKIDS - Supabase database setup
-- Run this script once in Supabase > SQL Editor > New Query.

create extension if not exists pgcrypto;

-- 1) Participants: one registration per normalized participant name.
create table if not exists public.participants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  name_key text not null unique,
  team text,
  icon text,
  age_group text,
  created_at timestamptz not null default now()
);

-- 2) Results: every completed activity is stored against a participant.
create table if not exists public.results (
  id uuid primary key default gen_random_uuid(),
  participant_id uuid references public.participants(id) on delete restrict,
  name text not null,
  icon text,
  team text,
  age_group text,
  level smallint not null default 0 check (level between 0 and 2),
  category smallint,
  points integer not null default 0 check (points >= 0),
  correct_answers integer not null default 0 check (correct_answers >= 0),
  total_questions integer not null default 0 check (total_questions >= 0),
  duration_seconds integer not null default 0 check (duration_seconds >= 0),
  completed_at timestamptz not null default now(),
  wrong_questions jsonb not null default '[]'::jsonb,
  badges jsonb not null default '[]'::jsonb,
  activity_mode text not null default 'تحدّي',
  created_at timestamptz not null default now()
);

create index if not exists results_participant_id_idx on public.results(participant_id);
create index if not exists results_points_idx on public.results(points desc);
create index if not exists results_completed_at_idx on public.results(completed_at desc);

-- 3) Settings: shared competition configuration.
create table if not exists public.settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

insert into public.settings(key, value)
values
  ('main', '{"duration_seconds":600,"round_questions":8}'::jsonb)
on conflict (key) do nothing;

-- 4) Questions added by the administrator.
create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  category smallint not null check (category between 0 and 5),
  level smallint not null check (level between 0 and 2),
  question_text text not null,
  options jsonb not null,
  correct_option smallint not null check (correct_option between 0 and 3),
  explanation text,
  created_at timestamptz not null default now()
);

-- Enable Row Level Security.
alter table public.participants enable row level security;
alter table public.results enable row level security;
alter table public.settings enable row level security;
alter table public.questions enable row level security;

-- Public participants can register, but cannot browse participant records.
drop policy if exists "public_register_participants" on public.participants;
create policy "public_register_participants"
on public.participants for insert to anon
with check (
  length(trim(name)) between 1 and 80
  and name_key = lower(regexp_replace(trim(name), '\s+', ' ', 'g'))
);

-- Public participants can submit completed results.
drop policy if exists "public_submit_results" on public.results;
create policy "public_submit_results"
on public.results for insert to anon
with check (
  points >= 0
  and correct_answers >= 0
  and total_questions >= correct_answers
);

-- Public leaderboard access is intentionally limited to a view.
-- Full result records should be read only by authenticated administrators.
drop policy if exists "authenticated_read_results" on public.results;
create policy "authenticated_read_results"
on public.results for select to authenticated
using (true);

drop policy if exists "authenticated_manage_participants" on public.participants;
create policy "authenticated_manage_participants"
on public.participants for all to authenticated
using (true) with check (true);

drop policy if exists "authenticated_manage_settings" on public.settings;
create policy "authenticated_manage_settings"
on public.settings for all to authenticated
using (true) with check (true);

drop policy if exists "authenticated_manage_questions" on public.questions;
create policy "authenticated_manage_questions"
on public.questions for all to authenticated
using (true) with check (true);

-- Minimal public leaderboard view. Avoid exposing age group or detailed answers.
create or replace view public.public_leaderboard
with (security_barrier = true) as
select
  name,
  icon,
  team,
  points,
  level,
  activity_mode,
  completed_at
from public.results
order by points desc, completed_at asc;

-- The view is created by the database owner and exposes only the selected
-- leaderboard columns. Do not grant anon SELECT on the base results table.

grant usage on schema public to anon, authenticated;
grant insert on public.participants to anon;
grant insert on public.results to anon;
grant select on public.public_leaderboard to anon, authenticated;
grant select, insert, update, delete on public.participants to authenticated;
grant select, insert, update, delete on public.results to authenticated;
grant select, insert, update, delete on public.settings to authenticated;
grant select, insert, update, delete on public.questions to authenticated;

-- Note:
-- Configure an administrator account in Supabase Authentication.
-- Never place the Supabase service_role key in index.html.
-- Use only the project's publishable/anon key in browser code.
