// Стемік · сайт бази даних STEM-студії.
// Сайт розвивається поетапно: config.js → stage вмикає розділи (див. SECTIONS).
// Дані читаються з Supabase через REST API: POST /rest/v1/rpc/<функція>.
(() => {
  'use strict';
  const cfg = window.STEMIK_CONFIG || {};
  const STAGE = Number(cfg.stage) || 1;
  const $ = (s, el = document) => el.querySelector(s);
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const tag = (t, cls = '') => `<span class="tag ${cls}">${esc(t)}</span>`;
  const num = (n) => Number(n || 0).toLocaleString('uk-UA');

  // ---------------- підключення до бази ----------------
  const cache = {};
  async function rpc(name, args) {
    if (!cfg.url || !cfg.anonKey) throw new Error('Не задано підключення до бази: заповніть url і anonKey у config.js.');
    const res = await fetch(cfg.url.replace(/\/+$/, '') + '/rest/v1/rpc/' + name, {
      method: 'POST',
      headers: Object.assign({ apikey: cfg.anonKey, 'Content-Type': 'application/json' },
        /^eyJ/.test(cfg.anonKey) ? { Authorization: 'Bearer ' + cfg.anonKey } : {}),
      body: JSON.stringify(args || {}),
    }).catch(() => { throw new Error('Немає зв’язку з базою даних (перевірте url і інтернет).'); });
    const text = await res.text();
    if (!res.ok) {
      let msg = text; try { msg = JSON.parse(text).message || text; } catch (e) { /* не JSON */ }
      if (/Could not find the function/.test(msg)) msg = `У базі ще немає функції ${name}: виконайте SQL цього етапу в Supabase.`;
      throw new Error(msg);
    }
    setConn(true);
    return text ? JSON.parse(text) : null;
  }
  const once = (name) => (cache[name] = cache[name] || rpc(name).catch((e) => { delete cache[name]; throw e; }));
  function setConn(ok, msg) {
    $('#connDot').className = 'dot ' + (ok ? 'ok' : 'bad');
    $('#connText').textContent = ok ? 'база підключена' : (msg || 'немає підключення');
  }
  const status = (el, err) => { el.className = 'status' + (err ? ' err' : ''); el.textContent = err ? (err.message || String(err)) : 'Завантаження з бази…'; if (err) setConn(false); };

  // ---------------- довідкові описи сутностей ----------------
  const GROUPS = [
    ['Довідники', ['course', 'tariff', 'studio_settings']],
    ['Люди', ['employee', 'student', 'parent', 'parent_student', 'student_comment']],
    ['Розклад і облік', ['lesson', 'lesson_student', 'attendance', 'subscription']],
    ['3D-друк', ['printer', 'filament', 'work', 'work_cost']],
    ['Кабінет батьків', ['parent_credential', 'parent_session']],
  ];
  const DESC = {
    course: ['Курс', 'Напрям навчання (3D, VR, робототехніка) і вікова група.'],
    tariff: ['Тариф', 'Ціна заняття й абонемента та оплата викладача для пари «курс × формат заняття».'],
    studio_settings: ['Налаштування студії', 'Єдиний рядок параметрів: тариф на електроенергію, відсоток відходів пластику.'],
    employee: ['Працівник', 'Викладач, адміністратор або керівник студії.'],
    student: ['Учень', 'Дитина, яка навчається в студії.'],
    parent: ['Батьки', 'Контактна особа учня; вхід у кабінет за номером телефону.'],
    parent_student: ['Батьки — учень', 'Зв’язок «багато-до-багатьох»: у сім’ї кілька дітей, у дитини двоє батьків.'],
    student_comment: ['Коментар', 'Нотатка працівника про учня.'],
    lesson: ['Заняття', 'Конкретне заняття курсу: дата, час, викладач, формат, тема.'],
    lesson_student: ['Запис на заняття', 'Зв’язок «багато-до-багатьох»: хто з учнів записаний на заняття.'],
    attendance: ['Відвідування', 'Відмітка присутності учня на занятті та оплата.'],
    subscription: ['Абонемент', 'Пакет занять учня на курс і залишок занять.'],
    printer: ['3D-принтер', 'Обладнання для друку: потужність, амортизація.'],
    filament: ['Пластик', 'Матеріал і колір філаменту, ціна за кілограм.'],
    work: ['Робота учня', 'Модель, створена учнем на занятті, і дані про її друк.'],
    work_cost: ['Собівартість друку', 'Розрахунок вартості пластику, електроенергії й амортизації для роботи.'],
    parent_credential: ['Облікові дані батьків', 'Хеш пароля й блокування після невдалих спроб входу.'],
    parent_session: ['Сесія входу', 'Активні входи батьків у кабінет.'],
  };
  const title = (t) => (DESC[t] ? DESC[t][0] : t);

  // ---------------- розділи сайту за етапами ----------------
  const SECTIONS = [
    { id: 'home', title: 'Огляд', stage: 1, render: viewHome },
    { id: 'domain', title: 'Предметна область', stage: 1, render: viewDomain },
    { id: 'model', title: 'Модель даних', stage: 2, render: viewModel },
    { id: 'tables', title: 'Таблиці', stage: 2, render: viewTables },
    { id: 'integrity', title: 'Цілісність', stage: 2, render: viewIntegrity },
    { id: 'ddl', title: 'DDL-скрипт', stage: 2, render: viewDDL },
  ].filter((s) => s.stage <= STAGE);

  $('#nav').innerHTML = SECTIONS.map((s) => `<a href="#${s.id}" data-id="${s.id}">${esc(s.title)}</a>`).join('');
  function route() {
    const [id, arg] = decodeURIComponent(location.hash.slice(1)).split('/');
    const sec = SECTIONS.find((s) => s.id === id) || SECTIONS[0];
    document.querySelectorAll('#nav a').forEach((a) => a.classList.toggle('on', a.dataset.id === sec.id));
    sec.render($('#view'), arg);
    if (!arg) window.scrollTo(0, 0);
  }
  window.addEventListener('hashchange', route);

  // перегляд діаграми на весь екран
  document.addEventListener('click', (e) => {
    const img = e.target.closest('figure.diagram img');
    if (img) { $('#zoomImg').src = img.src; $('#zoom').hidden = false; }
  });
  $('#zoom').addEventListener('click', () => { $('#zoom').hidden = true; });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') $('#zoom').hidden = true; });

  // ======================= ОГЛЯД =======================
  function viewHome(v) {
    const cards = [
      ['domain', 'Предметна область', 'Чим займається студія, які сутності й зв’язки описує база, ER-діаграма та аналіз поточних даних.'],
      ['model', 'Модель даних', 'Фізична схема бази: таблиці, зв’язки, розрив «багато-до-багатьох», правила каскадних дій.'],
      ['tables', 'Таблиці', 'Кожна таблиця: стовпці й типи даних, ключі, NOT NULL, DEFAULT, UNIQUE і CHECK.'],
      ['integrity', 'Цілісність', 'Усі обмеження бази та їх перевірка наживо: що база не дозволить зберегти.'],
      ['ddl', 'DDL-скрипт', 'SQL-скрипт створення бази — повністю або для окремої таблиці.'],
    ].filter(([id]) => SECTIONS.some((s) => s.id === id));
    v.innerHTML = `<div class="eyebrow">STEM-студія «Стемік»</div>
      <h1>База даних студії</h1>
      <p class="lead">Студія навчає дітей 6–14 років 3D-моделюванню, робототехніці та створенню VR-світів. База даних зберігає курси й тарифи, учнів і батьків, розклад занять, відвідування й оплату, абонементи та 3D-друк робіт учнів.</p>
      <div class="grid" id="kpi"></div>
      <h2>Розділи</h2>
      <div class="grid">${cards.map(([id, t, d]) => `<a class="card" href="#${id}"><h3>${esc(t)}</h3><p>${esc(d)}</p></a>`).join('')}</div>`;
    const k = $('#kpi');
    const fill = (items) => { k.innerHTML = items.map(([n, t, w]) => `<div class="card kpi ${w ? 'warn' : ''}"><b>${n}</b><span>${esc(t)}</span></div>`).join(''); };
    if (STAGE >= 2) {
      once('site_model').then((m) => fill([
        [m.counts.tables, 'таблиць у базі'], [m.counts.pk, 'первинних ключів'], [m.counts.fk, 'зовнішніх ключів'],
        [m.counts.unique + m.counts.check, 'обмежень UNIQUE і CHECK'], [num(m.counts.rows), 'рядків тестових даних']]))
        .catch((e) => { k.innerHTML = '<div class="status"></div>'; status(k.firstChild, e); });
    } else {
      once('site_current_db').then((o) => fill([
        [o.objects.tables, 'таблиць у поточній базі'], [o.objects.views, 'представлень'], [o.objects.functions, 'функцій'],
        [o.anomalies.student_ids_orphan, 'посилань на неіснуючих учнів', true]]))
        .catch((e) => { k.innerHTML = '<div class="status"></div>'; status(k.firstChild, e); });
    }
  }

  // ======================= ПРЕДМЕТНА ОБЛАСТЬ =======================
  function viewDomain(v) {
    v.innerHTML = `<div class="eyebrow">Предметна область</div>
      <h1>Що описує база даних</h1>
      <p class="lead">Адміністратор складає розклад і записує дітей на заняття, викладач відмічає присутність, батьки платять разово або купують абонемент, а роботи учнів друкуються на 3D-принтері. Кожна з цих дій — запис у базі.</p>
      <div class="grid">
        <div class="card"><h3>Адміністратор</h3><p>розклад, запис учнів, оплата, абонементи, борги</p></div>
        <div class="card"><h3>Викладач</h3><p>свої заняття, відмітки присутності, роботи учнів</p></div>
        <div class="card"><h3>Батьки</h3><p>кабінет: відвідування дитини, залишок абонемента</p></div>
        <div class="card"><h3>Керівник</h3><p>тарифи, оплата викладачів, аналітика студії</p></div>
      </div>
      <h2>ER-діаграма</h2>
      <p class="muted">Сутності, атрибути й зв’язки з кардинальністю (нотація «вороняча лапка»). Натисніть, щоб збільшити.</p>
      <figure class="diagram"><img src="img/er.png" alt="ER-діаграма бази даних студії"><figcaption>18 сутностей: довідники, люди, розклад і облік, 3D-друк, кабінет батьків.</figcaption></figure>
      <h2>Сутності</h2>
      ${GROUPS.map(([g, list]) => `<h3>${esc(g)}</h3><div class="grid">${list.map((t) => `<div class="card"><h3>${esc(DESC[t][0])} <code class="muted">${t}</code></h3><p>${esc(DESC[t][1])}</p></div>`).join('')}</div>`).join('')}
      <h2>Аналіз поточної бази</h2>
      <p class="lead">Студія вже працює з базою, яка зростала разом із застосунком. Аналіз її структури й даних показав, що саме має виправити нова модель.</p>
      <div id="audit" class="status">Завантаження з бази…</div>`;
    const box = $('#audit');
    once('site_current_db').then((o) => {
      const a = o.anomalies;
      box.className = '';
      box.innerHTML = `<div class="grid">
          <div class="card kpi"><b>${o.objects.tables}</b><span>таблиць, ${o.objects.views} представлень, ${o.objects.functions} функцій, ${o.objects.triggers} тригерів</span></div>
          <div class="card kpi warn"><b>${a.student_ids_orphan}</b><span>з ${num(a.student_ids_total)} id учнів у розкладі посилаються на неіснуючих учнів — у масиві немає зовнішнього ключа</span></div>
          <div class="card kpi warn"><b>${a.course_spellings.length} → ${a.courses_in_rate_cards}</b><span>написань назв курсів замість довідника з ${a.courses_in_rate_cards} курсів</span></div>
          <div class="card kpi warn"><b>${a.rate_cards_columns}</b><span>стовпців цін в одній таблиці тарифів — повторювана група</span></div>
          <div class="card kpi warn"><b>${a.students_with_parent_names}</b><span>карток учнів зберігають ім’я батьків текстом</span></div>
          <div class="card kpi warn"><b>${a.attendance_not_in_lesson}</b><span>відмітка учня, якого немає в списку заняття</span></div>
        </div>
        <h3>Таблиці поточної бази</h3>
        <div class="tbl"><table><tr><th>Таблиця</th><th class="n">Рядків</th><th class="n">Стовпців</th><th class="n">Зовнішніх ключів</th><th>Захист рядків (RLS)</th></tr>
          ${o.tables.map((t) => `<tr><td><code>${esc(t.name)}</code></td><td class="n">${num(t.rows)}</td><td class="n">${t.columns}</td><td class="n">${t.fks}</td><td>${t.rls ? tag('увімкнено', 'ok') : tag('ні', 'bad')}</td></tr>`).join('')}</table></div>
        <h3>Як записано назви курсів</h3>
        <div class="tbl"><table><tr><th>Назва в розкладі</th><th class="n">Занять</th></tr>
          ${a.course_spellings.map((c) => `<tr><td>${esc(c.course)}</td><td class="n">${c.rows}</td></tr>`).join('')}</table></div>`;
    }).catch((e) => status(box, e));
  }

  // ======================= МОДЕЛЬ ДАНИХ =======================
  // асоціативні таблиці: первинний ключ із ≥ 2 стовпців, і всі вони — зовнішні ключі
  function associative(m) {
    return m.tables.filter((t) => {
      const pk = t.columns.filter((c) => (c.keys || '').includes('PK'));
      return pk.length >= 2 && pk.every((c) => (c.keys || '').includes('FK'));
    }).map((t) => ({ table: t.name, parents: m.foreign_keys.filter((f) => f.child === t.name).map((f) => f.parent) }));
  }
  function cardinality(m, fk) {
    const t = m.tables.find((x) => x.name === fk.child); const cols = fk.columns.split(', ');
    const pk = t.columns.filter((c) => (c.keys || '').includes('PK')).map((c) => c.name);
    const one = pk.length === cols.length && cols.every((c) => pk.includes(c));
    return one ? '1 : 1' : '1 : N';
  }
  const ruleCls = (r) => ({ CASCADE: 'c', RESTRICT: 'r', 'SET NULL': 'n' }[r] || '');

  function viewModel(v) {
    v.innerHTML = `<div class="eyebrow">Модель даних</div><h1>Фізична схема бази</h1>
      <p class="lead">Кожна сутність предметної області стала таблицею з типами даних, первинним ключем і зовнішніми ключами. Нижче все читається наживо із системного каталогу бази.</p>
      <figure class="diagram"><img src="img/model.png" alt="Фізична схема бази даних"><figcaption>Таблиці, типи стовпців, PK / FK / UK, зв’язки (підписи — стовпці зовнішніх ключів). Натисніть, щоб збільшити.</figcaption></figure>
      <div id="mbody" class="status" style="margin-top:18px">Завантаження з бази…</div>`;
    const box = $('#mbody');
    once('site_model').then((m) => {
      const mn = associative(m);
      box.className = '';
      box.innerHTML = `
        <h2>Зв’язки «багато-до-багатьох»</h2>
        <p>Зв’язок M:N реляційна модель напряму не зберігає, тому кожен такий зв’язок розірвано асоціативною таблицею: її первинний ключ складається з двох зовнішніх ключів, і вона дає два зв’язки «один-до-багатьох».</p>
        <div class="grid">${mn.map((x) => `<div class="card"><h3>${esc(title(x.parents[0]))} ↔ ${esc(title(x.parents[1]))}</h3>
          <p><code>${esc(x.parents[0])}</code> 1 : N <b><code>${esc(x.table)}</code></b> N : 1 <code>${esc(x.parents[1])}</code></p><p class="muted">${esc(DESC[x.table] ? DESC[x.table][1] : '')}</p></div>`).join('')}</div>
        <h2>Усі зв’язки (${m.foreign_keys.length})</h2>
        <p class="muted">Таблиця, що посилається → таблиця, на яку посилаються; правило при видаленні: <span class="rule c">CASCADE</span> — видалити залежні рядки, <span class="rule r">RESTRICT</span> — заборонити, <span class="rule n">SET NULL</span> — очистити посилання.</p>
        <div class="tbl"><table><tr><th>Таблиця</th><th>Стовпці</th><th></th><th>Посилається на</th><th>Тип</th><th>ON DELETE</th><th>ON UPDATE</th></tr>
          ${m.foreign_keys.map((f) => `<tr><td><a href="#tables/${f.child}"><code>${esc(f.child)}</code></a></td><td><code>${esc(f.columns)}</code></td><td>→</td>
            <td><a href="#tables/${f.parent}"><code>${esc(f.parent)}</code></a></td><td>${cardinality(m, f)}</td>
            <td><span class="rule ${ruleCls(f.on_delete)}">${esc(f.on_delete)}</span></td><td><span class="rule">${esc(f.on_update)}</span></td></tr>`).join('')}</table></div>
        <h2>Що змінено порівняно з поточною базою</h2>
        <div class="tbl"><table><tr><th>Поточна база</th><th>Нова модель</th><th>Зміна</th></tr>
          ${m.mapping.map((x) => `<tr><td><code>${esc(x.current)}</code></td><td><a href="#tables/${esc(x.model.split(',')[0])}"><code>${esc(x.model)}</code></a></td><td>${esc(x.change)}</td></tr>`).join('')}</table></div>`;
    }).catch((e) => status(box, e));
  }

  // ======================= ТАБЛИЦІ =======================
  function viewTables(v, name) {
    v.innerHTML = `<div class="eyebrow">Таблиці</div><h1>Структура таблиць</h1>
      <p class="lead">Оберіть таблицю: стовпці з типами даних, обов’язковість (NOT NULL), значення за замовчуванням (DEFAULT), ключі та перевірки CHECK.</p>
      <div id="tbody" class="status">Завантаження з бази…</div>`;
    const box = $('#tbody');
    once('site_model').then((m) => {
      const t = m.tables.find((x) => x.name === name) || m.tables.find((x) => x.name === 'lesson') || m.tables[0];
      const grouped = GROUPS.map(([g, list]) => [g, list.filter((n) => m.tables.some((x) => x.name === n))]);
      const extra = m.tables.map((x) => x.name).filter((n) => !GROUPS.some(([, l]) => l.includes(n)));
      if (extra.length) grouped.push(['Інші', extra]);
      const keyTag = (k) => (k || '').split(',').filter(Boolean).map((x) => tag(x, x.toLowerCase())).join('');
      const checks = m.checks.filter((c) => c.table === t.name);
      const out = m.foreign_keys.filter((f) => f.child === t.name);
      const inc = m.foreign_keys.filter((f) => f.parent === t.name);
      box.className = '';
      box.innerHTML = `<div class="split">
        <div class="tlist">${grouped.map(([g, list]) => `<div class="grp">${esc(g)}</div>` + list.map((n) => {
          const x = m.tables.find((y) => y.name === n);
          return `<a href="#tables/${n}" class="${n === t.name ? 'on' : ''}">${esc(n)}<span>${x.rows}</span></a>`;
        }).join('')).join('')}</div>
        <div>
          <h2 style="margin-top:0">${esc(title(t.name))} <code class="muted">${esc(t.name)}</code></h2>
          <p>${esc(t.comment || (DESC[t.name] || [])[1] || '')}</p>
          <p class="muted">Стовпців: ${t.columns.length} · рядків тестових даних: ${t.rows}</p>
          <div class="tbl"><table><tr><th>Стовпець</th><th>Тип даних</th><th>NOT NULL</th><th>DEFAULT</th><th>Ключ</th></tr>
            ${t.columns.map((c) => `<tr><td><code>${esc(c.name)}</code></td><td><code>${esc(c.type)}</code></td>
              <td>${c.not_null ? tag('так', 'ok') : '<span class="muted">—</span>'}</td>
              <td>${c.default ? `<code>${esc(c.default)}</code>` : '<span class="muted">—</span>'}</td><td>${keyTag(c.keys)}</td></tr>`).join('')}</table></div>
          <h3>Перевірки CHECK (${checks.length})</h3>
          ${checks.length ? `<div class="tbl"><table><tr><th>Назва</th><th>Умова</th></tr>${checks.map((c) => `<tr><td><code>${esc(c.name)}</code></td><td><code style="white-space:normal">${esc(c.definition)}</code></td></tr>`).join('')}</table></div>` : '<p class="muted">немає</p>'}
          <h3>Посилається на (${out.length})</h3>
          ${out.length ? `<div class="tbl"><table><tr><th>Стовпці</th><th>Таблиця</th><th>ON DELETE</th><th>ON UPDATE</th></tr>${out.map((f) => `<tr><td><code>${esc(f.columns)}</code></td><td><a href="#tables/${f.parent}"><code>${esc(f.parent)}</code></a></td><td><span class="rule ${ruleCls(f.on_delete)}">${esc(f.on_delete)}</span></td><td><span class="rule">${esc(f.on_update)}</span></td></tr>`).join('')}</table></div>` : '<p class="muted">незалежна таблиця — без зовнішніх ключів</p>'}
          <h3>На неї посилаються (${inc.length})</h3>
          ${inc.length ? `<div class="tbl"><table><tr><th>Таблиця</th><th>Стовпці</th><th>ON DELETE</th></tr>${inc.map((f) => `<tr><td><a href="#tables/${f.child}"><code>${esc(f.child)}</code></a></td><td><code>${esc(f.columns)}</code></td><td><span class="rule ${ruleCls(f.on_delete)}">${esc(f.on_delete)}</span></td></tr>`).join('')}</table></div>` : '<p class="muted">немає</p>'}
          <p style="margin-top:16px"><a class="btn ghost" href="#ddl/${t.name}">CREATE TABLE ${esc(t.name)} →</a></p>
        </div></div>`;
    }).catch((e) => status(box, e));
  }

  // ======================= ЦІЛІСНІСТЬ =======================
  function viewIntegrity(v) {
    v.innerHTML = `<div class="eyebrow">Цілісність даних</div><h1>Що база не дозволить зберегти</h1>
      <p class="lead">Правила зберігаються в самій базі, а не в коді сайту: їх неможливо обійти жодним застосунком. Перевірка нижче намагається зберегти неправильні дані й видалити пов’язані рядки — кожна спроба виконується з відкатом, тож дані не змінюються.</p>
      <div id="ibody" class="status">Завантаження з бази…</div>
      <h2>Перевірка наживо</h2>
      <p><button class="btn" id="run">Перевірити правила бази</button></p>
      <div id="tests"></div>`;
    const box = $('#ibody');
    once('site_model').then((m) => {
      const cols = m.tables.flatMap((t) => t.columns);
      const by = (r) => m.foreign_keys.filter((f) => f.on_delete === r).length;
      box.className = '';
      box.innerHTML = `<div class="grid">
          <div class="card kpi"><b>${m.counts.pk}</b><span>PRIMARY KEY — кожен рядок однозначно визначений</span></div>
          <div class="card kpi"><b>${m.counts.fk}</b><span>FOREIGN KEY — посилання лише на існуючі рядки</span></div>
          <div class="card kpi"><b>${m.counts.unique}</b><span>UNIQUE — без дублікатів (телефон, e-mail, назва курсу…)</span></div>
          <div class="card kpi"><b>${m.counts.check}</b><span>CHECK — допустимі значення й діапазони</span></div>
          <div class="card kpi"><b>${cols.filter((c) => c.not_null).length}</b><span>NOT NULL — обов’язкові стовпці з ${cols.length}</span></div>
          <div class="card kpi"><b>${cols.filter((c) => c.default).length}</b><span>DEFAULT — значення за замовчуванням</span></div>
        </div>
        <h2>Каскадні дії при видаленні</h2>
        <div class="grid">
          <div class="card"><h3><span class="rule c">ON DELETE CASCADE</span> · ${by('CASCADE')}</h3><p>Залежні рядки видаляються разом із головним: скасували заняття — зникли записи на нього й відмітки.</p></div>
          <div class="card"><h3><span class="rule r">ON DELETE RESTRICT</span> · ${by('RESTRICT')}</h3><p>Видалення заборонено, поки є залежні рядки: не можна видалити учня з історією занять чи курс із заняттями.</p></div>
          <div class="card"><h3><span class="rule n">ON DELETE SET NULL</span> · ${by('SET NULL')}</h3><p>Посилання очищається, рядок лишається: списали принтер — роботи учнів зберігаються.</p></div>
        </div>`;
    }).catch((e) => status(box, e));
    $('#run').addEventListener('click', async (ev) => {
      const btn = ev.target, out = $('#tests'); btn.disabled = true;
      out.innerHTML = '<div class="status">Перевірка…</div>';
      try {
        const rows = (await rpc('site_integrity_tests')).sort((a, b) => a.no - b.no);
        const ok = rows.filter((r) => r.ok).length;
        out.innerHTML = `<p>${tag(`${ok} з ${rows.length} правил спрацювали як очікувалося`, ok === rows.length ? 'ok' : 'bad')}</p>
          <div class="tbl"><table><tr><th>№</th><th>Спроба</th><th>Очікування</th><th>Відповідь бази</th><th></th></tr>
          ${rows.map((r) => `<tr><td>${r.no}</td><td>${esc(r.test)}</td><td>${esc(r.expected)}</td><td>${esc(r.result)}</td><td>${r.ok ? tag('так', 'ok') : tag('ні', 'bad')}</td></tr>`).join('')}</table></div>`;
      } catch (e) { out.innerHTML = '<div class="status"></div>'; status(out.firstChild, e); }
      finally { btn.disabled = false; }
    });
  }

  // ======================= DDL =======================
  let ddlText = null;
  const KW = /\b(CREATE|TABLE|SCHEMA|DROP|IF|EXISTS|CASCADE|SET|PRIMARY|KEY|FOREIGN|REFERENCES|UNIQUE|CHECK|NOT|NULL|DEFAULT|ON|DELETE|UPDATE|RESTRICT|CONSTRAINT|GENERATED|ALWAYS|AS|IDENTITY|AND|OR|IN|BETWEEN|COMMENT|IS|TO|ALTER|INDEX|ADD|TRUE|FALSE)\b/g;
  const hl = (sql) => sql.split('\n').map((line) => {
    const i = line.indexOf('--'); const code = i >= 0 ? line.slice(0, i) : line; const cm = i >= 0 ? line.slice(i) : '';
    return esc(code).replace(KW, '<span class="kw">$1</span>') + (cm ? `<span class="cm">${esc(cm)}</span>` : '');
  }).join('\n');
  function viewDDL(v, name) {
    v.innerHTML = `<div class="eyebrow">DDL-скрипт</div><h1>SQL-скрипт створення бази</h1>
      <p class="lead">Скрипт створює схему й усі таблиці в порядку залежностей: спочатку довідники, потім таблиці із зовнішніми ключами, асоціативні таблиці — останніми.</p>
      <div class="toolbar"><div><label for="ddlSel">Показати</label><select id="ddlSel"><option value="">увесь скрипт</option></select></div>
        <a class="btn ghost" href="sql/schema.sql" download="stemik_schema.sql">Завантажити .sql</a></div>
      <div id="ddl" class="status">Завантаження…</div>`;
    const box = $('#ddl'), sel = $('#ddlSel');
    const load = ddlText ? Promise.resolve(ddlText) : fetch('sql/schema.sql').then((r) => { if (!r.ok) throw new Error('Не вдалося завантажити sql/schema.sql'); return r.text(); }).then((t) => (ddlText = t));
    load.then((text) => {
      const blocks = {}; const re = /CREATE TABLE (\w+) \([\s\S]*?\n\);/g; let mm;
      while ((mm = re.exec(text))) blocks[mm[1]] = mm[0];
      sel.innerHTML += Object.keys(blocks).map((n) => `<option value="${n}">CREATE TABLE ${n}</option>`).join('');
      const show = (n) => { box.className = ''; box.innerHTML = `<pre class="sql">${hl(n && blocks[n] ? blocks[n] : text)}</pre>`; };
      sel.value = blocks[name] ? name : ''; show(sel.value);
      sel.addEventListener('change', () => { history.replaceState(null, '', '#ddl' + (sel.value ? '/' + sel.value : '')); show(sel.value); });
    }).catch((e) => status(box, e));
  }

  route();
})();
