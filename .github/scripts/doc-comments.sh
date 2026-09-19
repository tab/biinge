#!/usr/bin/env bash
# Grades doc comments against the CLAUDE.md rule: one sentence, no trailing period
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"

paths=("$@")
[ "${#paths[@]}" -eq 0 ] && paths=(.)

files="$(git ls-files -- "${paths[@]}" | grep -E '\.(go|swift)$' || true)"
[ -z "$files" ] && { echo "No sources to check."; exit 0; }

hits="$(
  while IFS= read -r file; do
    # mockgen and sqlc write their own comments, and neither is ours to reword
    head -5 "$file" | grep -q 'DO NOT EDIT' && continue

    awk -v file="$file" -v ci="${GITHUB_ACTIONS:-}" '
      function grade(   joined, i, why) {
        if (n == 0) return

        joined = ""
        for (i = 1; i <= n; i++) joined = joined (i > 1 ? " " : "") text[i]

        if (para) why = "a paragraph break"
        else if (joined ~ /\.[ \t]+[A-Z]/) why = "a second sentence"
        else if (joined ~ /\.$/ && joined !~ /\.\.\.$/) why = "a trailing period"
        else return

        # ::error:: makes it an annotation on the pull request; a local run wants the plain line
        if (ci != "") printf "::error file=%s,line=%d::doc comment has %s: %s\n", file, start, why, joined
        else printf "%s:%d: doc comment has %s: %s\n", file, start, why, joined
      }

      function reset() { n = 0; para = 0 }

      BEGIN { swift = (file ~ /\.swift$/); reset() }

      {
        line = $0
        sub(/^[ \t]+/, "", line)

        isdoc = swift ? (line ~ /^\/\/\//) : (line ~ /^\/\// && line !~ /^\/\/(go:|nolint)/)

        if (isdoc) {
          if (n == 0) start = NR
          body = line
          sub(/^\/+[ \t]*/, "", body)
          if (body == "") para = 1
          else { n++; text[n] = body }
          next
        }

        # Every /// is a doc comment; in Go only a top-level declaration makes the block above it one
        if (swift || $0 ~ /^(func|type|const|var|package)[ \t(]/) grade()

        reset()
      }
    ' "$file"
  done <<<"$files"
)"

[ -z "$hits" ] && { echo "Doc comments are one line."; exit 0; }

echo "$hits"
exit 1
