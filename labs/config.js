// Підключення навчальних версій сайту до НАВЧАЛЬНОГО проєкту Supabase.
// Supabase Dashboard → Project Settings → API:
//   url     — Project URL (https://<ref>.supabase.co)
//   anonKey — ключ anon / publishable. Він публічний за призначенням:
//             сайт викликає лише функції lab_*, що повертають дозволені дані.
// НЕ вставляйте сюди ключ service_role / secret і не підключайте робочий проєкт.
window.LAB_CONFIG = {
  url: '',
  anonKey: '',
};
