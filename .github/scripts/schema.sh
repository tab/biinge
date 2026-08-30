#!/usr/bin/env bash
# Fails when a database change leaves its committed artefact behind (schema dump, sqlc output)
set -euo pipefail

base="${1:-origin/master}"
changed="$(git diff --name-only "$base"...HEAD)"
status=0

touched() { grep -qE "$1" <<<"$changed"; }

if touched '^api/db/migrate/' && ! touched '^api/db/schema\.sql$'; then
  echo "::error::api/db/migrate changed without api/db/schema.sql. Run: GO_ENV=test make db:migrate db:schema:dump"
  status=1
fi

if touched '^api/db/sqlc/' && ! touched '^api/internal/app/repositories/db/'; then
  echo "::error::api/db/sqlc changed without regenerating api/internal/app/repositories/db. Run: sqlc generate"
  status=1
fi

[ "$status" -eq 0 ] && echo "No schema drift."
exit "$status"
