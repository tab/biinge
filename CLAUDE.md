# biinge

Monorepo: `api/` (Go REST API), `ios/` (SwiftUI client), `docs/` (Astro site on
GitHub Pages). Each has a README covering setup, commands and configuration —
read those rather than re-deriving them. `api/CLAUDE.md` and `ios/CLAUDE.md`
carry the conventions specific to each.

## Working agreement

- Give honest, realistic assessments of requests, feasibility and risk. No
  sugar-coating, and no vague maybes where a concrete answer exists
- Assume the request may rest on a wrong or incomplete premise. Evaluate it
  rather than executing it verbatim, and ask when the answer changes the work
- State assumptions explicitly when proceeding without asking. Where a request
  reads two ways, surface both rather than silently picking one
- We work as two senior developers. Be direct, skip the flattery, and say when
  something is a bad idea
- Prefer the simplest thing that works, then iterate. Don't overthink

## Finish with the verification loop

Every implementation ends with the area's verification loop — not only the ones
that end in a commit. `make check` in `api/`, `make lint && make test` in `ios/`,
`npm run build` in `docs/`. Fix what it reports and re-run until clean.

If a loop can't be run, say so plainly and call the work unverified. Never
report an implementation as done on the strength of the code looking right.

## No sugar

- Don't add an abstraction until something needs it. No factories, no thin
  wrappers that only forward or rename, no generalizing for a second caller that
  doesn't exist yet
- Don't factor a small branch into a private helper. Repeat it in each method,
  with a short comment where the reasoning isn't obvious — reading a method
  should show its whole control flow
- One interface, one implementation, one mock
- Don't add error handling, validation or fallbacks for cases that can't happen

## Conventions

- Doc comments are one line and take no trailing period, in Go and Swift alike.
  Extra detail goes in parentheses inside that sentence; anything longer belongs
  in a body comment, not the doc comment
- Comments describe what the code does now, never how it got there. No history,
  no "changed from", no commented-out code left behind
- Make surgical changes. Don't reformat, rename or "improve" code the task
  didn't ask about; remove only what your own edits orphaned
- The linters own the mechanical rules (`api/.golangci.yaml`,
  `ios/.swiftlint.yml`). Don't restate them here, and run `make lint` rather
  than hand-fixing what it fixes

## Deployment hosts stay out of the repo

No committed file names the production domain. Hosts live in gitignored `.env`
files and, for CI, in GitHub Actions repository variables:

| Where | Names |
| --- | --- |
| `docs/.env` and Actions variables | `SITE_URL`, `PUBLIC_API_BASE_URL` |
| `ios/.env` | `API_BASE_URL` |
| the deployment compose file | `CLIENT_URL` |

Committed templates (`*.env.example`, `api/.env.production`) hold placeholders
or empty values. The Pages workflow derives the CNAME from `SITE_URL` instead of
committing one. An unset repository variable arrives as an empty string, not as
absent — treat empty as unset when reading one.

## Commits

Conventional Commits, always scoped: `feat(api):`, `fix(ios):`, `docs(readme):`.
Imperative and capitalized, no trailing period. No AI attribution anywhere in
the message: no `Co-Authored-By` or `Claude-Session` trailer, no "Generated
with" line, no robot emoji. Naming a path is not attribution, so `docs(claude):`
for a change under `.claude/` is fine.

Commits are signed and made by hand. Write the message; never run `git commit`.

The default branch is `master`, not `main` — check before writing a branch name
or a permalink into docs.

## Hooks

`.githooks/` holds the two checks that run before the code leaves the machine.
Turn them on once per clone:

```
git config core.hooksPath .githooks
```

`commit-msg` rejects a subject that isn't a scoped Conventional Commit and any
AI attribution in the message. `pre-push` runs the verification loop for each
area the push touches, then the schema and spec drift checks. Push with
`--no-verify`, or set `SKIP_VERIFY=1`, when you mean to skip it.

The `Title & commits` job repeats both checks on the pull request, so a clone
without the hooks installed still gets caught.

## Workflow

- Use `gh` for anything on GitHub: pull requests, issues, checks, releases
- PR descriptions carry no "Test plan" section
- Before merging `master` into a working branch, pull both so neither is stale
- Skills in `.claude/skills/` hold the procedural loops (`verify`, `add-test`,
  `generate-mock`) and load on demand. Reach for them rather than reciting the
  steps
