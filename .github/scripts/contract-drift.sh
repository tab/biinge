#!/usr/bin/env bash
# Fails when a change to the schema or the API contract leaves its committed
# artefact behind (api/CLAUDE.md: "generated code is committed", "the OpenAPI
# spec ships with the change")
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

# Controllers map sentinels to status codes and serializers are the wire shapes,
# so either one moving is a contract change. Tests and mocks are not.
contract="$(grep -E '^api/internal/(app/(controllers|serializers)/.*|config/router/router)\.go$' <<<"$changed" \
  | grep -vE '_(test|mock)\.go$' || true)"

if [ -n "$contract" ] && [ -z "${ALLOW_SPEC_DRIFT:-}" ] && ! touched '^api/api/swagger\.yaml$'; then
  echo "::error::a route or serializer changed without api/api/swagger.yaml. The spec is hand-maintained and the iOS client reads it as the backend's documentation"
  while IFS= read -r file; do echo "  $file"; done <<<"$contract"
  echo "  no contract moved? label the PR contract-unchanged"
  status=1
fi

# The reference page keeps its own endpoint list and does not read the spec, so
# it can legitimately lag a change it does not cover
if touched '^api/api/swagger\.yaml$' && ! touched '^docs/src/pages/docs/api\.astro$'; then
  echo "::warning::api/api/swagger.yaml changed without docs/src/pages/docs/api.astro. Check whether the reference page covers the endpoint you moved"
fi

[ "$status" -eq 0 ] && echo "No contract or schema drift."
exit "$status"
