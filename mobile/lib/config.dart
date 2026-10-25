// Same Supabase project as the web version (config.js in the repo root).
// The anon key is public by design — Row Level Security in the database
// decides what each signed-in user may read and write.
const supabaseUrl = 'https://smfwlbbjcfezmayvcofv.supabase.co';
const supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZndsYmJqY2Zlem1heXZjb2Z2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg2OTg5ODgsImV4cCI6MjEwNDI3NDk4OH0.JqdFphXJFwxwe0lAdRwApjz15fAqP9Ezgx5WXQ-lx9U';

/// The web version; password-reset emails send people there.
const siteUrl = 'https://ut2ucn-dev.github.io/';

/// Published by CI (.github/workflows/mobile.yml) with every release from
/// main; the in-app update check reads it.
const updateManifestUrl = 'https://github.com/ut2ucn-dev/ut2ucn-dev.github.io/releases/latest/download/version.json';

/// Always the newest Android build.
const latestApkUrl = 'https://github.com/ut2ucn-dev/ut2ucn-dev.github.io/releases/latest/download/stemik.apk';

/// Always the newest macOS admin app.
const latestDmgUrl = 'https://github.com/ut2ucn-dev/ut2ucn-dev.github.io/releases/latest/download/stemik-admin.dmg';

/// The parents' portal; messages with a new parent password point there
/// (window.PARENT_PORTAL_URL in config.js).
const parentPortalUrl = 'https://client.stemik.studio';

/// Lesson dates and times are stored as studio-local wall-clock values.
const studioTimeZone = 'Europe/Kyiv';
