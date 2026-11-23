// Спільна частина навчальних версій сайту «Стемік».
// Кожна версія (labs/lrN/index.html) задає window.LAB_STAGE = N; меню
// показує етапи до N включно — наступна ЛР лише додає свій розділ.
(function () {
  const STAGES = [
    { n: 1, path: 'lr1', title: 'ЛР1 · Аналіз' },
    { n: 2, path: 'lr2', title: 'ЛР2 · Модель' },
    { n: 3, path: 'lr3', title: 'ЛР3 · Таблиці й дані' },
    { n: 4, path: 'lr4', title: 'ЛР4 · Запити' },
    { n: 5, path: 'lr5', title: 'ЛР5 · Форми' },
    { n: 6, path: 'lr6', title: 'ЛР6 · Логіка в БД' },
  ];

  const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  // Виклик функції бази через REST API Supabase (PostgREST): POST /rest/v1/rpc/<name>
  async function rpc(name, args) {
    const cfg = window.LAB_CONFIG || {};
    if (!cfg.url || !cfg.anonKey) {
      throw new Error('Не задано підключення: заповніть url і anonKey у labs/config.js (навчальний проєкт Supabase).');
    }
    const res = await fetch(cfg.url.replace(/\/$/, '') + '/rest/v1/rpc/' + name, {
      method: 'POST',
      // ключ формату sb_publishable_… — не JWT, його передають лише в apikey
      headers: Object.assign({ apikey: cfg.anonKey, 'Content-Type': 'application/json' },
        /^eyJ/.test(cfg.anonKey) ? { Authorization: 'Bearer ' + cfg.anonKey } : {}),
      body: JSON.stringify(args || {}),
    });
    const text = await res.text();
    if (!res.ok) {
      let msg = text;
      try { msg = JSON.parse(text).message || text; } catch (e) { /* не JSON */ }
      throw new Error(`Помилка ${res.status} у ${name}: ${msg}`);
    }
    return text ? JSON.parse(text) : null;
  }

  function header(current) {
    const stage = window.LAB_STAGE || 0;
    const published = Math.max(stage, window.LAB_PUBLISHED || 0);
    const nav = STAGES.map((s) => {
      const cls = s.n === current ? 'on' : s.n > published ? 'off' : '';
      return `<a class="${cls}" href="../${s.path}/">${esc(s.title)}</a>`;
    }).join('');
    const el = document.createElement('header');
    el.className = 'top';
    el.innerHTML = `<div class="wrap"><a class="brand" href="../" style="color:inherit;text-decoration:none">Стемік<small>навчальна версія · етап ЛР${stage}</small></a><nav>${nav}</nav></div>`;
    document.body.prepend(el);
  }

  function status(el, err) {
    el.className = 'status' + (err ? ' err' : '');
    el.textContent = err ? err.message || String(err) : 'Завантаження даних з бази…';
  }

  window.Lab = { rpc, header, status, esc, STAGES };
})();
