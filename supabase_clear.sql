-- =====================================================
-- أداة مسح النتائج للمشرف — إضافة فقط، آمنة لإعادة التشغيل
-- تمسح اللاعبين ونتائجهم (وإحصاءات الأسئلة إن وُجدت)، كلها أو لصف محدد
-- =====================================================
create or replace function public.admin_clear_results(p_pass text, p_grade text default null)
returns json
language plpgsql security definer
set search_path = public, extensions
as $$
declare n int;
begin
  if not exists (select 1 from public.admin_settings
                 where pass_hash = extensions.crypt(p_pass, pass_hash)) then
    raise exception 'كلمة مرور المشرف غير صحيحة';
  end if;
  delete from public.players where coalesce(p_grade, '') = '' or grade = p_grade;  -- النتائج تُحذف تلقائياً (cascade)
  get diagnostics n = row_count;
  if to_regclass('public.question_stats') is not null then
    delete from public.question_stats where coalesce(p_grade, '') = '' or grade = p_grade;
  end if;
  return json_build_object('deleted', n);
end $$;

revoke execute on function public.admin_clear_results(text, text) from public;
grant execute on function public.admin_clear_results(text, text) to anon, authenticated;
