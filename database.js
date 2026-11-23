/* database.js — الاتصال بـ Supabase والعمليات السحابية
   1) نفّذ supabase_setup.sql في SQL Editor
   2) ضع رابط المشروع والمفتاح العام (anon) أدناه
   إن لم تضعهما تعمل المنصة بوضع تجريبي محلي (localStorage). */

const SUPABASE_URL = 'https://rzxfmhmhwfknexhinqkc.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_vuicgg-qL4hgT30ydnAUmg_vkkiejxq';

const DB = (() => {
  let sb = null;
  const LS = 'ksp_local_v1';
  const DEMO_ADMIN = 'demo';

  const read = () => { try { return JSON.parse(localStorage.getItem(LS)) || { players: [] }; } catch (e) { return { players: [] }; } };
  const write = (d) => { try { localStorage.setItem(LS, JSON.stringify(d)); } catch (e) {} };
  const uid = () => (crypto.randomUUID ? crypto.randomUUID() : String(Date.now() + Math.random()));

  function init() {
    const ok = !SUPABASE_URL.startsWith('YOUR_') && window.supabase;
    if (ok) sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    return !!sb;
  }
  const isCloud = () => !!sb;

  async function rpc(fn, args) {
    const { data, error } = await sb.rpc(fn, args || {});
    if (error) throw new Error(error.message);
    return data;
  }

  async function registerPlayer(name, grade, avatar) {
    if (sb) return rpc('register_player', { p_name: name, p_grade: grade, p_avatar: avatar });
    const d = read();
    const p = { id: uid(), token: uid(), name, grade, avatar, score: 0, correct: 0, answered: 0, total: 8,
                finished: false, duration_s: 0, created_at: new Date().toISOString(), updated_at: new Date().toISOString() };
    d.players.push(p); write(d);
    return { id: p.id, token: p.token, name };
  }

  async function saveProgress(token, s) {
    if (sb) return rpc('save_progress', {
      p_token: token, p_score: s.score, p_correct: s.correct, p_answered: s.answered,
      p_total: s.total, p_finished: s.finished, p_duration: s.duration });
    const d = read(); const p = d.players.find(x => x.token === token);
    if (p) { Object.assign(p, { score: s.score, correct: s.correct, answered: s.answered, total: s.total,
             finished: s.finished, duration_s: s.duration, updated_at: new Date().toISOString() }); write(d); }
    return { ok: true };
  }

  async function getLeaderboard() {
    if (sb) return rpc('get_leaderboard');
    return read().players.filter(p => p.answered > 0)
      .sort((a, b) => b.score - a.score || a.duration_s - b.duration_s).slice(0, 10);
  }

  async function adminResults(pass) {
    if (sb) return rpc('admin_get_results', { p_pass: pass });
    if (pass !== DEMO_ADMIN) throw new Error('كلمة المرور غير صحيحة (الوضع التجريبي: demo)');
    return read().players.slice().sort((a, b) => b.updated_at.localeCompare(a.updated_at));
  }

  // ---- إحصاءات الأسئلة (إضافة مستقلة: فشلها لا يؤثر على حفظ التقدم) ----
  async function recordAnswer(token, qid, correct) {
    if (sb) return rpc('record_answer', { p_token: token, p_qid: qid, p_correct: !!correct });
    const d = read(); const p = d.players.find(x => x.token === token); if (!p) return;
    d.q = d.q || {}; const k = qid + '|' + p.grade; const s = d.q[k] || (d.q[k] = { r: 0, w: 0 });
    correct ? s.r++ : s.w++; write(d);
  }
  async function adminQuestionStats(pass) {
    if (sb) return rpc('admin_question_stats', { p_pass: pass });
    if (pass !== DEMO_ADMIN) throw new Error('كلمة المرور غير صحيحة');
    return Object.entries(read().q || {}).map(([k, s]) => { const [qid, grade] = k.split('|');
      return { qid, grade, right_count: s.r, wrong_count: s.w }; });
  }

  return { init, isCloud, registerPlayer, saveProgress, getLeaderboard, adminResults, recordAnswer, adminQuestionStats };
})();
