---
description: 'Rules for generating and reviewing code in the biinge repository'
applyTo: '**/*'
---

# Copilot instructions

biinge is a monorepo: a Go REST API in `api/`, a SwiftUI client in `ios/`, and an
Astro site in `docs/`.

## Canonical sources

Read these and treat them as authoritative:

- `CLAUDE.md` for the working agreement, commit format, the deployment-host
  policy and the no-sugar rules
- `api/CLAUDE.md` for Go layering, error handling, the OpenAPI contract and
  committed generated code
- `ios/CLAUDE.md` for SwiftUI structure, stores, the backend contract and
  configuration
- `.claude/skills/*/SKILL.md` for the verification loop and mock generation
- `.github/CODE_REVIEW.md` and `.github/CODE_REVIEW_PROMPT.md` for review

This applies to every assistant working here: Copilot, Codex, Claude Code,
Cursor. When one of these files and any other guide disagree, the file above
wins, and the drift is worth reporting.

## What the tooling already owns

Don't restate or hand-fix what a linter enforces. `api/.golangci.yaml` and
`ios/.swiftlint.yml` own the mechanical rules, `godoclint` included, so run
`make lint` instead of arguing style.

## Fallback order

When no rule covers the situation:

1. how the repository already solves the same problem
2. idiomatic Go, or idiomatic Swift 6 and SwiftUI
3. the Uber Go style guide, for Go only, as guidance that never overrides
   `CLAUDE.md`

Anything resting on 3 is a suggestion, not a violation.

## Two rules worth repeating

No committed file names the production domain. Hosts live in gitignored `.env`
files and in Actions repository variables.

Commit messages carry no `Co-Authored-By` trailer and no mention of AI tooling.
The default branch is `master`.
