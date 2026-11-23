-- =====================================================
-- ترقية اختيارية: إحصاءات الأسئلة للمشرف
-- إضافة فقط — لا يغيّر أي جدول أو دالة موجودة (التسجيل وحفظ التقدم يبقيان كما هما)
-- شغّله مرة واحدة في SQL Editor. آمن لإعادة التشغيل.
-- =====================================================

create table if not exists public.question_stats (
  qid         text not null check (char_length(qid) <= 20),
  grade       text not null,
  right_count int  not null default 0,
  wrong_count int  not null default 0,
  primary key (qid, grade)
);
alter table public.question_stats enable row level security;
revoke all on public.question_stats from anon, authenticated;

create or replace function public.record_answer(p_token uuid, p_qid text, p_correct boolean)
returns json
language plpgsql security definer
set search_path = public, extensions
as $$
declare v_grade text;
begin
  select grade into v_grade from public.players where token = p_token;
  if v_grade is null then raise exception 'لاعب غير معروف'; end if;
  if p_qid is null or char_length(p_qid) > 20 then raise exception 'سؤال غير صالح'; end if;
  insert into public.question_stats (qid, grade, right_count, wrong_count)
  values (p_qid, v_grade, case when p_correct then 1 else 0 end, case when p_correct then 0 else 1 end)
  on conflict (qid, grade) do update set
    right_count = public.question_stats.right_count + (case when p_correct then 1 else 0 end),
    wrong_count = public.question_stats.wrong_count + (case when p_correct then 0 else 1 end);
  return json_build_object('ok', true);
end $$;

create or replace function public.admin_question_stats(p_pass text)
returns table (qid text, grade text, right_count int, wrong_count int)
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  if not exists (select 1 from public.admin_settings
                 where pass_hash = extensions.crypt(p_pass, pass_hash)) then
    raise exception 'كلمة مرور المشرف غير صحيحة';
  end if;
  return query select s.qid, s.grade, s.right_count, s.wrong_count from public.question_stats s;
end $$;

revoke execute on function public.record_answer(uuid, text, boolean) from public;
revoke execute on function public.admin_question_stats(text) from public;
grant execute on function public.record_answer(uuid, text, boolean) to anon, authenticated;
grant execute on function public.admin_question_stats(text) to anon, authenticated;
