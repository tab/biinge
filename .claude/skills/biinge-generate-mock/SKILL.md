---
name: biinge-generate-mock
description: Generate or regenerate a gomock mock for an interface in the biinge api. Use when adding a new interface, changing an existing one, or when tests fail against a stale mock.
---

# Generate a gomock mock

Mocks use `go.uber.org/mock`, are committed, and sit next to their source in the
same package: `foo.go` → `foo_mock.go`.

## Command

Run from `api/`, with paths relative to that directory:

```bash
mockgen \
  -source=internal/path/to/file.go \
  -destination=internal/path/to/file_mock.go \
  -package=packagename
```

## Rules

- No `//go:generate` directives — the repo has none, run mockgen directly
- Never hand-edit a `*_mock.go`. Change the interface and regenerate
- Name the file `*_mock.go`, never `*_mock_test.go` — other packages' tests
  import these
- The mock's package matches the source package
- Every interface a test needs to replace has a mock
- Regenerate and commit in the same change as the interface edit

## Example

For `StatsCache` in `internal/app/services/stats_cache.go`:

```bash
mockgen \
  -source=internal/app/services/stats_cache.go \
  -destination=internal/app/services/stats_cache_mock.go \
  -package=services
```

Then run `make check` — a stale mock elsewhere shows up as a compile failure in
the test build.
