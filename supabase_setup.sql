-- =====================================================
-- منصة الأمان الرقمي للأطفال — إعداد Supabase
-- شغّل هذا الملف كاملاً في: Supabase > SQL Editor
-- =====================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- الجداول ----------
create table if not exists public.players (
  id         uuid primary key default gen_random_uuid(),
  token      uuid not null unique default gen_random_uuid(), -- سرّ اللاعب (لا يُعرض للآخرين)
  name       text not null check (char_length(name) between 2 and 40),
  grade      text not null check (char_length(grade) <= 30),
  avatar     text not null default '🕵️',
  created_at timestamptz not null default now()
);

create table if not exists public.results (
  id         uuid primary key default gen_random_uuid(),
  player_id  uuid not null unique references public.players(id) on delete cascade,
  score      int  not null default 0 check (score >= 0),
  correct    int  not null default 0 check (correct >= 0),
  answered   int  not null default 0 check (answered >= 0),
  total      int  not null default 8,
  finished   boolean not null default false,
  duration_s int  not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.admin_settings (
  id        int primary key default 1 check (id = 1),
  pass_hash text not null
);

-- كلمة مرور المشرف الافتراضية: ChangeMe123  (غيّرها فوراً — انظر آخر الملف)
insert into public.admin_settings (id, pass_hash)
values (1, extensions.crypt('ChangeMe123', extensions.gen_salt('bf')))
on conflict (id) do nothing;

-- ---------- سياسات الحماية (RLS) ----------
-- نفعّل RLS ولا نضع أي سياسة للوصول المباشر: الجداول مغلقة بالكامل
-- والوصول يتم فقط عبر الدوال الآمنة أدناه.
alter table public.players        enable row level security;
alter table public.results        enable row level security;
alter table public.admin_settings enable row level security;

revoke all on public.players, public.results, public.admin_settings from anon, authenticated;

-- ---------- دالة التسجيل ----------
create or replace function public.register_player(p_name text, p_grade text, p_avatar text)
returns json
language plpgsql security definer
set search_path = public, extensions
as $$
declare v_player public.players;
begin
  if p_name is null or char_length(trim(p_name)) < 2 then
    raise exception 'الاسم قصير جداً';
  end if;
  insert into public.players (name, grade, avatar)
  values (left(trim(p_name), 40), left(coalesce(p_grade, ''), 30), left(coalesce(p_avatar, '🕵️'), 8))
  returning * into v_player;
  insert into public.results (player_id) values (v_player.id);
  return json_build_object('id', v_player.id, 'token', v_player.token, 'name', v_player.name);
end $$;

-- ---------- دالة حفظ التقدم ----------
create or replace function public.save_progress(
  p_token uuid, p_score int, p_correct int, p_answered int,
  p_total int, p_finished boolean, p_duration int)
returns json
language plpgsql security definer
set search_path = public, extensions
as $$
declare v_id uuid;
begin
  select id into v_id from public.players where token = p_token;
  if v_id is null then raise exception 'لاعب غير معروف'; end if;
  update public.results set
    score      = greatest(0, least(p_score, 1000)),
    correct    = greatest(0, p_correct),
    answered   = greatest(0, p_answered),
    total      = greatest(1, p_total),
    finished   = p_finished,
    duration_s = greatest(0, p_duration),
    updated_at = now()
  where player_id = v_id;
  return json_build_object('ok', true);
end $$;

-- ---------- لوحة الصدارة (أسماء ونقاط فقط) ----------
create or replace function public.get_leaderboard()
returns table (name text, avatar text, score int)
language sql security definer
set search_path = public, extensions
as $$
  select p.name, p.avatar, r.score
  from public.results r join public.players p on p.id = r.player_id
  where r.answered > 0
  order by r.score desc, r.duration_s asc
  limit 10;
$$;

-- ---------- نتائج المشرف (محمية بكلمة مرور) ----------
create or replace function public.admin_get_results(p_pass text)
returns table (name text, grade text, avatar text, score int, correct int,
               answered int, total int, finished boolean, duration_s int,
               created_at timestamptz, updated_at timestamptz)
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  if not exists (select 1 from public.admin_settings
                 where pass_hash = extensions.crypt(p_pass, pass_hash)) then
    raise exception 'كلمة مرور المشرف غير صحيحة';
  end if;
  return query
    select p.name, p.grade, p.avatar, r.score, r.correct, r.answered, r.total,
           r.finished, r.duration_s, p.created_at, r.updated_at
    from public.players p join public.results r on r.player_id = p.id
    order by r.updated_at desc;
end $$;

-- ---------- الصلاحيات ----------
revoke execute on all functions in schema public from public;
grant execute on function public.register_player(text, text, text) to anon, authenticated;
grant execute on function public.save_progress(uuid, int, int, int, int, boolean, int) to anon, authenticated;
grant execute on function public.get_leaderboard() to anon, authenticated;
grant execute on function public.admin_get_results(text) to anon, authenticated;

-- ---------- تغيير كلمة مرور المشرف (شغّله مرة واحدة بكلمتك) ----------
-- update public.admin_settings
--   set pass_hash = extensions.crypt('كلمة_المرور_الجديدة', extensions.gen_salt('bf'))
--   where id = 1;
