// Стемік CRM (демоверсія) — робоче місце адміністратора.
// Звертається до Supabase лише через REST API:
//   POST /auth/v1/token          — вхід працівника (Supabase Auth)
//   POST /rest/v1/rpc/crm_<fn>   — функції бази з файлу sql/04_crm_api.sql
(() => {
  'use strict';
  const cfg = window.CRM_CONFIG || {};
  const $ = (s, el = document) => el.querySelector(s);
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  // ---------------- сховище сесії (може бути недоступне) ----------------
  const store = {
    get(k) { try { return JSON.parse(sessionStorage.getItem(k)); } catch (e) { return null; } },
    set(k, v) { try { sessionStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* без збереження */ } },
    del(k) { try { sessionStorage.removeItem(k); } catch (e) { /* немає */ } },
  };
  let session = store.get('crm_session'); // { access_token, refresh_token, expires_at, email }
  let refs = null;

  // ---------------- форматування ----------------
  const DAYS = ['нд', 'пн', 'вт', 'ср', 'чт', 'пт', 'сб'];
  const iso = (d) => new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
  const today = () => iso(new Date());
  const addDays = (s, n) => { const d = new Date(s + 'T12:00:00'); d.setDate(d.getDate() + n); return iso(d); };
  const monday = (s) => { const d = new Date(s + 'T12:00:00'); return addDays(s, -((d.getDay() + 6) % 7)); };
  const fd = (s) => s ? `${s.slice(8, 10)}.${s.slice(5, 7)}.${s.slice(0, 4)}` : '—';
  const fdw = (s) => s ? `${DAYS[new Date(s + 'T12:00:00').getDay()]}, ${fd(s)}` : '—';
  const money = (v) => v === null || v === undefined ? '—' : Number(v).toLocaleString('uk-UA', { maximumFractionDigits: 2 }) + ' грн';
  const FORMAT = { group: 'група', group_online: 'група онлайн', individual: 'індивідуально', individual_online: 'індив. онлайн' };
  const STATUS = { present: ['був', 'ok'], absent: ['відсутній', 'bad'], excused: ['поважна', 'warn'] };
  const PAY = { card: 'картка', cash: 'готівка', subscription: 'абонемент', certificate: 'сертифікат' };
  const SUBST = { active: ['активний', 'ok'], completed: ['використаний', ''], cancelled: ['скасований', 'bad'] };
  const tag = (txt, cls = '') => `<span class="tag ${cls}">${esc(txt)}</span>`;
  const statusTag = (s, pay) => !s ? tag('не відмічено', 'blue')
    : s === 'present' && !pay ? tag('був · борг', 'bad') : tag(STATUS[s][0] + (pay ? ' · ' + (PAY[pay] || pay) : ''), STATUS[s][1]);

  function toast(msg, bad) {
    const t = $('#toast'); t.textContent = msg; t.className = 'toast' + (bad ? ' bad' : ''); t.hidden = false;
    clearTimeout(toast.t); toast.t = setTimeout(() => { t.hidden = true; }, bad ? 6000 : 2600);
  }

  // ---------------- звернення до Supabase ----------------
  const base = () => (cfg.url || '').replace(/\/+$/, '');
  const isJwt = (k) => /^eyJ/.test(k || '');
  function headers(useUser) {
    const h = { apikey: cfg.anonKey, 'Content-Type': 'application/json' };
    if (useUser && session) h.Authorization = 'Bearer ' + session.access_token;
    else if (isJwt(cfg.anonKey)) h.Authorization = 'Bearer ' + cfg.anonKey; // старий формат ключа anon
    return h;
  }
  function checkConfig() {
    if (!cfg.url || !cfg.anonKey) throw new Error('Не заповнено config.js: вкажіть url і anonKey навчального проєкту Supabase (див. README).');
  }
  async function auth(body, grant) {
    checkConfig();
    const res = await fetch(`${base()}/auth/v1/token?grant_type=${grant}`, { method: 'POST', headers: headers(false), body: JSON.stringify(body) });
    const d = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(d.error_description || d.msg || d.message || 'Помилка входу (' + res.status + ')');
    session = { access_token: d.access_token, refresh_token: d.refresh_token,
                expires_at: Date.now() + (d.expires_in || 3600) * 1000, email: (d.user && d.user.email) || body.email };
    store.set('crm_session', session);
  }
  async function rpc(name, args, anon) {
    checkConfig();
    if (!anon && session && session.refresh_token && Date.now() > session.expires_at - 60000) {
      try { await auth({ refresh_token: session.refresh_token }, 'refresh_token'); } catch (e) { logout('Сесія завершилась — увійдіть знову.'); throw e; }
    }
    let res;
    try {
      res = await fetch(`${base()}/rest/v1/rpc/${name}`, { method: 'POST', headers: headers(!anon), body: JSON.stringify(args || {}) });
    } catch (e) { throw new Error('Немає зв’язку з Supabase: перевірте url у config.js та інтернет.'); }
    const text = await res.text();
    if (!res.ok) {
      let msg = text; try { const j = JSON.parse(text); msg = j.message || j.msg || text; } catch (e) { /* не JSON */ }
      if ((res.status === 401 || res.status === 403) && !anon && session) { logout('Сесія недійсна — увійдіть знову.'); }
      if (/Could not find the function/.test(msg)) msg = `Функцію ${name} не знайдено: виконайте sql/04_crm_api.sql у SQL Editor.`;
      throw new Error(msg);
    }
    return text ? JSON.parse(text) : null;
  }

  // ---------------- вхід і перевірка підключення ----------------
  async function ping() {
    const dot = $('#pingDot'), txt = $('#pingText');
    dot.className = 'dot'; txt.textContent = 'Перевіряю підключення…';
    try {
      const t0 = performance.now();
      const p = await rpc('crm_ping', {}, true);
      const ms = Math.round(performance.now() - t0);
      dot.className = 'dot ok';
      txt.innerHTML = `<b>Підключено</b> · відповідь за ${ms} мс<small>Сервер: ${esc(p.server_time)} · PostgreSQL ${esc(String(p.postgres).split(' ')[0])}</small>
        <small>Схема stemik: ${p.tables} таблиць · ${p.rows.students} учнів · ${p.rows.lessons} занять · ${p.rows.attendance} відміток · ${p.rows.subscriptions} абонементів</small>`;
    } catch (e) {
      dot.className = 'dot bad';
      txt.innerHTML = `<b>Немає підключення</b><small>${esc(e.message)}</small>`;
    }
  }
  function logout(msg) {
    session = null; store.del('crm_session'); refs = null;
    $('#app').hidden = true; $('#login').hidden = false; closeDrawer();
    if (msg) { const er = $('#loginErr'); er.textContent = msg; er.hidden = false; }
    ping();
  }
  $('#pingBtn').addEventListener('click', ping);
  $('#logout').addEventListener('click', () => logout());
  $('#loginForm').addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const btn = ev.submitter || $('#loginForm button[type=submit]'); const er = $('#loginErr');
    er.hidden = true; btn.disabled = true;
    try {
      await auth({ email: $('#email').value.trim(), password: $('#password').value }, 'password');
      $('#password').value = '';
      await start();
    } catch (e) { er.textContent = e.message === 'Invalid login credentials' ? 'Невірний e-mail або пароль' : e.message; er.hidden = false; }
    finally { btn.disabled = false; }
  });

  async function start() {
    refs = await rpc('crm_refs');
    $('#me').textContent = (session.email || '') + (refs.me ? ' · дії від імені: ' + refs.me.name : '');
    $('#login').hidden = true; $('#app').hidden = false;
    go(location.hash.slice(1) || 'home');
  }

  // ---------------- навігація ----------------
  const VIEWS = { home: viewHome, students: viewStudents, schedule: viewSchedule, subs: viewSubs, debtors: viewDebtors };
  function go(name) {
    if (!VIEWS[name]) name = 'home';
    document.querySelectorAll('#nav button').forEach((b) => b.classList.toggle('on', b.dataset.view === name));
    try { history.replaceState(null, '', '#' + name); } catch (e) { /* file:// */ }
    VIEWS[name]();
  }
  $('#nav').addEventListener('click', (ev) => { const b = ev.target.closest('button'); if (b) go(b.dataset.view); });

  const loading = (el) => { el.innerHTML = '<div class="empty">Завантаження…</div>'; };
  const failed = (el, e) => { el.innerHTML = `<div class="err">${esc(e.message)}</div>`; };
  const sqlBox = (n, fn) => `<details class="sql"><summary>Пошуковий запит ${n}: як він працює (SQL)</summary>
    <p class="muted" style="margin:8px 0">Сайт викликає функцію бази <code>${esc(fn)}</code>; нижче — той самий запит у вигляді для SQL Editor (файл <code>sql/05_search_queries.sql</code>).</p>
    <pre>${esc((window.SEARCH_SQL || {})[n] || '')}</pre></details>`;
  const courseOptions = (sel, all) => (all ? `<option value="">усі курси</option>` : '') +
    refs.courses.map((c) => `<option value="${c.id}" ${String(sel) === String(c.id) ? 'selected' : ''}>${esc(c.name)}</option>`).join('');
  const teacherOptions = (sel, all) => (all ? `<option value="">усі викладачі</option>` : '') +
    refs.teachers.map((t) => `<option value="${t.id}" ${sel === t.id ? 'selected' : ''}>${esc(t.name)}</option>`).join('');
  function table(cols, rows, onRow) {
    if (!rows.length) return '<div class="tbl"><div class="empty">Нічого не знайдено</div></div>';
    return `<div class="tbl"><table><tr>${cols.map((c) => `<th class="${c.n ? 'n' : ''}">${esc(c.h)}</th>`).join('')}</tr>
      ${rows.map((r, i) => `<tr class="${onRow ? 'click' : ''}" data-i="${i}">${cols.map((c) => `<td class="${c.n ? 'n' : ''}">${c.f(r)}</td>`).join('')}</tr>`).join('')}</table></div>`;
  }
  function bindRows(el, rows, onRow) {
    el.querySelectorAll('tr.click').forEach((tr) => tr.addEventListener('click', () => onRow(rows[+tr.dataset.i])));
  }

  // ---------------- Огляд дня ----------------
  async function viewHome(date) {
    const v = $('#view'); date = date || today();
    v.innerHTML = `<h1>Огляд дня</h1><p class="lead">Заняття на обраний день і стан студії. Натисніть заняття, щоб відкрити журнал відміток.</p>
      <div class="toolbar"><div><label>Дата</label><input type="date" id="hDate" value="${date}"></div>
      <div class="auto"><button class="btn ghost" id="hPrev">← день</button> <button class="btn ghost" id="hToday">сьогодні</button> <button class="btn ghost" id="hNext">день →</button></div></div>
      <div id="hBody"></div>`;
    $('#hDate').addEventListener('change', (e) => viewHome(e.target.value));
    $('#hPrev').addEventListener('click', () => viewHome(addDays(date, -1)));
    $('#hNext').addEventListener('click', () => viewHome(addDays(date, 1)));
    $('#hToday').addEventListener('click', () => viewHome(today()));
    const b = $('#hBody'); loading(b);
    try {
      const d = await rpc('crm_dashboard', { p_date: date }); const k = d.kpi;
      b.innerHTML = `<div class="kpis">
          <div class="kpi"><b>${d.lessons.length}</b><span>занять ${fdw(date)}</span></div>
          <div class="kpi"><b>${k.week_lessons}</b><span>занять цього тижня</span></div>
          <div class="kpi"><b>${k.students}</b><span>активних учнів</span></div>
          <div class="kpi"><b>${k.active_subscriptions}</b><span>активних абонементів, ${k.ending_subscriptions} закінчуються</span></div>
          <div class="kpi warn"><b>${k.unpaid_visits}</b><span>неоплачених відвідувань · ${money(k.unpaid_sum)}</span></div>
        </div><h3 style="margin:0 0 8px">Розклад на ${fdw(date)}</h3><div id="hTbl"></div>`;
      const cols = [
        { h: 'Час', f: (r) => `<b>${esc(r.time || '—')}</b>` }, { h: 'Курс', f: (r) => esc(r.course) },
        { h: 'Викладач', f: (r) => esc(r.substitute ? r.substitute + ' (заміна)' : r.teacher) }, { h: 'Формат', f: (r) => esc(FORMAT[r.format] || r.format) },
        { h: 'Записано', n: 1, f: (r) => r.enrolled }, { h: 'Відмічено', n: 1, f: (r) => r.marked },
        { h: 'Стан', f: (r) => r.completed ? tag('проведено', 'ok') : r.marked >= r.enrolled && r.enrolled ? tag('усі відмічені', 'blue') : tag('очікує відміток', 'warn') }];
      $('#hTbl').innerHTML = table(cols, d.lessons, true);
      bindRows($('#hTbl'), d.lessons, (r) => openLesson(r.lesson_id, () => viewHome(date)));
    } catch (e) { failed(b, e); }
  }

  // ---------------- Учні (пошуковий запит 1) ----------------
  function viewStudents() {
    const v = $('#view');
    v.innerHTML = `<h1>Учні</h1><p class="lead">Пошук за прізвищем чи ім’ям учня, ПІБ батьків або будь-якою частиною телефону.</p>
      ${sqlBox(1, 'crm_students(p_q, p_active_only)')}
      <div class="toolbar"><div class="grow"><label>Пошук</label><input id="sQ" placeholder="напр. 010, Учень 02, Батьки…" autocomplete="off"></div>
      <div><label class="check"><input type="checkbox" id="sAct" checked> лише активні</label></div>
      <div class="auto"><button class="btn" id="sNew">+ Новий учень</button></div></div>
      <div id="sBody"></div>`;
    let t;
    const run = async () => {
      const b = $('#sBody'); loading(b);
      try {
        const rows = await rpc('crm_students', { p_q: $('#sQ').value, p_active_only: $('#sAct').checked });
        b.innerHTML = `<p class="count">Знайдено: ${rows.length}</p>` + table([
          { h: 'Учень', f: (r) => `<b>${esc(r.student)}</b>${r.phone ? `<br><span class="muted">${esc(r.phone)}</span>` : ''}` },
          { h: 'Батьки', f: (r) => esc(r.parents || '—') }, { h: 'Курси (2 міс.)', f: (r) => esc(r.courses || '—') },
          { h: 'Активні абонементи', f: (r) => esc(r.subscriptions || '—') }, { h: 'Останній візит', f: (r) => fd(r.last_visit) },
          { h: 'Борг', n: 1, f: (r) => r.unpaid ? tag(r.unpaid + ' зан.', 'bad') : '' }], rows, true);
        bindRows(b, rows, (r) => openStudent(r.student_id));
      } catch (e) { failed(b, e); }
    };
    $('#sQ').addEventListener('input', () => { clearTimeout(t); t = setTimeout(run, 300); });
    $('#sAct').addEventListener('change', run);
    $('#sNew').addEventListener('click', () => studentForm(null, run));
    run(); $('#sQ').focus();
  }

  // ---------------- Розклад (пошуковий запит 2) ----------------
  function viewSchedule() {
    const v = $('#view'); const from = monday(today());
    v.innerHTML = `<h1>Розклад</h1><p class="lead">Заняття за період з фільтром за курсом і викладачем. Натисніть заняття, щоб відкрити журнал.</p>
      ${sqlBox(2, 'crm_lessons(p_from, p_to, p_course, p_teacher)')}
      <div class="toolbar"><div><label>З</label><input type="date" id="lFrom" value="${from}"></div>
      <div><label>По</label><input type="date" id="lTo" value="${addDays(from, 6)}"></div>
      <div class="grow"><label>Курс</label><select id="lCourse">${courseOptions('', true)}</select></div>
      <div class="grow"><label>Викладач</label><select id="lTeacher">${teacherOptions('', true)}</select></div>
      <div class="auto"><button class="btn ghost" id="lWeek">цей тиждень</button></div>
      <div class="auto"><button class="btn" id="lNew">+ Заняття</button></div></div><div id="lBody"></div>`;
    const run = async () => {
      const b = $('#lBody'); loading(b);
      try {
        const rows = await rpc('crm_lessons', { p_from: $('#lFrom').value, p_to: $('#lTo').value,
          p_course: $('#lCourse').value || null, p_teacher: $('#lTeacher').value || null });
        b.innerHTML = `<p class="count">Занять: ${rows.length} · записів учнів: ${rows.reduce((s, r) => s + r.enrolled, 0)}</p>` + table([
          { h: 'Дата', f: (r) => fdw(r.lesson_date) }, { h: 'Час', f: (r) => `<b>${esc(r.start_time || '—')}</b>` },
          { h: 'Курс', f: (r) => esc(r.course) + (r.theme ? `<br><span class="muted">${esc(r.theme)}</span>` : '') },
          { h: 'Викладач', f: (r) => esc(r.teacher) }, { h: 'Формат', f: (r) => esc(FORMAT[r.format] || r.format) },
          { h: 'Записано', n: 1, f: (r) => r.enrolled }, { h: 'Відмічено', n: 1, f: (r) => r.marked },
          { h: 'Стан', f: (r) => r.completed ? tag('проведено', 'ok') : r.lesson_date < today() ? tag('не закрито', 'warn') : tag('заплановано') }], rows, true);
        bindRows(b, rows, (r) => openLesson(r.lesson_id, run));
      } catch (e) { failed(b, e); }
    };
    ['lFrom', 'lTo', 'lCourse', 'lTeacher'].forEach((id) => $('#' + id).addEventListener('change', run));
    $('#lWeek').addEventListener('click', () => { $('#lFrom').value = from; $('#lTo').value = addDays(from, 6); run(); });
    $('#lNew').addEventListener('click', () => lessonForm(run));
    run();
  }

  // ---------------- Абонементи ----------------
  function viewSubs() {
    const v = $('#view');
    v.innerHTML = `<h1>Абонементи</h1><p class="lead">Стан абонементів з телефонами батьків — для нагадувань про продовження.</p>
      <div class="toolbar"><div><label>Статус</label><select id="aSt"><option value="active">активні</option><option value="completed">використані</option><option value="cancelled">скасовані</option><option value="">усі</option></select></div>
      <div class="auto"><button class="btn" id="aNew">+ Продати абонемент</button></div></div><div id="aBody"></div>`;
    const run = async () => {
      const b = $('#aBody'); loading(b);
      try {
        const rows = await rpc('crm_subscriptions', { p_status: $('#aSt').value });
        b.innerHTML = `<p class="count">Абонементів: ${rows.length}</p>` + table([
          { h: 'Учень', f: (r) => `<b>${esc(r.student)}</b>` }, { h: 'Курс', f: (r) => esc(r.course) },
          { h: 'Залишок', f: (r) => tag(`${r.remaining} з ${r.total}`, r.status === 'active' && r.remaining <= 1 ? 'warn' : '') },
          { h: 'Ціна', n: 1, f: (r) => money(r.price) }, { h: 'Куплено', f: (r) => fd(r.purchased_at) },
          { h: 'Останній візит', f: (r) => r.last_visit ? fd(r.last_visit) : '<span class="muted">не було</span>' },
          { h: 'Телефони батьків', f: (r) => esc(r.parent_phones || '—') },
          { h: 'Статус', f: (r) => tag(...(SUBST[r.status] || [r.status])) }], rows, true);
        bindRows(b, rows, (r) => openStudent(r.student_id));
      } catch (e) { failed(b, e); }
    };
    $('#aSt').addEventListener('change', run);
    $('#aNew').addEventListener('click', () => subForm(null, run));
    run();
  }

  // ---------------- Боржники (пошуковий запит 3) ----------------
  function viewDebtors() {
    const v = $('#view');
    v.innerHTML = `<h1>Боржники</h1><p class="lead">Учні, які були на заняттях без оплати, — з сумою боргу й телефонами батьків.</p>
      ${sqlBox(3, 'crm_debtors(p_min)')}
      <div class="toolbar"><div><label>Неоплачених занять, не менше</label><input type="number" id="dMin" min="1" value="1"></div></div><div id="dBody"></div>`;
    const run = async () => {
      const b = $('#dBody'); loading(b);
      try {
        const rows = await rpc('crm_debtors', { p_min: +$('#dMin').value || 1 });
        const sum = rows.reduce((s, r) => s + Number(r.debt), 0);
        b.innerHTML = `<p class="count">Боржників: ${rows.length} · загальний борг: <b>${money(sum)}</b></p>` + table([
          { h: 'Учень', f: (r) => `<b>${esc(r.student)}</b>` }, { h: 'Неоплачених', n: 1, f: (r) => r.unpaid_visits },
          { h: 'Борг', n: 1, f: (r) => `<b>${money(r.debt)}</b>` }, { h: 'Період', f: (r) => `${fd(r.first_unpaid)} – ${fd(r.last_unpaid)}` },
          { h: 'Курси', f: (r) => esc(r.courses) }, { h: 'Телефони батьків', f: (r) => esc(r.parent_phones || '—') }], rows, true);
        bindRows(b, rows, (r) => openStudent(r.student_id));
      } catch (e) { failed(b, e); }
    };
    $('#dMin').addEventListener('change', run);
    run();
  }

  // ---------------- бічна панель ----------------
  function openDrawer(html) { $('#drawer').innerHTML = `<button class="btn ghost sm close" id="dClose">✕ Закрити</button>` + html; $('#overlay').hidden = false; $('#dClose').addEventListener('click', closeDrawer); }
  function closeDrawer() { $('#overlay').hidden = true; $('#drawer').innerHTML = ''; }
  $('#overlay').addEventListener('click', (e) => { if (e.target.id === 'overlay') closeDrawer(); });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !$('#overlay').hidden) closeDrawer(); });

  // Вибір учня з пошуком (для запису на заняття й продажу абонемента)
  function picker(el, onPick) {
    el.innerHTML = `<div class="picker"><input placeholder="почніть вводити ім’я або телефон" autocomplete="off"><ul hidden></ul></div>`;
    const inp = $('input', el), ul = $('ul', el); let t;
    inp.addEventListener('input', () => {
      clearTimeout(t);
      t = setTimeout(async () => {
        if (inp.value.trim().length < 2) { ul.hidden = true; return; }
        const rows = (await rpc('crm_students', { p_q: inp.value, p_active_only: true })).slice(0, 10);
        ul.innerHTML = rows.map((r, i) => `<li data-i="${i}">${esc(r.student)} <span class="muted">${esc(r.parents || '')}</span></li>`).join('') || '<li class="muted">нічого не знайдено</li>';
        ul.hidden = false;
        ul.querySelectorAll('li[data-i]').forEach((li) => li.addEventListener('click', () => {
          const r = rows[+li.dataset.i]; inp.value = r.student; ul.hidden = true; onPick(r);
        }));
      }, 250);
    });
  }

  // ---------------- Журнал заняття ----------------
  async function openLesson(id, onChange) {
    openDrawer('<div class="empty">Завантаження журналу…</div>');
    let d;
    try { d = await rpc('crm_lesson', { p_id: id }); } catch (e) { failed($('#drawer'), e); return; }
    const L = d.lesson;
    const changed = () => { if (onChange) onChange(); };
    const marked = d.students.filter((s) => s.status).length;
    openDrawer(`<div class="eyebrow muted">Журнал заняття</div><h2>${esc(L.course)}</h2>
      <div class="facts"><div><small>Дата й час</small>${fdw(L.date)}, ${esc(L.time || '—')} · ${L.duration} хв</div>
        <div><small>Викладач</small>${esc(L.teacher)}</div><div><small>Формат</small>${esc(FORMAT[L.format] || L.format)}</div>
        <div><small>Тема</small>${esc(L.theme || '—')}</div><div><small>Ціна заняття</small>${money(L.price)}</div>
        <div><small>Відмічено</small>${marked} з ${d.students.length}</div></div>
      <h3>Учні та відмітки</h3>
      <p class="muted" style="margin:0 0 8px">Оберіть спосіб оплати, потім натисніть «був». «Абонемент» списує одне заняття; повторна відмітка спочатку повертає його.</p>
      <div class="tbl"><table class="roster"><tr><th>Учень</th><th>Абонемент на курс</th><th>Оплата</th><th>Відмітка</th><th>Стан</th></tr>
      ${d.students.map((s, i) => `<tr data-i="${i}"><td><a href="#" class="stu">${esc(s.student)}</a></td>
        <td>${s.subscription ? tag(s.subscription, 'blue') : '<span class="muted">немає</span>'}</td>
        <td><select class="pay"><option value="card">картка</option><option value="cash">готівка</option>
          <option value="subscription" ${s.subscription ? '' : 'disabled'}>абонемент</option><option value="">борг</option></select></td>
        <td><span class="seg">${['present', 'absent', 'excused'].map((st) => `<button type="button" data-st="${st}" class="${st} ${s.status === st ? 'on' : ''}">${STATUS[st][0]}</button>`).join('')}</span></td>
        <td class="state">${statusTag(s.status, s.payment)}${s.status === 'present' ? `<br><span class="muted">${money(s.amount)}</span>` : ''}</td></tr>`).join('')
        || '<tr><td colspan="5" class="empty">На заняття ще нікого не записано</td></tr>'}</table></div>
      <h3>Записати учня на заняття</h3><div id="addStu"></div>
      <p style="margin-top:18px"><label class="check"><input type="checkbox" id="lDone" ${L.completed ? 'checked' : ''}> Заняття проведено (закрито викладачем)</label></p>`);
    document.querySelectorAll('#drawer tr[data-i]').forEach((tr) => {
      const s = d.students[+tr.dataset.i]; const sel = $('select.pay', tr);
      sel.value = s.status === 'present' ? (s.payment || '') : (s.subscription ? 'subscription' : 'card');
      $('a.stu', tr).addEventListener('click', (e) => { e.preventDefault(); openStudent(s.student_id); });
      tr.querySelectorAll('.seg button').forEach((b) => b.addEventListener('click', async () => {
        tr.querySelectorAll('.seg button').forEach((x) => { x.disabled = true; });
        try {
          const r = await rpc('crm_mark', { p_lesson: L.lesson_id, p_student: s.student_id, p_status: b.dataset.st,
                                           p_payment: b.dataset.st === 'present' ? sel.value : null });
          changed();
          toast(`${s.student}: ${STATUS[r.status][0]}${r.status === 'present' ? ' · ' + (r.payment ? PAY[r.payment] : 'борг') + ' · ' + money(r.amount) : ''}${r.subscription ? ' · залишок ' + r.subscription : ''}`);
          openLesson(id, onChange);
        } catch (e) { toast(e.message, true); tr.querySelectorAll('.seg button').forEach((x) => { x.disabled = false; }); }
      }));
    });
    picker($('#addStu'), async (r) => {
      try { await rpc('crm_lesson_add_student', { p_lesson: L.lesson_id, p_student: r.student_id }); changed(); toast(r.student + ' записаний на заняття'); openLesson(id, onChange); }
      catch (e) { toast(e.message, true); }
    });
    $('#lDone').addEventListener('change', async (e) => {
      try { await rpc('crm_lesson_complete', { p_lesson: L.lesson_id, p_completed: e.target.checked }); changed(); toast(e.target.checked ? 'Заняття закрито' : 'Заняття знову відкрите'); }
      catch (er) { toast(er.message, true); e.target.checked = !e.target.checked; }
    });
  }

  // ---------------- Картка учня ----------------
  async function openStudent(id) {
    openDrawer('<div class="empty">Завантаження картки…</div>');
    let d;
    try { d = await rpc('crm_student', { p_id: id }); } catch (e) { failed($('#drawer'), e); return; }
    const s = d.student;
    openDrawer(`<div class="eyebrow muted">Картка учня</div><h2>${esc(s.last_name)} ${esc(s.first_name)} ${s.active ? '' : tag('неактивний', 'bad')}</h2>
      <div class="facts"><div><small>Телефон учня</small>${esc(s.phone || '—')}</div><div><small>Дата народження</small>${fd(s.birthday)}</div>
        <div><small>Нотатки</small>${esc(s.notes || '—')}</div></div>
      <p><button class="btn ghost sm" id="stEdit">Редагувати</button> <button class="btn sm" id="stSell">+ Продати абонемент</button></p>
      <h3>Батьки</h3>${d.parents.length ? d.parents.map((p) => `<div>${esc([p.last_name, p.first_name].filter(Boolean).join(' ') || 'без імені')} · <b>${esc(p.phone)}</b> <span class="muted">${esc(p.relation)}</span></div>`).join('') : '<p class="muted">не вказано</p>'}
      <h3>Абонементи</h3>${table([{ h: 'Курс', f: (r) => esc(r.course) }, { h: 'Залишок', f: (r) => `${r.remaining} з ${r.total}` },
        { h: 'Ціна', n: 1, f: (r) => money(r.price) }, { h: 'Куплено', f: (r) => fd(r.purchased_at) }, { h: 'Статус', f: (r) => tag(...(SUBST[r.status] || [r.status])) }], d.subscriptions)}
      <h3>Найближчі заняття</h3><div id="stUp">${table([{ h: 'Дата', f: (r) => fdw(r.date) }, { h: 'Час', f: (r) => esc(r.time || '—') }, { h: 'Курс', f: (r) => esc(r.course) }], d.upcoming, true)}</div>
      <h3>Останні відвідування</h3>${table([{ h: 'Дата', f: (r) => fd(r.date) }, { h: 'Курс', f: (r) => esc(r.course) },
        { h: 'Відмітка', f: (r) => statusTag(r.status, r.payment) }, { h: 'Сума', n: 1, f: (r) => r.status === 'present' ? money(r.amount) : '' }], d.visits)}
      ${d.comments.length ? '<h3>Коментарі</h3>' + d.comments.map((c) => `<p><span class="muted">${esc(c.created_at)}</span> ${esc(c.body)}</p>`).join('') : ''}`);
    bindRows($('#stUp'), d.upcoming, (r) => openLesson(r.lesson_id));
    $('#stEdit').addEventListener('click', () => studentForm(d, () => openStudent(id)));
    $('#stSell').addEventListener('click', () => subForm({ student_id: id, student: s.last_name + ' ' + s.first_name }, () => openStudent(id)));
  }

  // ---------------- Форми ----------------
  function studentForm(d, after) {
    const s = d ? d.student : {}; const p = d && d.parents[0] ? d.parents[0] : {};
    openDrawer(`<h2>${d ? 'Редагування учня' : 'Новий учень'}</h2><form id="fStu">
      <div class="row"><div><label>Прізвище *</label><input name="last" required value="${esc(s.last_name)}"></div><div><label>Ім’я *</label><input name="first" required value="${esc(s.first_name)}"></div></div>
      <div class="row"><div><label>Телефон учня</label><input name="phone" value="${esc(s.phone)}" placeholder="+380 …"></div><div><label>Дата народження</label><input type="date" name="birthday" value="${esc(s.birthday || '')}"></div></div>
      <label>Нотатки</label><textarea name="notes" rows="2">${esc(s.notes)}</textarea>
      <h3>Батьки ${d && d.parents.length ? '<span class="muted" style="font-weight:400">(новий номер додасть ще одного з батьків)</span>' : ''}</h3>
      <div class="row"><div><label>Прізвище</label><input name="plast" value="${esc(p.last_name)}"></div><div><label>Ім’я</label><input name="pfirst" value="${esc(p.first_name)}"></div></div>
      <div class="row"><div><label>Телефон батьків</label><input name="pphone" value="${esc(p.phone)}" placeholder="380501234567"></div>
        <div><label>Хто</label><select name="rel">${[['parent', 'батьки'], ['mother', 'мати'], ['father', 'батько'], ['guardian', 'опікун']].map(([v, t]) => `<option value="${v}" ${p.relation === v ? 'selected' : ''}>${t}</option>`).join('')}</select></div></div>
      <p style="margin-top:16px"><button class="btn">Зберегти</button></p><div class="err" hidden></div></form>`);
    $('#fStu').addEventListener('submit', async (ev) => {
      ev.preventDefault(); const f = ev.target; const er = $('.err', f); er.hidden = true;
      try {
        const id = await rpc('crm_student_save', { p_id: s.student_id || null, p_last_name: f.last.value, p_first_name: f.first.value,
          p_phone: f.phone.value || null, p_birthday: f.birthday.value || null, p_notes: f.notes.value || null,
          p_parent_last_name: f.plast.value || null, p_parent_first_name: f.pfirst.value || null, p_parent_phone: f.pphone.value || null, p_relation: f.rel.value });
        toast('Учня збережено'); if (after) after(); openStudent(id);
      } catch (e) { er.textContent = e.message; er.hidden = false; }
    });
  }

  function lessonForm(after) {
    const picked = [];
    openDrawer(`<h2>Нове заняття</h2><p class="muted">Ціна заняття й оплата викладача беруться з тарифу курсу для обраного формату.</p><form id="fLes">
      <div class="row"><div><label>Курс *</label><select name="course">${courseOptions('')}</select></div><div><label>Викладач *</label><select name="teacher">${teacherOptions('')}</select></div></div>
      <div class="row"><div><label>Дата *</label><input type="date" name="date" required value="${today()}"></div><div><label>Час</label><input type="time" name="time" value="16:00"></div>
        <div><label>Тривалість, хв</label><input type="number" name="dur" min="15" max="240" value="60"></div></div>
      <div class="row"><div><label>Формат</label><select name="format">${Object.entries(FORMAT).map(([k, t]) => `<option value="${k}">${t}</option>`).join('')}</select></div><div><label>Тема</label><input name="theme"></div></div>
      <label>Учні</label><div id="lesPick"></div><div id="lesList" style="margin-top:6px"></div>
      <p style="margin-top:16px"><button class="btn">Створити заняття</button></p><div class="err" hidden></div></form>`);
    const draw = () => { $('#lesList').innerHTML = picked.map((r) => tag(r.student, 'blue')).join(' ') || '<span class="muted">поки нікого</span>'; };
    picker($('#lesPick'), (r) => { if (!picked.some((x) => x.student_id === r.student_id)) picked.push(r); draw(); }); draw();
    $('#fLes').addEventListener('submit', async (ev) => {
      ev.preventDefault(); const f = ev.target; const er = $('.err', f); er.hidden = true;
      try {
        const id = await rpc('crm_lesson_create', { p_course: +f.course.value, p_teacher: f.teacher.value, p_date: f.date.value, p_time: f.time.value || null,
          p_duration: +f.dur.value || 60, p_format: f.format.value, p_theme: f.theme.value, p_students: picked.map((r) => r.student_id) });
        toast('Заняття створено'); if (after) after(); openLesson(id, after);
      } catch (e) { er.textContent = e.message; er.hidden = false; }
    });
  }

  function subForm(student, after) {
    let chosen = student;
    openDrawer(`<h2>Продаж абонемента</h2><form id="fSub">
      <label>Учень *</label><div id="subPick">${student ? `<b>${esc(student.student)}</b>` : ''}</div>
      <div class="row"><div><label>Курс *</label><select name="course">${courseOptions('')}</select></div><div><label>Занять</label><input type="number" name="n" min="1" max="50" value="4"></div></div>
      <div class="row"><div><label>Ціна, грн</label><input type="number" name="price" min="0" step="10" placeholder="за тарифом курсу"></div>
        <div><label>Оплата</label><select name="pay"><option value="card">картка</option><option value="cash">готівка</option></select></div></div>
      <p style="margin-top:16px"><button class="btn">Продати</button></p><div class="err" hidden></div></form>`);
    if (!student) picker($('#subPick'), (r) => { chosen = r; });
    $('#fSub').addEventListener('submit', async (ev) => {
      ev.preventDefault(); const f = ev.target; const er = $('.err', f); er.hidden = true;
      try {
        if (!chosen) throw new Error('Оберіть учня');
        await rpc('crm_subscription_sell', { p_student: chosen.student_id, p_course: +f.course.value, p_lessons: +f.n.value || 4,
          p_price: f.price.value === '' ? null : +f.price.value, p_payment: f.pay.value });
        toast('Абонемент продано'); if (after) after(); openStudent(chosen.student_id);
      } catch (e) { er.textContent = e.message; er.hidden = false; }
    });
  }

  // ---------------- старт ----------------
  ping();
  if (session) start().catch(() => logout());
})();
