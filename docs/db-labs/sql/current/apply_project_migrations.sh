#!/usr/bin/env bash
# Відтворює поточну схему БД проєкту (Supabase) у локальному PostgreSQL:
# заглушки Supabase + базові таблиці + міграції sql/0001…0022.
# Міграції 0001–0012 видалено з репозиторію в коміті 3447c4f, тому
# їх беремо з історії git.
# Використання: ./apply_project_migrations.sh <назва_бази>  (змінні PG* — як для psql)
set -euo pipefail
DB=${1:-stemik_current}
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(git -C "$HERE" rev-parse --show-toplevel)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
for f in $(git -C "$REPO" show --name-only --format= 3447c4f); do
  git -C "$REPO" show "3447c4f^:$f" > "$TMP/$(basename "$f")"
done
cp "$REPO"/sql/*.sql "$TMP/"
PSQL="psql -q -v ON_ERROR_STOP=1 -d $DB"
$PSQL -f "$HERE/00_supabase_stubs.sql" -f "$HERE/00_base_reconstructed.sql"
for f in $(ls "$TMP"/*.sql | sort); do
  echo "→ $(basename "$f")"
  $PSQL -f "$f"
done
