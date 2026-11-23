// Підключення до проєкту Supabase і поточний етап розвитку сайту.
// Supabase → Project Settings → API Keys:
//   url     — Project URL, напр. 'https://abcd1234.supabase.co'
//   anonKey — ключ anon (Legacy) або publishable (sb_publishable_…).
//             НЕ service_role і НЕ secret!
// stage — скільки розділів сайту ввімкнено (кожен етап додає нові):
//   1 — огляд і предметна область
//   2 — + модель даних, таблиці, цілісність, DDL
window.STEMIK_CONFIG = {
  url: '',
  anonKey: '',
  stage: 2,
};
