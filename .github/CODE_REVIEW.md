# biinge pull request review policy

## Purpose

This document defines the pull request review process for biinge. It covers the
process only: severity, hygiene, breaking changes and output format.

Code rules live elsewhere and are canonical:

| Source | Owns |
| --- | --- |
| `CLAUDE.md` | working agreement, commits, deployment hosts, the no-sugar rules |
| `api/CLAUDE.md` | Go layering, error handling, the OpenAPI contract, generated code |
| `ios/CLAUDE.md` | SwiftUI structure, stores, the backend contract, configuration |
| `.claude/skills/*/SKILL.md` | the verification loop, mock generation |

Cite the section heading rather than restating the rule.

## 1. Severity

- **BLOCKER**: fix before merge. A pull request with a blocker is not approved
- **MAJOR**: fix before merge
- **MINOR**: worth improving
- **OPTIONAL**: a suggestion the author can decline

Assignment:

- an undeclared breaking change (section 3) is a blocker
- anything that puts a production host in a committed file is a blocker
- a violation of a rule in `CLAUDE.md` or an area file is major
- a style note no rule covers is minor or optional

## 2. Hygiene

**Summary.** Every pull request explains what the change is for and what it
touches: routes, response shapes, migrations, watch-state writes, stores,
navigation, configuration. When the diff goes past the stated intent, ask.
Don't guess.

**Title (major).** Conventional Commits, scoped: `feat(api):`, `fix(ios):`,
`docs(readme):`. Imperative, capitalized, no trailing period.

**Commits (major).** One logical change each. No `wip`, no `fix`. No
AI attribution anywhere in the message: no `Co-Authored-By` or `Claude-Session`
trailer, no "Generated with" line, no robot emoji. Naming a path is not
attribution, so `docs(claude):` is fine.

**Description (minor).** No "Test plan" section.

## 3. Breaking changes

A change is breaking when it:

- removes or renames a route, a query parameter or a request field
- changes a response shape, a field name or a field type. The iOS `Models/`
  mirror the serializers, so a rename ships a client crash
- changes a status code a client branches on
- adds a migration that drops or renames a column, or that the running API
  cannot serve during a rolling deploy
- changes the JWT shape, its claims or its lifetime
- renames an environment variable the deployment sets

Undeclared in the summary makes it a blocker. When unsure, assume breaking and
say so.

## 4. Output

```
#### METADATA
- (2) Title:
- (2) Commits:

#### BLOCKERS
- [file:line] (source > section) What is wrong
  Fix:

#### MAJOR
- [file:line] (source > section) What is wrong
  Fix:

#### MINOR
- [file:line] What is wrong

#### OPTIONAL
- [file:line] Suggestion

#### INTENT MISMATCH
None, or what the diff does that the summary doesn't say

#### BREAKING CHANGE
No, or yes with the impact

#### VERDICT
APPROVE / REQUEST CHANGES / NEEDS DISCUSSION
```

Rules: code findings carry `file:line`. Blockers and majors cite a source and
section, and carry a concrete fix. Group by file. Write `None` for an empty
section rather than dropping it.
