#!/usr/bin/env bash
# Fails when a route or a wire shape moves without api/api/swagger.yaml
set -euo pipefail

base="${1:-origin/master}"
changed="$(git diff --name-only "$base"...HEAD)"
status=0

touched() { grep -qE "$1" <<<"$changed"; }

# Controllers carry the status codes and serializers the wire shapes; tests and mocks carry neither
contract="$(grep -E '^api/internal/(app/(controllers|serializers)/.*|config/router/router)\.go$' <<<"$changed" \
  | grep -vE '_(test|mock)\.go$' || true)"

# A comment or a gofmt realignment moves no contract, so grade the changed lines rather than the path
moved=""
while IFS= read -r file; do
  [ -z "$file" ] && continue

  lines="$(git diff -U0 -w "$base"...HEAD -- "$file" | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' || true)"

  if [ -n "$lines" ] && grep -qvE '^[+-][[:space:]]*(//.*)?$' <<<"$lines"; then
    moved+="$file"$'\n'
  fi
done <<<"$contract"

if [ -n "$moved" ] && [ -z "${ALLOW_SPEC_DRIFT:-}" ] && ! touched '^api/api/swagger\.yaml$'; then
  echo "::error::a route or serializer changed without api/api/swagger.yaml"
  while IFS= read -r file; do [ -n "$file" ] && echo "  $file"; done <<<"$moved"
  echo "  no contract moved? label the pull request contract-unchanged, then re-run this job"
  status=1
fi

# The reference page keeps its own endpoint list, so it can lag a change it does not cover
if touched '^api/api/swagger\.yaml$' && ! touched '^docs/src/pages/docs/api\.astro$'; then
  echo "::warning::api/api/swagger.yaml changed without docs/src/pages/docs/api.astro. Check whether the reference page covers the endpoint you moved"
fi

[ "$status" -eq 0 ] && echo "No spec drift."
exit "$status"
