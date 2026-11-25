// Стемік · CRM студії.
// Працює з Supabase лише через REST API:
//   POST /auth/v1/token          — вхід працівника (Supabase Auth)
//   POST /rest/v1/rpc/crm_<fn>   — функції бази з файлів sql/04_crm_api.sql і sql/05_crm_api_v2.sql
(() => {
  'use strict';
  const cfg = window.CRM_CONFIG || {};
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => Array.from(el.querySelectorAll(s));
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  // ---------------- іконки (контурні, як в основному застосунку) ----------------
  const ICON = {
    home: '<path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/>',
    calendar: '<rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/>',
    users: '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
    ticket: '<path d="M3 7a2 2 0 0 0 2-2h14a2 2 0 0 0 2 2v3a2 2 0 0 0 0 4v3a2 2 0 0 0-2 2H5a2 2 0 0 0-2-2v-3a2 2 0 0 0 0-4z"/><line x1="13" y1="5" x2="13" y2="19" stroke-dasharray="2 2"/>',
    alert: '<circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>',
    chart: '<line x1="18" y1="20" x2="18" y2="10"/><line x1="12" y1="20" x2="12" y2="4"/><line x1="6" y1="20" x2="6" y2="14"/>',
    money: '<line x1="12" y1="1" x2="12" y2="23"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/>',
    shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
    logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/>',
    sun: '<circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/>',
    moon: '<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>',
    plus: '<line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>',
    search: '<circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>',
    x: '<line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>',
    edit: '<path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4z"/>',
    trash: '<polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/><path d="M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/>',
    check: '<polyline points="20 6 9 17 4 12"/>',
    left: '<polyline points="15 18 9 12 15 6"/>',
    right: '<polyline points="9 18 15 12 9 6"/>',
    clock: '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>',
    phone: '<path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6A19.79 19.79 0 0 1 2.12 4.18 2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/>',
  };
  const icon = (n, s = 17) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${ICON[n] || ''}</svg>`;

  // ---------------- форматування ----------------
  const DAYS = ['неділя', 'понеділок', 'вівторок', 'середа', 'четвер', 'пʼятниця', 'субота'];
  const DSHORT = ['нд', 'пн', 'вт', 'ср', 'чт', 'пт', 'сб'];
  const MONTHS = ['січня', 'лютого', 'березня', 'квітня', 'травня', 'червня', 'липня', 'серпня', 'вересня', 'жовтня', 'листопада', 'грудня'];
  const iso = (d) => new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
  const today = () => iso(new Date());
  const addDays = (s, n) => { const d = new Date(s + 'T12:00:00'); d.setDate(d.getDate() + n); return iso(d); };
  const monday = (s) => { const d = new Date(s + 'T12:00:00'); return addDays(s, -((d.getDay() + 6) % 7)); };
  const dt = (s) => new Date(s + 'T12:00:00');
  const fd = (s) => s ? `${s.slice(8, 10)}.${s.slice(5, 7)}.${s.slice(0, 4)}` : '—';
  const fdLong = (s) => s ? `${dt(s).getDate()} ${MONTHS[dt(s).getMonth()]}` : '—';
  const money = (v) => v === null || v === undefined ? '—' : (Math.round(Number(v) * 100) / 100).toLocaleString('uk-UA', { maximumFractionDigits: 2 }) + ' грн';
  const FORMAT = { group: 'Група', group_online: 'Група онлайн', individual: 'Індивідуально', individual_online: 'Індив. онлайн' };
  const TARIFF = { group_1: 'Група (1 учень)', group_2_6: 'Група (2–6)', group_online: 'Група онлайн', individual: 'Індив. очно', individual_online: 'Індив. онлайн', extra_service: 'Додаткова послуга' };
  const PAY = { card: 'Картка', cash: 'Готівка', subscription: 'Абонемент', certificate: 'Сертифікат', debt: 'Борг' };
  const STATUS = { present: 'Був', absent: 'Не був', excused: 'ВПП' };
  const SUBST = { active: ['Активний', 'ok'], completed: ['Використаний', 'muted'], cancelled: ['Скасований', 'warn'] };
  const ROLE = { superadmin: 'керівник', admin: 'адміністратор', teacher: 'викладач' };
  const tag = (t, cls = 'muted') => `<span class="tag ${cls}">${esc(t)}</span>`;
  const formatTag = (f) => `<span class="format-tag ${/individual/.test(f) ? 'individual' : ''} ${/online/.test(f) ? 'online' : ''}">${esc(FORMAT[f] || f)}</span>`;
  const initial = (name) => esc((String(name || '?').trim()[0] || '?').toUpperCase());

  // ---------------- сповіщення ----------------
  function toast(msg, bad) {
    const el = document.createElement('div');
    el.className = 'toast ' + (bad ? 'toast-error' : 'toast-success');
    el.innerHTML = icon(bad ? 'alert' : 'check', 16) + `<span>${esc(msg)}</span>`;
    el.onclick = () => el.remove();
    $('#toasts').appendChild(el);
    setTimeout(() => el.remove(), bad ? 6500 : 3000);
  }

  // ---------------- сесія і звернення до Supabase ----------------
  const store = {
    get(k) { try { return JSON.parse(sessionStorage.getItem(k)); } catch (e) { return null; } },
    set(k, v) { try { sessionStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* без збереження */ } },
    del(k) { try { sessionStorage.removeItem(k); } catch (e) { /* немає */ } },
  };
  let session = store.get('crm_session');
  let refs = null;
  const base = () => (cfg.url || '').replace(/\/+$/, '');
  const isJwt = (k) => /^eyJ/.test(k || '');
  function headers(user) {
    const h = { apikey: cfg.anonKey, 'Content-Type': 'application/json' };
    if (user && session) h.Authorization = 'Bearer ' + session.access_token;
    else if (isJwt(cfg.anonKey)) h.Authorization = 'Bearer ' + cfg.anonKey;
    return h;
  }
  function needConfig() {
    if (!cfg.url || !cfg.anonKey) throw new Error('Не заповнено config.js: вкажіть url і anonKey проєкту Supabase (див. README).');
  }
  async function auth(body, grant) {
    needConfig();
    const res = await fetch(`${base()}/auth/v1/token?grant_type=${grant}`, { method: 'POST', headers: headers(false), body: JSON.stringify(body) });
    const d = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(d.error_description || d.msg || d.message || 'Помилка входу (' + res.status + ')');
    session = { access_token: d.access_token, refresh_token: d.refresh_token,
                expires_at: Date.now() + (d.expires_in || 3600) * 1000, email: (d.user && d.user.email) || body.email };
    store.set('crm_session', session);
  }
  async function rpc(name, args, anon) {
    needConfig();
    if (!anon && session && session.refresh_token && Date.now() > session.expires_at - 60000) {
      try { await auth({ refresh_token: session.refresh_token }, 'refresh_token'); } catch (e) { logout('Сесія завершилась — увійдіть знову.'); throw e; }
    }
    let res;
    try { res = await fetch(`${base()}/rest/v1/rpc/${name}`, { method: 'POST', headers: headers(!anon), body: JSON.stringify(args || {}) }); }
    catch (e) { setSync(false); throw new Error('Немає зв’язку з Supabase: перевірте url у config.js та інтернет.'); }
    const text = await res.text();
    if (!res.ok) {
      let msg = text; try { const j = JSON.parse(text); msg = j.message || j.msg || text; } catch (e) { /* не JSON */ }
      if ((res.status === 401 || res.status === 403) && !anon && session) logout('Сесія недійсна — увійдіть знову.');
      if (/Could not find the function/.test(msg)) msg = `У базі немає функції ${name}: виконайте SQL-скрипти з README.`;
      throw new Error(msg);
    }
    setSync(true);
    return text ? JSON.parse(text) : null;
  }
  function setSync(ok) {
    const d = $('#syncDot'), t = $('#syncText');
    if (d) d.className = 'studio-sync-dot' + (ok ? '' : ' error');
    if (t) t.textContent = ok ? 'Supabase підключено' : 'Немає зв’язку з Supabase';
  }

  // ---------------- тема ----------------
  function toggleTheme() {
    const dark = document.documentElement.classList.toggle('theme-dark');
    try { localStorage.setItem('stemik-theme', dark ? 'dark' : 'light'); } catch (e) { /* без збереження */ }
    $$('.theme-toggle').forEach((b) => { b.innerHTML = icon(dark ? 'sun' : 'moon', 17); });
  }
  const themeBtn = () => `<button class="theme-toggle" data-act="theme" title="Світла / темна тема">${icon(document.documentElement.classList.contains('theme-dark') ? 'sun' : 'moon', 17)}</button>`;

  // ======================= ВХІД =======================
  function renderLogin(msg) {
    $('#root').innerHTML = `<div class="studio-app login-app" style="display:flex">
      <div class="login-blob login-blob-1"></div><div class="login-blob login-blob-2"></div>
      <div class="login-theme-toggle">${themeBtn()}</div>
      <div class="login-wrap"><form class="login-card" id="loginForm">
        <div class="login-title">Стемік</div>
        <div class="login-sub">CRM студії · вхід для працівників</div>
        <div class="login-ping"><span class="studio-sync-dot pulsing" id="pingDot"></span><div id="pingText">Перевіряю підключення до бази…</div></div>
        <div class="login-error" id="loginErr" ${msg ? '' : 'hidden'}>${icon('alert', 15)}<span>${esc(msg || '')}</span></div>
        <div class="field"><label class="field-label" for="email">E-mail</label><input type="email" id="email" autocomplete="username" required></div>
        <div class="field"><label class="field-label" for="password">Пароль</label><input type="password" id="password" autocomplete="current-password" required></div>
        <button class="studio-btn primary login-btn" type="submit">Увійти</button>
      </form>
      <div class="login-footer">STEM-студія «Стемік» · 3D-моделювання, робототехніка, VR</div></div></div>`;
    $('#loginForm').addEventListener('submit', async (ev) => {
      ev.preventDefault();
      const btn = $('button[type=submit]', ev.target), er = $('#loginErr');
      btn.disabled = true;
      try { await auth({ email: $('#email').value.trim(), password: $('#password').value }, 'password'); await start(); }
      catch (e) {
        er.hidden = false; $('span', er).textContent = e.message === 'Invalid login credentials' ? 'Невірний e-mail або пароль' : e.message;
        $('.login-card').classList.remove('shake'); void $('.login-card').offsetWidth; $('.login-card').classList.add('shake');
      } finally { btn.disabled = false; }
    });
    ping();
  }
  async function ping() {
    const dot = $('#pingDot'), txt = $('#pingText');
    try {
      const t0 = performance.now(); const p = await rpc('crm_ping', {}, true); const ms = Math.round(performance.now() - t0);
      if (!dot) return;
      dot.className = 'studio-sync-dot ok';
      txt.innerHTML = `<b>База підключена</b> · ${ms} мс<br>${p.rows.students} учнів · ${p.rows.lessons} занять · ${p.rows.subscriptions} абонементів`;
    } catch (e) { if (dot) { dot.className = 'studio-sync-dot error'; txt.innerHTML = `<b>Немає підключення</b><br>${esc(e.message)}`; } }
  }
  function logout(msg) { session = null; refs = null; store.del('crm_session'); closeModal(); renderLogin(msg); }

  // ======================= КАРКАС =======================
  const NAV = {
    work: [['home', 'home', 'Огляд дня'], ['schedule', 'calendar', 'Розклад'], ['students', 'users', 'Учні'], ['subs', 'ticket', 'Абонементи']],
    admin: [['debtors', 'alert', 'Боржники'], ['reports', 'chart', 'Звіти'], ['rates', 'money', 'Тарифи']],
  };
  const TITLES = { home: 'Огляд дня', schedule: 'Розклад', students: 'Учні', subs: 'Абонементи', debtors: 'Боржники', reports: 'Звіти', rates: 'Тарифи' };
  let state = { mode: 'work', view: 'home' };
  let studentCount = 0;

  async function start() {
    refs = await rpc('crm_refs');
    const h = location.hash.slice(1);
    if (TITLES[h]) state = { mode: NAV.admin.some((n) => n[0] === h) ? 'admin' : 'work', view: h };
    renderShell();
  }
  function renderShell() {
    const me = refs.me || {};
    $('#root').innerHTML = `<div class="studio-app"><div class="bg-grid"></div><div class="studio-shell">
      <aside class="studio-sidebar">
        <div class="studio-brand"><div class="studio-brand-mark">С</div><div><div class="studio-brand-title">Стемік</div><div class="studio-brand-sub">CRM студії</div></div></div>
        <div class="sidebar-profile" title="${esc(session.email || '')}"><div class="avatar sm">${initial(me.name || session.email)}</div>
          <div style="min-width:0"><div class="sidebar-profile-name">${esc(session.email || '')}</div><div class="students-meta">${esc(ROLE[me.role] || 'працівник')}${me.name ? ' · дії від імені: ' + esc(me.name) : ''}</div></div></div>
        <div class="mode-switch">
          <button class="mode-btn ${state.mode === 'work' ? 'active' : ''}" data-mode="work"><span class="mode-ic">${icon('calendar', 16)}</span>
            <div><div class="mode-btn-title">Робочий кабінет</div><div class="mode-btn-sub">Розклад, журнал, учні, абонементи</div></div></button>
          <button class="mode-btn ${state.mode === 'admin' ? 'active' : ''}" data-mode="admin"><span class="mode-ic">${icon('shield', 16)}</span>
            <div><div class="mode-btn-title">Адміністрування</div><div class="mode-btn-sub">Боржники, звіти, тарифи</div></div></button>
        </div>
        <div class="nav-group" id="nav"></div>
        <div class="studio-sync"><span class="studio-sync-dot" id="syncDot"></span><span id="syncText">Supabase підключено</span></div>
        <button class="studio-nav-btn logout-btn" data-act="logout">${icon('logout', 15)} Вийти</button>
      </aside>
      <main class="studio-main"><div id="view" class="tab-fade"></div></main></div></div>
      <div id="modalRoot"></div>`;
    $$('.mode-btn').forEach((b) => b.addEventListener('click', () => { state.mode = b.dataset.mode; state.view = NAV[state.mode][0][0]; renderShell(); }));
    renderNav(); go(state.view);
  }
  function renderNav() {
    $('#nav').innerHTML = NAV[state.mode].map(([id, ic, t]) => `<button class="studio-nav-btn ${state.view === id ? 'active' : ''}" data-view="${id}">
      <span class="nav-ic">${icon(ic)}</span> ${t}${id === 'students' && studentCount ? `<span class="studio-nav-badge">${studentCount}</span>` : ''}</button>`).join('');
    $$('#nav .studio-nav-btn').forEach((b) => b.addEventListener('click', () => go(b.dataset.view)));
  }
  const VIEWS = {};
  function go(view) {
    state.view = view; renderNav();
    try { history.replaceState(null, '', '#' + view); } catch (e) { /* file:// */ }
    const v = $('#view'); v.classList.remove('tab-fade'); void v.offsetWidth; v.classList.add('tab-fade');
    VIEWS[view](v);
  }
  function pageHead(title, actions = '') {
    return `<div class="studio-page-head"><div class="studio-page-title">${esc(title)}</div><div class="head-actions">${actions}${themeBtn()}</div></div>`;
  }
  const loading = (el) => { el.innerHTML = '<div class="loading-block">Завантаження з бази…</div>'; };
  const failed = (el, e) => { el.innerHTML = `<div class="login-error">${icon('alert', 15)}<span>${esc(e.message)}</span></div>`; };
  const empty = (t, s = '') => `<div class="empty-state"><div class="empty-state-title">${esc(t)}</div><div class="empty-state-sub">${esc(s)}</div></div>`;
  const statCard = (ic, value, label, color, act) => `<div class="stat-card ${act ? 'clickable' : ''}" ${act ? `data-go="${act}"` : ''} style="--stat-color:${color[0]};--stat-soft:${color[1]}">
    <div class="stat-icon">${icon(ic, 18)}</div><div><div class="stat-value">${value}</div><div class="stat-label">${esc(label)}</div></div></div>`;
  const C = { brand: ['var(--brand)', 'var(--brand-soft)'], ok: ['var(--success)', 'var(--success-soft)'], warn: ['var(--alert)', 'var(--alert-soft)'], sand: ['var(--sand-text)', 'var(--sand)'] };
  function bindGo(el) { $$('[data-go]', el).forEach((c) => c.addEventListener('click', () => {
    const v = c.dataset.go; state.mode = NAV.admin.some((n) => n[0] === v) ? 'admin' : 'work'; renderShell(); go(v); })); }
  const courseOpts = (sel, all) => (all ? '<option value="">Усі курси</option>' : '') + refs.courses.map((c) => `<option value="${c.id}" ${String(sel) === String(c.id) ? 'selected' : ''}>${esc(c.name)}</option>`).join('');
  const teacherOpts = (sel, all) => (all ? '<option value="">Усі викладачі</option>' : '') + refs.teachers.map((t) => `<option value="${t.id}" ${sel === t.id ? 'selected' : ''}>${esc(t.name)}</option>`).join('');

  function lessonRow(l) {
    const done = l.completed ? tag('Проведено', 'ok') : (l.marked >= l.enrolled && l.enrolled ? tag('Усі відмічені', 'ok') : (l.date && l.date < today() ? tag('Не закрито', 'warn') : ''));
    return `<div class="lesson-row" data-lesson="${l.lesson_id}">
      <div class="lesson-time-block">${esc(l.time || '—')}</div>
      <div class="lesson-title-block"><div class="lesson-course-line" style="color:var(--brand-text)">${esc(l.course)}</div>
        ${l.theme === undefined ? '' : `<div class="lesson-theme">${esc(l.theme || 'Без теми')}</div>`}</div>
      <div class="lesson-row-right">${formatTag(l.format)}<span class="teacher-tag">${esc(l.teacher)}</span>
        <span class="tag roster-count">${icon('users', 11)} ${l.enrolled}</span><span class="tag progress">відмічено ${l.marked}/${l.enrolled}</span>${done}</div></div>`;
  }
  function bindLessons(el, after) { $$('[data-lesson]', el).forEach((r) => r.addEventListener('click', () => openLesson(r.dataset.lesson, after))); }

  // ======================= ОГЛЯД ДНЯ =======================
  VIEWS.home = async (v, date) => {
    date = date || today();
    v.innerHTML = pageHead('Огляд дня', `<button class="studio-btn ghost" data-d="-1">${icon('left', 15)}</button>
      <button class="studio-btn ghost" data-d="0">Сьогодні</button><button class="studio-btn ghost" data-d="1">${icon('right', 15)}</button>`) + '<div id="hb"></div>';
    $$('[data-d]', v).forEach((b) => b.addEventListener('click', () => VIEWS.home(v, +b.dataset.d ? addDays(date, +b.dataset.d) : today())));
    const b = $('#hb'); loading(b);
    try {
      const d = await rpc('crm_dashboard', { p_date: date }); const k = d.kpi; studentCount = k.students; renderNav();
      const next = d.lessons.find((l) => !l.completed) || d.lessons[0];
      b.innerHTML = `<div class="stats-row">
          ${statCard('calendar', d.lessons.length, 'занять ' + (date === today() ? 'сьогодні' : fdLong(date)), C.brand, 'schedule')}
          ${statCard('clock', k.week_lessons, 'занять цього тижня', C.sand, 'schedule')}
          ${statCard('users', k.students, 'активних учнів', C.ok, 'students')}
          ${statCard('ticket', k.active_subscriptions, `активних абонементів · ${k.ending_subscriptions} закінчуються`, C.brand, 'subs')}
          ${statCard('alert', k.unpaid_visits, `неоплачених відвідувань · ${money(k.unpaid_sum)}`, C.warn, 'debtors')}</div>
        ${next ? `<div class="studio-hero" data-lesson="${next.lesson_id}" style="cursor:pointer">
          <div class="datecard big"><div class="datecard-top">${esc(DSHORT[dt(date).getDay()].toUpperCase())}</div><div class="datecard-body">
            <div class="datecard-day">${dt(date).getDate()}</div><div class="datecard-weekday">${esc(MONTHS[dt(date).getMonth()])}</div><div class="datecard-time">${esc(next.time || '')}</div></div></div>
          <div><div class="studio-hero-label">${next.completed ? 'Заняття дня' : 'Найближче заняття'}</div>
            <div class="studio-hero-theme">${esc(next.course)}</div>
            <div class="studio-hero-date">${esc(next.substitute ? next.substitute + ' (заміна)' : next.teacher)} · ${esc(FORMAT[next.format] || next.format)} · записано ${next.enrolled}, відмічено ${next.marked}</div>
            <div class="studio-hero-date" style="margin-top:8px">Натисніть, щоб відкрити журнал заняття</div></div></div>` : ''}
        <div class="week-day ${date === today() ? 'today' : ''}"><div class="week-day-head"><div><div class="week-day-name">${esc(DAYS[dt(date).getDay()])}</div>
          <div class="week-day-date">${fd(date)}</div></div>${date === today() ? '<span class="today-badge">сьогодні</span>' : ''}</div>
          ${d.lessons.length ? d.lessons.map((l) => lessonRow(Object.assign({}, l, { date, teacher: l.substitute ? l.substitute + ' (заміна)' : l.teacher }))).join('') : '<div class="week-day-empty">Занять немає</div>'}</div>`;
      bindGo(b); bindLessons(b, () => VIEWS.home(v, date));
    } catch (e) { failed(b, e); }
  };

  // ======================= РОЗКЛАД =======================
  let sched = { from: monday(today()), course: '', teacher: '' };
  VIEWS.schedule = (v) => {
    v.innerHTML = pageHead('Розклад', `<button class="studio-btn primary" data-act="newLesson">${icon('plus', 15)} Заняття</button>`) +
      `<div class="filters"><div class="week-nav"><button class="studio-btn ghost" data-w="-7">${icon('left', 15)}</button>
        <div class="week-label" id="wl"></div><button class="studio-btn ghost" data-w="7">${icon('right', 15)}</button>
        <button class="studio-btn ghost" data-w="0">Цей тиждень</button></div>
        <select id="fCourse">${courseOpts(sched.course, true)}</select><select id="fTeacher">${teacherOpts(sched.teacher, true)}</select></div>
      <div id="sb"></div>`;
    $$('[data-w]', v).forEach((b) => b.addEventListener('click', () => { sched.from = +b.dataset.w ? addDays(sched.from, +b.dataset.w) : monday(today()); load(); }));
    $('#fCourse').addEventListener('change', (e) => { sched.course = e.target.value; load(); });
    $('#fTeacher').addEventListener('change', (e) => { sched.teacher = e.target.value; load(); });
    $('[data-act=newLesson]', v).addEventListener('click', () => lessonForm(null, load));
    async function load() {
      const to = addDays(sched.from, 6);
      $('#wl').textContent = `${fdLong(sched.from)} – ${fdLong(to)}`;
      const b = $('#sb'); loading(b);
      try {
        const rows = await rpc('crm_lessons', { p_from: sched.from, p_to: to, p_course: sched.course || null, p_teacher: sched.teacher || null });
        const days = [...Array(7)].map((_, i) => addDays(sched.from, i));
        b.innerHTML = `<div class="week-list">${days.map((day) => {
          const ls = rows.filter((r) => r.lesson_date === day);
          return `<div class="week-day ${day === today() ? 'today' : ''}"><div class="week-day-head"><div><div class="week-day-name">${esc(DAYS[dt(day).getDay()])}</div>
            <div class="week-day-date">${fd(day)}</div></div>${day === today() ? '<span class="today-badge">сьогодні</span>' : ''}</div>
            ${ls.length ? ls.map((l) => lessonRow({ lesson_id: l.lesson_id, time: l.start_time, course: l.course, theme: l.theme, format: l.format, teacher: l.teacher,
              enrolled: l.enrolled, marked: l.marked, completed: l.completed, date: l.lesson_date })).join('') : '<div class="week-day-empty">Занять немає</div>'}</div>`;
        }).join('')}</div>`;
        bindLessons(b, load);
      } catch (e) { failed(b, e); }
    }
    load();
  };

  // ======================= УЧНІ =======================
  let stu = { q: '', active: true };
  VIEWS.students = (v) => {
    v.innerHTML = pageHead('Учні', `<button class="studio-btn primary" data-act="newStudent">${icon('plus', 15)} Учень</button>`) +
      `<div class="search-field">${icon('search', 16)}<input id="sq" placeholder="Пошук: ім’я учня, ім’я батьків або частина телефону" value="${esc(stu.q)}" autocomplete="off">
        <button class="search-clear" id="sqc" title="Очистити">${icon('x', 14)}</button></div>
      <div class="filters"><div class="studio-segmented"><button data-a="1" class="${stu.active ? 'active' : ''}">Активні</button><button data-a="0" class="${stu.active ? '' : 'active'}">Усі, разом з неактивними</button></div></div>
      <div id="stb"></div>`;
    let t;
    const run = async () => {
      const b = $('#stb'); loading(b);
      try {
        const rows = await rpc('crm_students', { p_q: stu.q, p_active_only: stu.active });
        if (!stu.q && stu.active) { studentCount = rows.length; renderNav(); }
        b.innerHTML = rows.length ? `<p class="hint" style="margin:-4px 0 10px">Знайдено: ${rows.length}</p><div class="students-list">${rows.map((r) => `
          <div class="students-row admin-row" data-student="${r.student_id}"><div class="avatar">${initial(r.student)}</div>
            <div style="flex:1;min-width:0"><div class="student-name">${esc(r.student)}</div>
              <div class="students-sub">${esc(r.parents || 'батьків не вказано')}</div>
              <div class="students-meta">${esc(r.courses || 'немає занять за 2 місяці')}${r.last_visit ? ' · останній візит ' + fd(r.last_visit) : ''}</div></div>
            <div class="lesson-row-right">${r.subscriptions ? r.subscriptions.split('; ').map((s) => `<span class="format-tag">${esc(s)}</span>`).join('') : ''}
              ${r.unpaid ? tag('Борг: ' + r.unpaid + ' зан.', 'warn') : ''}</div></div>`).join('')}</div>` : empty('Нікого не знайдено', 'Спробуйте частину імені або телефону');
        bindStudents(b, run);
      } catch (e) { failed(b, e); }
    };
    $('#sq').addEventListener('input', (e) => { stu.q = e.target.value; clearTimeout(t); t = setTimeout(run, 300); });
    $('#sqc').addEventListener('click', () => { stu.q = ''; $('#sq').value = ''; run(); });
    $$('[data-a]', v).forEach((b) => b.addEventListener('click', () => { stu.active = b.dataset.a === '1'; VIEWS.students(v); }));
    $('[data-act=newStudent]', v).addEventListener('click', () => studentForm(null, run));
    run();
  };
  function bindStudents(el, after) { $$('[data-student]', el).forEach((r) => r.addEventListener('click', () => openStudent(r.dataset.student, after))); }

  // ======================= АБОНЕМЕНТИ =======================
  let subSt = 'active';
  VIEWS.subs = (v) => {
    v.innerHTML = pageHead('Абонементи', `<button class="studio-btn primary" data-act="sell">${icon('plus', 15)} Абонемент</button>`) +
      `<div class="filters"><div class="studio-segmented">${[['active', 'Активні'], ['completed', 'Використані'], ['cancelled', 'Скасовані'], ['', 'Усі']].map(([k, t]) =>
        `<button data-s="${k}" class="${subSt === k ? 'active' : ''}">${t}</button>`).join('')}</div></div><div id="ab"></div>`;
    $$('[data-s]', v).forEach((b) => b.addEventListener('click', () => { subSt = b.dataset.s; VIEWS.subs(v); }));
    const run = async () => {
      const b = $('#ab'); loading(b);
      try {
        const rows = await rpc('crm_subscriptions', { p_status: subSt });
        b.innerHTML = rows.length ? `<div class="students-list">${rows.map((r) => `
          <div class="students-row"><div class="avatar">${initial(r.student)}</div>
            <div style="flex:1;min-width:0;cursor:pointer" data-student="${r.student_id}"><div class="student-name">${esc(r.student)}</div>
              <div class="students-sub">${esc(r.course)} · куплено ${fd(r.purchased_at)} · ${money(r.price)}${r.payment ? ' · ' + esc(PAY[r.payment] || r.payment) : ''}</div>
              <div class="students-meta">${r.last_visit ? 'останній візит ' + fd(r.last_visit) : 'ще не використовувався'} · ${esc(r.parent_phones || 'без телефону')}</div></div>
            <div class="lesson-row-right"><span class="tag progress" style="margin-left:0">${r.remaining} з ${r.total}</span>${tag(...(SUBST[r.status] || [r.status]))}
              ${r.status === 'active' ? `<button class="studio-btn ghost" data-cancel="${r.subscription_id}" title="Скасувати абонемент">${icon('x', 14)}</button>` : ''}</div></div>`).join('')}</div>` : empty('Абонементів немає');
        bindStudents(b, run);
        $$('[data-cancel]', b).forEach((x) => x.addEventListener('click', (e) => {
          e.stopPropagation();
          confirmBox('Скасувати абонемент?', 'Абонемент отримає статус «скасований». Уже використані заняття лишаться в історії відвідувань.', 'Скасувати абонемент', async () => {
            await rpc('crm_subscription_cancel', { p_id: x.dataset.cancel }); toast('Абонемент скасовано'); run();
          });
        }));
      } catch (e) { failed(b, e); }
    };
    $('[data-act=sell]', v).addEventListener('click', () => subForm(null, run));
    run();
  };

  // ======================= БОРЖНИКИ =======================
  let debtMin = 1;
  VIEWS.debtors = (v) => {
    v.innerHTML = pageHead('Боржники') + `<div class="filters"><span class="label">Неоплачених занять, не менше</span>
      <div class="studio-segmented">${[1, 2, 3].map((n) => `<button data-m="${n}" class="${debtMin === n ? 'active' : ''}">${n}</button>`).join('')}</div></div><div id="db"></div>`;
    $$('[data-m]', v).forEach((b) => b.addEventListener('click', () => { debtMin = +b.dataset.m; VIEWS.debtors(v); }));
    (async () => {
      const b = $('#db'); loading(b);
      try {
        const rows = await rpc('crm_debtors', { p_min: debtMin });
        const sum = rows.reduce((s, r) => s + Number(r.debt), 0);
        b.innerHTML = `<div class="stats-row">${statCard('users', rows.length, 'учнів з боргом', C.warn)}${statCard('money', money(sum), 'загальна сума боргу', C.warn)}</div>` +
          (rows.length ? `<div class="students-list">${rows.map((r) => `<div class="students-row admin-row" data-student="${r.student_id}">
            <div class="avatar">${initial(r.student)}</div><div style="flex:1;min-width:0"><div class="student-name">${esc(r.student)}</div>
            <div class="students-sub">${esc(r.courses)} · ${fd(r.first_unpaid)} – ${fd(r.last_unpaid)}</div>
            <div class="students-meta">${icon('phone', 11)} ${esc(r.parent_phones || 'без телефону')}</div></div>
            <div class="lesson-row-right">${tag(r.unpaid_visits + ' зан.', 'warn')}<span class="money debt">${money(r.debt)}</span></div></div>`).join('')}</div>` : empty('Боржників немає'));
        bindStudents(b, () => VIEWS.debtors(v));
      } catch (e) { failed(b, e); }
    })();
  };

  // ======================= ЗВІТИ =======================
  let rep = { kind: 'revenue', from: '2026-09-01', to: addDays(today(), 0) };
  const REPORTS = [['revenue', 'Виручка'], ['weekly', 'По тижнях'], ['teachers', 'Викладачі'], ['courses', 'Курси'], ['dropped', 'Випали з розкладу']];
  VIEWS.reports = (v) => {
    v.innerHTML = pageHead('Звіти') + `<div class="filters"><div class="studio-segmented format-segmented">${REPORTS.map(([k, t]) =>
        `<button data-r="${k}" class="${rep.kind === k ? 'active' : ''}">${t}</button>`).join('')}</div>
      ${rep.kind !== 'dropped' ? `<span class="label">з</span><input type="date" id="rf" value="${rep.from}"><span class="label">по</span><input type="date" id="rt" value="${rep.to}">` : ''}</div>
      <div id="rb"></div>`;
    $$('[data-r]', v).forEach((b) => b.addEventListener('click', () => { rep.kind = b.dataset.r; VIEWS.reports(v); }));
    ['rf', 'rt'].forEach((id) => $('#' + id) && $('#' + id).addEventListener('change', () => { rep.from = $('#rf').value; rep.to = $('#rt').value; draw(); }));
    const bar = (val, max, alt) => `<div class="bar ${alt ? 'alt' : ''}"><span style="width:${max ? Math.max(2, 100 * val / max) : 0}%"></span></div>`;
    const table = (head, rows) => `<div class="rate-table-wrap"><table class="rate-table"><tr>${head.map(([h, n]) => `<th class="${n ? 'n' : ''}">${h}</th>`).join('')}</tr>${rows.join('')}</table></div>`;
    async function draw() {
      const b = $('#rb'); loading(b); const p = { p_from: rep.from, p_to: rep.to };
      try {
        if (rep.kind === 'revenue') {
          const r = await rpc('crm_report_revenue', p);
          const months = [...new Set(r.map((x) => x.month))];
          const paid = r.filter((x) => x.payment !== 'debt').reduce((s, x) => s + Number(x.amount), 0);
          const debt = r.filter((x) => x.payment === 'debt').reduce((s, x) => s + Number(x.amount), 0);
          const max = Math.max(...r.map((x) => Number(x.amount)), 0);
          b.innerHTML = `<div class="stats-row">${statCard('money', money(paid), 'отримано за період', C.ok)}${statCard('alert', money(debt), 'не оплачено (борг)', C.warn)}
            ${statCard('users', r.reduce((s, x) => s + Number(x.visits), 0), 'відвідувань «був»', C.brand)}</div>
            <p class="report-note">Частка — внесок способу оплати у суму місяця.</p>` +
            table([['Місяць'], ['Спосіб оплати'], ['Відвідувань', 1], ['Сума', 1], ['Частка', 1], ['']], months.flatMap((m) => r.filter((x) => x.month === m).map((x, i) =>
              `<tr><td>${i ? '' : `<b>${esc(MONTHS[+m.slice(5) - 1])} ${m.slice(0, 4)}</b>`}</td><td>${esc(PAY[x.payment] || x.payment)}</td><td class="n">${x.visits}</td>
              <td class="n"><span class="money ${x.payment === 'debt' ? 'debt' : ''}">${money(x.amount)}</span></td><td class="n">${x.share ?? '—'}%</td><td style="width:160px">${bar(Number(x.amount), max, x.payment === 'debt')}</td></tr>`)));
        } else if (rep.kind === 'weekly') {
          const r = await rpc('crm_report_weekly', p);
          const max = Math.max(...r.map((x) => Number(x.paid)), 0);
          b.innerHTML = `<p class="report-note">Наростаючий підсумок — сума отриманого з початку періоду.</p>` + table([['Тиждень з'], ['Отримано', 1], ['Борг', 1], ['Наростаючим', 1], ['']], r.map((x) =>
            `<tr><td>${fd(x.week)}</td><td class="n"><span class="money">${money(x.paid)}</span></td><td class="n">${Number(x.debt) ? `<span class="money debt">${money(x.debt)}</span>` : '—'}</td>
            <td class="n"><b>${money(x.cumulative)}</b></td><td style="width:180px">${bar(Number(x.paid), max)}</td></tr>`));
        } else if (rep.kind === 'teachers') {
          const r = await rpc('crm_report_teachers', Object.assign({ p_min_lessons: 1 }, p));
          const max = Math.max(...r.map((x) => Number(x.lessons)), 0);
          b.innerHTML = `<p class="report-note">Оплата — за заняттями, позначеними як проведені.</p>` + table([['Викладач'], ['Роль'], ['Занять', 1], ['Проведено', 1], ['Учнемісць', 1], ['Сер. група', 1], ['Оплата', 1], ['']], r.map((x) =>
            `<tr><td><b>${esc(x.teacher)}</b></td><td>${esc(ROLE[x.role] || x.role)}</td><td class="n">${x.lessons}</td><td class="n">${x.completed}</td><td class="n">${x.seats}</td>
            <td class="n">${x.avg_group ?? '—'}</td><td class="n"><span class="money">${money(x.payroll)}</span></td><td style="width:150px">${bar(Number(x.lessons), max)}</td></tr>`));
        } else if (rep.kind === 'courses') {
          const r = await rpc('crm_report_courses', p);
          b.innerHTML = `<p class="report-note">Відвідуваність — частка відміток «був» серед усіх відміток курсу.</p>` + table([['Курс'], ['Учнів', 1], ['Занять', 1], ['Сер. група', 1], ['Макс.', 1], ['Відвідуваність', 1], ['Виручка', 1]], r.map((x) =>
            `<tr><td><span class="course-tag">${esc(x.direction)}</span> <b>${esc(x.course)}</b></td><td class="n">${x.students}</td><td class="n">${x.lessons}</td><td class="n">${x.avg_group ?? '—'}</td>
            <td class="n">${x.max_group ?? '—'}</td><td class="n">${x.present_pct === null ? '—' : x.present_pct + '%'}</td><td class="n"><span class="money">${money(x.revenue)}</span></td></tr>`));
        } else {
          const r = await rpc('crm_report_dropped', { p_today: today() });
          b.innerHTML = `<p class="report-note">Учні, які відвідували заняття, але не записані на жодне майбутнє, — варто зателефонувати батькам.</p>` +
            (r.length ? `<div class="students-list">${r.map((x) => `<div class="students-row admin-row" data-student="${x.student_id}"><div class="avatar">${initial(x.student)}</div>
              <div style="flex:1;min-width:0"><div class="student-name">${esc(x.student)}</div><div class="students-sub">${esc(x.courses || '')}</div>
              <div class="students-meta">${icon('phone', 11)} ${esc(x.parent_phones || 'без телефону')}</div></div>
              <div class="lesson-row-right">${tag(x.visits + ' відвідувань', 'muted')}${tag('останній ' + fd(x.last_visit), 'warn')}</div></div>`).join('')}</div>` : empty('Таких учнів немає'));
          bindStudents(b, draw);
        }
      } catch (e) { failed(b, e); }
    }
    draw();
  };

  // ======================= ТАРИФИ =======================
  VIEWS.rates = async (v) => {
    v.innerHTML = pageHead('Тарифи') + `<div class="info-banner">${icon('alert', 15)} Нові ціни діють для нових занять і абонементів. Ціна вже проведених занять зафіксована в самому занятті й не зміниться.</div><div id="tb"></div>`;
    const b = $('#tb'); loading(b);
    try {
      const rows = await rpc('crm_tariffs');
      let last = '';
      b.innerHTML = `<div class="rate-table-wrap"><table class="rate-table"><tr><th>Курс</th><th>Тип заняття</th><th class="n">Оплата викладачу</th><th class="n">Ціна заняття</th><th class="n">Ціна абонемента</th><th></th></tr>
        ${rows.map((r) => { const first = r.course !== last; last = r.course;
          return `<tr data-t="${r.tariff_id}" style="${first ? 'border-top:2px solid var(--line-strong)' : ''}"><td>${first ? `<span class="course-tag">${esc(r.direction)}</span> <span class="rate-course-name">${esc(r.course)}</span>` : ''}</td>
          <td>${esc(TARIFF[r.tariff_type] || r.tariff_type)}</td>
          ${['teacher_pay', 'lesson_price', 'subscription_price'].map((f) => `<td class="n"><input class="rate-input" type="number" min="0" step="10" data-f="${f}" value="${r[f] ?? ''}" data-orig="${r[f] ?? ''}"></td>`).join('')}
          <td><button class="studio-btn ghost" data-save hidden>${icon('check', 14)} Зберегти</button></td></tr>`; }).join('')}</table></div>`;
      $$('tr[data-t]', b).forEach((tr) => {
        const btn = $('[data-save]', tr);
        $$('input', tr).forEach((i) => i.addEventListener('input', () => {
          i.classList.toggle('dirty', i.value !== i.dataset.orig); btn.hidden = !$$('input', tr).some((x) => x.value !== x.dataset.orig);
        }));
        btn.addEventListener('click', async () => {
          const val = (f) => { const x = $(`[data-f=${f}]`, tr).value; return x === '' ? null : Number(x); };
          btn.disabled = true;
          try {
            await rpc('crm_tariff_save', { p_id: +tr.dataset.t, p_teacher_pay: val('teacher_pay') ?? 0, p_lesson_price: val('lesson_price') ?? 0, p_subscription_price: val('subscription_price') });
            $$('input', tr).forEach((i) => { i.dataset.orig = i.value; i.classList.remove('dirty'); }); btn.hidden = true; toast('Тариф збережено');
          } catch (e) { toast(e.message, true); } finally { btn.disabled = false; }
        });
      });
    } catch (e) { failed(b, e); }
  };

  // ======================= МОДАЛЬНІ ВІКНА =======================
  let onModalClose = null;
  function openModal(html, cls = '', onClose) {
    onModalClose = onClose || null;
    $('#modalRoot').innerHTML = `<div class="overlay" id="ov"><div class="modal ${cls}">${html}</div></div>`;
    $('#ov').addEventListener('click', (e) => { if (e.target.id === 'ov') closeModal(); });
    $$('[data-close]', $('#ov')).forEach((b) => b.addEventListener('click', closeModal));
    return $('#ov .modal');
  }
  function closeModal() {
    const r = $('#modalRoot'); if (r) r.innerHTML = '';
    const cb = onModalClose; onModalClose = null; if (cb) cb();
  }
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && $('#ov')) closeModal(); });
  const mTitle = (t) => `<div class="modal-title"><span>${esc(t)}</span><button class="search-clear" data-close title="Закрити">${icon('x', 18)}</button></div>`;
  function confirmBox(title, text, okText, action) {
    const prev = onModalClose; onModalClose = null;
    const m = openModal(`${mTitle(title)}<div class="confirm-message">${esc(text)}</div>
      <div class="modal-actions"><button class="studio-btn" data-close>Відмінити</button><button class="studio-btn danger" id="okBtn">${esc(okText)}</button></div>`, 'confirm-modal', prev);
    $('#okBtn', m).addEventListener('click', async (e) => {
      e.target.disabled = true;
      try { await action(); } catch (er) { toast(er.message, true); } finally { closeModal(); }
    });
  }
  function picker(el, onPick) {
    el.innerHTML = `<div class="picker"><div class="search-field" style="margin:0">${icon('search', 15)}<input placeholder="Почніть вводити ім’я або телефон" autocomplete="off"></div><div class="picker-list" hidden></div></div>`;
    const inp = $('input', el), list = $('.picker-list', el); let t;
    inp.addEventListener('input', () => { clearTimeout(t); t = setTimeout(async () => {
      if (inp.value.trim().length < 2) { list.hidden = true; return; }
      const rows = (await rpc('crm_students', { p_q: inp.value, p_active_only: true })).slice(0, 8);
      list.innerHTML = rows.map((r, i) => `<div class="picker-item" data-i="${i}">${esc(r.student)}<small>${esc(r.parents || '')}</small></div>`).join('') || '<div class="picker-item">нічого не знайдено</div>';
      list.hidden = false;
      $$('[data-i]', list).forEach((x) => x.addEventListener('click', () => { const r = rows[+x.dataset.i]; inp.value = r.student; list.hidden = true; onPick(r); }));
    }, 250); });
  }

  // ---------- журнал заняття ----------
  async function openLesson(id, after) {
    const m = openModal('<div class="loading-block">Завантаження журналу…</div>', 'lesson-card-modal', after);
    let d;
    try { d = await rpc('crm_lesson', { p_id: id }); } catch (e) { failed(m, e); return; }
    const L = d.lesson; const marked = d.students.filter((s) => s.status).length;
    m.innerHTML = `${mTitle('Журнал заняття')}
      <div class="lesson-head-left"><div class="datecard big"><div class="datecard-top">${esc(DSHORT[dt(L.date).getDay()].toUpperCase())}</div><div class="datecard-body">
        <div class="datecard-day">${dt(L.date).getDate()}</div><div class="datecard-weekday">${esc(MONTHS[dt(L.date).getMonth()])}</div><div class="datecard-time">${esc(L.time || '')}</div></div></div>
        <div class="lesson-title-block"><div class="lesson-course-line" style="color:var(--brand-text)">${esc(L.course)}</div><div class="lesson-theme">${esc(L.theme || 'Без теми')}</div>
          <div class="lesson-meta-row" style="padding:6px 0 0">${formatTag(L.format)}<span class="teacher-tag">${esc(L.teacher)}</span>
            <span class="tag muted">${L.duration} хв</span><span class="tag muted">${money(L.price)}</span><span class="tag progress" style="margin-left:0">відмічено ${marked}/${d.students.length}</span></div></div></div>
      <div class="roster" style="margin:14px 0 6px">${d.students.map((s, i) => {
        const pay = s.status === 'present' ? (s.payment || 'debt') : (s.subscription ? 'subscription' : 'card');
        return `<div class="roster-row" data-i="${i}"><div class="roster-top"><div class="avatar sm">${initial(s.student)}</div>
          <span class="roster-name" style="cursor:pointer" data-stu>${esc(s.student)}</span>
          ${s.subscription ? `<span class="format-tag">абонемент ${esc(s.subscription)}</span>` : ''}
          ${s.status === 'present' ? `<span class="money ${s.payment ? '' : 'debt'}">${money(s.amount)}${s.payment ? '' : ' борг'}</span>` : ''}</div>
          <div class="attend-block"><div class="attend-line"><span class="attend-line-label">Відмітка</span><div class="attend-switch">
            ${['present', 'absent', 'excused'].map((st) => `<button class="attend-btn ${st} ${s.status === st ? 'active' : ''} ${st === 'present' && s.status === 'present' && !s.payment ? 'unpaid' : ''}" data-st="${st}">${STATUS[st]}</button>`).join('')}</div></div>
            <div class="attend-line"><span class="attend-line-label">Оплата</span><div class="pay-chips">
            ${['card', 'cash', 'subscription', 'debt'].map((p) => `<span class="chip payment-chip ${pay === p ? 'selected' : ''}" data-pay="${p}" ${p === 'subscription' && !s.subscription ? 'style="opacity:.4;pointer-events:none" title="Немає активного абонемента на цей курс"' : ''}>${PAY[p]}</span>`).join('')}</div></div></div>
          ${s.status ? '' : `<div style="text-align:right;margin-top:6px"><button class="search-clear" data-rm title="Прибрати із запису на заняття" style="display:inline-flex;gap:4px;font-size:12px;padding:3px 6px">${icon('x', 12)} прибрати із запису</button></div>`}</div>`;
      }).join('') || '<div class="week-day-empty" style="padding:14px 0">На заняття ще нікого не записано</div>'}</div>
      <div class="field"><label class="field-label">Записати учня на заняття</label><div id="addStu"></div></div>
      <div class="hint">Оберіть оплату, потім «Був». «Абонемент» списує одне заняття; повторна відмітка спершу повертає списане.</div>
      <div class="modal-actions" style="justify-content:space-between;flex-wrap:wrap">
        <div style="display:flex;gap:8px"><button class="studio-btn ghost" id="lEdit">${icon('edit', 14)} Змінити</button><button class="studio-btn danger" id="lDel">${icon('trash', 14)} Видалити</button></div>
        <button class="studio-btn ${L.completed ? '' : 'primary'}" id="lDone">${icon('check', 14)} ${L.completed ? 'Відкрити знову' : 'Заняття проведено'}</button></div>`;
    $$('[data-close]', m).forEach((b) => b.addEventListener('click', closeModal));
    $$('.roster-row', m).forEach((row) => {
      const s = d.students[+row.dataset.i];
      $$('[data-pay]', row).forEach((c) => c.addEventListener('click', () => { $$('[data-pay]', row).forEach((x) => x.classList.remove('selected')); c.classList.add('selected'); }));
      $('[data-stu]', row).addEventListener('click', () => { onModalClose = null; openStudent(s.student_id, after); });
      $$('[data-st]', row).forEach((b) => b.addEventListener('click', async () => {
        const pay = ($('[data-pay].selected', row) || {}).dataset?.pay;
        $$('[data-st]', row).forEach((x) => { x.disabled = true; });
        try {
          const r = await rpc('crm_mark', { p_lesson: L.lesson_id, p_student: s.student_id, p_status: b.dataset.st,
                                            p_payment: b.dataset.st === 'present' ? (pay === 'debt' ? null : pay) : null });
          toast(`${s.student}: ${STATUS[r.status]}${r.status === 'present' ? ' · ' + (r.payment ? PAY[r.payment] : 'борг') + ' · ' + money(r.amount) : ''}${r.subscription ? ' · залишок ' + r.subscription : ''}`);
          openLesson(id, after);
        } catch (e) { toast(e.message, true); $$('[data-st]', row).forEach((x) => { x.disabled = false; }); }
      }));
      const rm = $('[data-rm]', row);
      if (rm) rm.addEventListener('click', async () => {
        try { await rpc('crm_lesson_remove_student', { p_lesson: L.lesson_id, p_student: s.student_id }); toast(s.student + ' — прибрано із запису'); openLesson(id, after); }
        catch (e) { toast(e.message, true); }
      });
    });
    picker($('#addStu', m), async (r) => {
      try { await rpc('crm_lesson_add_student', { p_lesson: L.lesson_id, p_student: r.student_id }); toast(r.student + ' записаний на заняття'); openLesson(id, after); }
      catch (e) { toast(e.message, true); }
    });
    $('#lDone', m).addEventListener('click', async () => {
      try { await rpc('crm_lesson_complete', { p_lesson: L.lesson_id, p_completed: !L.completed }); toast(L.completed ? 'Заняття знову відкрите' : 'Заняття позначено проведеним'); openLesson(id, after); }
      catch (e) { toast(e.message, true); }
    });
    $('#lEdit', m).addEventListener('click', () => { onModalClose = null; lessonForm(L, after); });
    $('#lDel', m).addEventListener('click', () => confirmBox('Видалити заняття?',
      marked ? `На занятті вже є відмітки (${marked}). База не дозволить видалити заняття з історією оплат — його можна лише змінити.` :
        `Заняття ${fd(L.date)} о ${L.time || '—'} буде видалено разом із записами учнів на нього (${d.students.length}).`,
      'Видалити', async () => { const r = await rpc('crm_lesson_delete', { p_id: L.lesson_id }); toast(`Заняття видалено, записів прибрано: ${r.enrolled_removed}`); }));
  }

  // ---------- картка учня ----------
  async function openStudent(id, after) {
    const m = openModal('<div class="loading-block">Завантаження картки…</div>', 'student-card-modal', after);
    let d;
    try { d = await rpc('crm_student', { p_id: id }); } catch (e) { failed(m, e); return; }
    const s = d.student; let tab = 'profile';
    const draw = () => {
      m.innerHTML = `${mTitle('Картка учня')}
        <div class="student-card-head"><div class="avatar lg">${initial(s.last_name)}</div><div style="min-width:0">
          <div class="student-card-name">${esc(s.last_name)} ${esc(s.first_name)}</div>
          <div class="students-meta">${s.phone ? icon('phone', 11) + ' ' + esc(s.phone) : 'телефон учня не вказано'}${s.birthday ? ' · народився ' + fd(s.birthday) : ''}</div>
          <div style="margin-top:6px">${s.active ? tag('Активний', 'ok') : tag('Неактивний', 'warn')}</div></div></div>
        <div class="modal-tabs">${[['profile', 'Профіль'], ['subs', `Абонементи (${d.subscriptions.length})`], ['visits', `Відвідування (${d.visits.length})`]].map(([k, t]) =>
          `<button class="modal-tab ${tab === k ? 'active' : ''}" data-tab="${k}">${t}</button>`).join('')}</div>
        <div id="tabBody"></div>
        <div class="modal-actions" style="justify-content:space-between;flex-wrap:wrap">
          <button class="studio-btn ${s.active ? 'danger' : ''}" id="sAct">${s.active ? 'Деактивувати' : 'Активувати'}</button>
          <div style="display:flex;gap:8px;flex-wrap:wrap"><button class="studio-btn ghost" id="sEdit">${icon('edit', 14)} Змінити</button>
            ${s.active ? `<button class="studio-btn primary" id="sSell">${icon('plus', 14)} Абонемент</button>` : ''}</div></div>`;
      const tb = $('#tabBody', m);
      if (tab === 'profile') {
        tb.innerHTML = `<div class="section-title">Батьки</div>${d.parents.length ? d.parents.map((p) => `<div class="students-row" style="padding:8px 0;border-bottom:none">
            <div class="avatar sm">${initial(p.last_name || p.phone)}</div><div style="flex:1"><div class="student-name">${esc([p.last_name, p.first_name].filter(Boolean).join(' ') || 'без імені')}</div>
            <div class="students-meta">${esc(p.relation)}</div></div><a class="tel-link" href="tel:+${esc(p.phone)}">${icon('phone', 12)} ${esc(p.phone)}</a></div>`).join('') : '<div class="hint">не вказано</div>'}
          ${s.notes ? `<div class="section-title">Нотатки</div><div class="confirm-message">${esc(s.notes)}</div>` : ''}
          <div class="section-title">Найближчі заняття</div>${d.upcoming.length ? `<div class="list-card">${d.upcoming.map((u) => `<div class="lesson-row" data-lesson="${u.lesson_id}">
            <div class="lesson-time-block">${esc(u.time || '—')}</div><div class="lesson-title-block"><div class="lesson-course-line" style="color:var(--brand-text)">${esc(u.course)}</div>
            <div class="students-meta">${esc(DAYS[dt(u.date).getDay()])}, ${fd(u.date)}</div></div></div>`).join('')}</div>` : '<div class="hint">не записаний на майбутні заняття</div>'}
          ${d.comments.length ? `<div class="section-title">Коментарі</div>${d.comments.map((c) => `<div class="confirm-message"><span class="students-meta">${fd(c.created_at)}</span> ${esc(c.body)}</div>`).join('')}` : ''}`;
        $$('[data-lesson]', tb).forEach((r) => r.addEventListener('click', () => { onModalClose = null; openLesson(r.dataset.lesson, after); }));
      } else if (tab === 'subs') {
        tb.innerHTML = d.subscriptions.length ? d.subscriptions.map((x) => `<div class="students-row" style="padding:10px 0">
          <div style="flex:1"><div class="student-name">${esc(x.course)}</div><div class="students-meta">куплено ${fd(x.purchased_at)} · ${money(x.price)}</div></div>
          <span class="tag progress" style="margin-left:0">${x.remaining} з ${x.total}</span>${tag(...(SUBST[x.status] || [x.status]))}</div>`).join('') : '<div class="hint">абонементів немає</div>';
      } else {
        tb.innerHTML = d.visits.length ? `<div class="rate-table-wrap"><table class="rate-table" style="min-width:0"><tr><th>Дата</th><th>Курс</th><th>Відмітка</th><th class="n">Сума</th></tr>
          ${d.visits.map((x) => `<tr><td>${fd(x.date)}</td><td>${esc(x.course)}</td><td>${esc(STATUS[x.status])}${x.status === 'present' ? ' · ' + esc(PAY[x.payment || 'debt']) : ''}</td>
          <td class="n">${x.status === 'present' ? `<span class="money ${x.payment ? '' : 'debt'}">${money(x.amount)}</span>` : ''}</td></tr>`).join('')}</table></div>` : '<div class="hint">відвідувань ще немає</div>';
      }
      $$('[data-close]', m).forEach((b) => b.addEventListener('click', closeModal));
      $$('[data-tab]', m).forEach((b) => b.addEventListener('click', () => { tab = b.dataset.tab; draw(); }));
      $('#sEdit', m).addEventListener('click', () => { onModalClose = null; studentForm(d, after); });
      if ($('#sSell', m)) $('#sSell', m).addEventListener('click', () => { onModalClose = null; subForm({ student_id: id, student: s.last_name + ' ' + s.first_name }, after); });
      $('#sAct', m).addEventListener('click', () => {
        if (!s.active) { rpc('crm_student_set_active', { p_id: id, p_active: true }).then(() => { toast('Учня активовано'); openStudent(id, after); }).catch((e) => toast(e.message, true)); return; }
        onModalClose = null;
        confirmBox('Деактивувати учня?', 'Учня з історією занять не видаляють: база зберігає його відвідування й оплати. Після деактивації він зникне зі списку активних, але історія лишиться.',
          'Деактивувати', async () => { await rpc('crm_student_set_active', { p_id: id, p_active: false }); toast('Учня деактивовано'); if (after) after(); });
      });
    };
    draw();
  }

  // ---------- форми ----------
  function formModal(title, body, submitText, onSubmit, after) {
    const m = openModal(`${mTitle(title)}<form id="frm">${body}<div class="login-error" hidden id="fErr">${icon('alert', 15)}<span></span></div>
      <div class="modal-actions"><button type="button" class="studio-btn" data-close>Відмінити</button><button class="studio-btn primary">${esc(submitText)}</button></div></form>`, '', after);
    $('#frm', m).addEventListener('submit', async (ev) => {
      ev.preventDefault(); const er = $('#fErr', m); er.hidden = true; const btn = $('button.primary', m); btn.disabled = true;
      try { await onSubmit(ev.target); } catch (e) { $('span', er).textContent = e.message; er.hidden = false; } finally { btn.disabled = false; }
    });
    return m;
  }
  function studentForm(d, after) {
    const s = d ? d.student : {}; const p = d && d.parents[0] ? d.parents[0] : {};
    formModal(d ? 'Змінити дані учня' : 'Новий учень', `
      <div class="field-row"><div class="field"><label class="field-label">Прізвище *</label><input type="text" name="last" required value="${esc(s.last_name)}"></div>
        <div class="field"><label class="field-label">Ім’я *</label><input type="text" name="first" required value="${esc(s.first_name)}"></div></div>
      <div class="field-row"><div class="field"><label class="field-label">Телефон учня</label><input type="tel" name="phone" value="${esc(s.phone)}"></div>
        <div class="field"><label class="field-label">Дата народження</label><input type="date" name="birthday" value="${esc(s.birthday || '')}"></div></div>
      <div class="field"><label class="field-label">Нотатки</label><input type="text" name="notes" value="${esc(s.notes)}"></div>
      <div class="modal-divider"></div>
      <div class="field-row"><div class="field"><label class="field-label">Прізвище батьків</label><input type="text" name="plast" value="${esc(p.last_name)}"></div>
        <div class="field"><label class="field-label">Ім’я батьків</label><input type="text" name="pfirst" value="${esc(p.first_name)}"></div></div>
      <div class="field-row"><div class="field"><label class="field-label">Телефон батьків</label><input type="tel" name="pphone" value="${esc(p.phone)}" placeholder="380501234567"></div>
        <div class="field"><label class="field-label">Хто</label><select name="rel">${[['parent', 'Батьки'], ['mother', 'Мати'], ['father', 'Батько'], ['guardian', 'Опікун']].map(([k, t]) =>
          `<option value="${k}" ${p.relation === k ? 'selected' : ''}>${t}</option>`).join('')}</select></div></div>
      <div class="hint">Якщо батьки з таким телефоном уже є в базі, учня буде прив’язано до них — без дубля.</div>`,
    'Зберегти', async (f) => {
      const id = await rpc('crm_student_save', { p_id: s.student_id || null, p_last_name: f.last.value, p_first_name: f.first.value, p_phone: f.phone.value || null,
        p_birthday: f.birthday.value || null, p_notes: f.notes.value || null, p_parent_last_name: f.plast.value || null, p_parent_first_name: f.pfirst.value || null,
        p_parent_phone: f.pphone.value || null, p_relation: f.rel.value });
      toast('Учня збережено'); onModalClose = null; openStudent(id, after);
    }, after);
  }
  function lessonForm(L, after) {
    const picked = [];
    const m = formModal(L ? 'Змінити заняття' : 'Нове заняття', `
      <div class="field"><label class="field-label">Курс *</label><select name="course">${courseOpts(L ? L.course_id : '')}</select></div>
      <div class="field"><label class="field-label">Викладач *</label><select name="teacher">${teacherOpts(L ? L.teacher_id : '')}</select></div>
      <div class="field-row"><div class="field"><label class="field-label">Дата *</label><input type="date" name="date" required value="${L ? L.date : today()}"></div>
        <div class="field"><label class="field-label">Час</label><input type="time" name="time" value="${L ? L.time : '16:00'}"></div>
        <div class="field"><label class="field-label">Хвилин</label><input type="number" name="dur" min="15" max="240" value="${L ? L.duration : 60}"></div></div>
      <div class="field"><label class="field-label">Формат</label><div class="studio-segmented format-segmented" id="fmt">${Object.entries(FORMAT).map(([k, t]) =>
        `<button type="button" data-f="${k}" class="${(L ? L.format : 'group') === k ? 'active' : ''}">${t}</button>`).join('')}</div></div>
      <div class="field"><label class="field-label">Тема</label><input type="text" name="theme" value="${esc(L ? L.theme : '')}"></div>
      ${L ? '<div class="hint">Поки на занятті немає відміток, ціна й оплата викладача перераховуються за тарифом.</div>' :
        '<div class="field"><label class="field-label">Учні</label><div id="lp"></div><div class="chip-wrap" id="ll" style="margin-top:8px"></div></div><div class="hint">Ціна заняття й оплата викладача беруться з тарифу курсу.</div>'}`,
    L ? 'Зберегти' : 'Створити', async (f) => {
      const fmt = $('#fmt .active', m).dataset.f;
      const args = { p_course: +f.course.value, p_teacher: f.teacher.value, p_date: f.date.value, p_time: f.time.value || null, p_duration: +f.dur.value || 60, p_format: fmt, p_theme: f.theme.value };
      let id = L && L.lesson_id;
      if (L) { await rpc('crm_lesson_update', Object.assign({ p_id: id }, args)); toast('Заняття змінено'); }
      else { id = await rpc('crm_lesson_create', Object.assign({ p_students: picked.map((r) => r.student_id) }, args)); toast('Заняття створено'); }
      onModalClose = null; openLesson(id, after);
    }, after);
    $$('#fmt [data-f]', m).forEach((b) => b.addEventListener('click', () => { $$('#fmt [data-f]', m).forEach((x) => x.classList.remove('active')); b.classList.add('active'); }));
    if (!L) {
      const draw = () => { $('#ll', m).innerHTML = picked.map((r) => `<span class="chip selected">${esc(r.student)}</span>`).join('') || '<span class="hint">поки нікого</span>'; };
      picker($('#lp', m), (r) => { if (!picked.some((x) => x.student_id === r.student_id)) picked.push(r); draw(); }); draw();
    }
  }
  function subForm(student, after) {
    let chosen = student;
    const m = formModal('Продаж абонемента', `
      <div class="field"><label class="field-label">Учень *</label><div id="sp">${student ? `<div class="static-field-value">${esc(student.student)}</div>` : ''}</div></div>
      <div class="field"><label class="field-label">Курс *</label><select name="course">${courseOpts('')}</select></div>
      <div class="field-row"><div class="field"><label class="field-label">Занять</label><input type="number" name="n" min="1" max="50" value="4"></div>
        <div class="field"><label class="field-label">Ціна, грн</label><input type="number" name="price" min="0" step="10" placeholder="за тарифом"></div></div>
      <div class="field"><label class="field-label">Оплата</label><div class="studio-segmented" id="pm"><button type="button" data-p="card" class="active">Картка</button><button type="button" data-p="cash">Готівка</button></div></div>`,
    'Продати', async (f) => {
      if (!chosen) throw new Error('Оберіть учня');
      await rpc('crm_subscription_sell', { p_student: chosen.student_id, p_course: +f.course.value, p_lessons: +f.n.value || 4,
        p_price: f.price.value === '' ? null : +f.price.value, p_payment: $('#pm .active', m).dataset.p });
      toast('Абонемент продано'); onModalClose = null; openStudent(chosen.student_id, after);
    }, after);
    $$('#pm [data-p]', m).forEach((b) => b.addEventListener('click', () => { $$('#pm [data-p]', m).forEach((x) => x.classList.remove('active')); b.classList.add('active'); }));
    if (!student) picker($('#sp', m), (r) => { chosen = r; });
  }

  // ---------------- глобальні дії ----------------
  document.addEventListener('click', (e) => {
    const a = e.target.closest('[data-act]'); if (!a) return;
    if (a.dataset.act === 'theme') toggleTheme();
    if (a.dataset.act === 'logout') logout();
  });

  if (session) start().catch(() => logout()); else renderLogin();
})();
