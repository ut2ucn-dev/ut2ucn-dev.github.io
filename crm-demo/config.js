// Підключення до навчального проєкту Supabase.
// Supabase → Project Settings → API (Data API):
//   url     — Project URL, напр. 'https://abcd1234.supabase.co'
//   anonKey — ключ anon / publishable (НЕ service_role і НЕ secret!)
// Ключ anon можна публікувати: без входу він дає лише функцію перевірки
// підключення crm_ping(); решта функцій доступна тільки після входу.
window.CRM_CONFIG = {
  url: '',
  anonKey: '',
};
