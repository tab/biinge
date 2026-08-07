-- Watched stats come in pairs: a bounded query for the current calendar period and
-- an all-time one. Serving both from a single statement with a nullable bound makes
-- postgres settle on a generic plan that never uses the watched_at indexes.

-- name: MovieStats :one
-- Everything is scoped to the period: want counts what was added to the list inside it,
-- dated by created_at since a row carries no record of when it entered a state
WITH bound AS (
  SELECT date_trunc(sqlc.arg(period_unit)::text, NOW()) AS since
)
SELECT
  COUNT(*) FILTER (WHERE state = 'want' AND created_at >= (SELECT since FROM bound))::bigint AS want_count,
  COUNT(*) FILTER (WHERE state = 'watched' AND watched_at >= (SELECT since FROM bound))::bigint AS watched_count,
  COALESCE(SUM(runtime) FILTER (WHERE state = 'watched' AND watched_at >= (SELECT since FROM bound)), 0)::bigint AS watched_minutes
FROM movies
WHERE user_id = sqlc.arg(user_id);

-- name: MovieStatsAll :one
-- Want is a backlog rather than an event, so it only exists all-time
SELECT
  COUNT(*) FILTER (WHERE state = 'want')::bigint AS want_count,
  COUNT(*) FILTER (WHERE state = 'watched')::bigint AS watched_count,
  COALESCE(SUM(runtime) FILTER (WHERE state = 'watched'), 0)::bigint AS watched_minutes
FROM movies
WHERE user_id = $1;

-- name: SeriesStats :one
-- A show counts as watched in the period when any of its episodes was ticked inside it.
-- series carries no watched_at of its own, so the episodes are what date a show.
-- There is no watching count: a show is being watched now, which no window can bound
WITH bound AS (
  SELECT date_trunc(sqlc.arg(period_unit)::text, NOW()) AS since
)
SELECT
  (
    SELECT COUNT(*)
    FROM series w
    WHERE w.user_id = sqlc.arg(user_id)
      AND w.state = 'want'
      AND w.created_at >= (SELECT since FROM bound)
  )::bigint AS want_count,
  (
    SELECT COUNT(DISTINCT t.id)
    FROM episodes e
      JOIN seasons s ON e.season_id = s.id
      JOIN series t ON s.series_id = t.id
    WHERE t.user_id = sqlc.arg(user_id)
      AND e.watched_at >= (SELECT since FROM bound)
  )::bigint AS watched_count;

-- name: SeriesStatsAll :one
SELECT
  COUNT(*) FILTER (WHERE state = 'want')::bigint AS want_count,
  COUNT(*) FILTER (WHERE state = 'watching')::bigint AS watching_count,
  COUNT(*) FILTER (WHERE state = 'watched')::bigint AS watched_count
FROM series
WHERE user_id = $1;

-- name: EpisodeStats :one
-- Episode rows only exist while watched, so the period filters on watched_at alone
SELECT
  COUNT(*)::bigint AS watched_count,
  COALESCE(SUM(e.runtime), 0)::bigint AS watched_minutes
FROM episodes e
  JOIN seasons s ON e.season_id = s.id
  JOIN series t ON s.series_id = t.id
WHERE t.user_id = sqlc.arg(user_id)
  AND e.watched_at >= date_trunc(sqlc.arg(period_unit)::text, NOW());

-- name: EpisodeStatsAll :one
SELECT
  COUNT(*)::bigint AS watched_count,
  COALESCE(SUM(e.runtime), 0)::bigint AS watched_minutes
FROM episodes e
  JOIN seasons s ON e.season_id = s.id
  JOIN series t ON s.series_id = t.id
WHERE t.user_id = $1;

-- name: GameStats :one
-- Scoped to the period the way movies are: want counts what was added inside it, played
-- what was finished inside it. There is no playing count -- a game is being played now,
-- which no window can bound
WITH bound AS (
  SELECT date_trunc(sqlc.arg(period_unit)::text, NOW()) AS since
)
SELECT
  COUNT(*) FILTER (WHERE state = 'want' AND created_at >= (SELECT since FROM bound))::bigint AS want_count,
  COUNT(*) FILTER (WHERE state = 'played' AND played_at >= (SELECT since FROM bound))::bigint AS played_count,
  COALESCE(SUM(runtime) FILTER (WHERE state = 'played' AND played_at >= (SELECT since FROM bound)), 0)::bigint AS played_minutes
FROM games
WHERE user_id = sqlc.arg(user_id);

-- name: GameStatsAll :one
-- Minutes are IGDB's time to beat the game normally, not time the user actually played
SELECT
  COUNT(*) FILTER (WHERE state = 'want')::bigint AS want_count,
  COUNT(*) FILTER (WHERE state = 'playing')::bigint AS playing_count,
  COUNT(*) FILTER (WHERE state = 'played')::bigint AS played_count,
  COALESCE(SUM(runtime) FILTER (WHERE state = 'played'), 0)::bigint AS played_minutes
FROM games
WHERE user_id = $1;

-- name: WatchActivity :many
-- Watched minutes per bucket, split into movie and TV runtime and dense (buckets
-- with no activity return zero). Buckets span the whole current calendar period --
-- Monday to Sunday, the 1st to the end of the month, January to December -- so the
-- rest of an unfinished period reads as empty.
WITH bound AS (
  SELECT
    date_trunc(sqlc.arg(period_unit)::text, NOW()) AS since,
    CASE sqlc.arg(period_unit)::text
      WHEN 'week' THEN INTERVAL '1 week'
      WHEN 'month' THEN INTERVAL '1 month'
      ELSE INTERVAL '1 year'
    END AS span,
    -- bounded periods only ever bucket by day or month
    CASE sqlc.arg(bucket_unit)::text
      WHEN 'day' THEN INTERVAL '1 day'
      ELSE INTERVAL '1 month'
    END AS step
),
watched AS (
  SELECT mv.watched_at AS watched_at, mv.runtime AS minutes, 'movie' AS kind
  FROM movies mv
  WHERE mv.user_id = sqlc.arg(user_id)
    AND mv.watched_at >= (SELECT since FROM bound)
  UNION ALL
  SELECT e.watched_at AS watched_at, e.runtime AS minutes, 'tv' AS kind
  FROM episodes e
    JOIN seasons s ON e.season_id = s.id
    JOIN series t ON s.series_id = t.id
  WHERE t.user_id = sqlc.arg(user_id)
    AND e.watched_at >= (SELECT since FROM bound)
),
totals AS (
  SELECT
    date_trunc(sqlc.arg(bucket_unit)::text, w.watched_at) AS bucket,
    SUM(w.minutes) FILTER (WHERE w.kind = 'movie') AS movie_minutes,
    SUM(w.minutes) FILTER (WHERE w.kind = 'tv') AS tv_minutes
  FROM watched w
  GROUP BY 1
)
SELECT
  b.bucket::date AS bucket,
  COALESCE(t.movie_minutes, 0)::bigint AS movie_minutes,
  COALESCE(t.tv_minutes, 0)::bigint AS tv_minutes
FROM bound
  CROSS JOIN LATERAL generate_series(since, since + span - step, step) AS b(bucket)
  LEFT JOIN totals t ON t.bucket = b.bucket
ORDER BY b.bucket;

-- name: WatchActivityAll :many
-- Watched minutes per year across the whole history, dense and split by media kind
WITH watched AS (
  SELECT mv.watched_at AS watched_at, mv.runtime AS minutes, 'movie' AS kind
  FROM movies mv
  WHERE mv.user_id = sqlc.arg(user_id) AND mv.watched_at IS NOT NULL
  UNION ALL
  SELECT e.watched_at AS watched_at, e.runtime AS minutes, 'tv' AS kind
  FROM episodes e
    JOIN seasons s ON e.season_id = s.id
    JOIN series t ON s.series_id = t.id
  WHERE t.user_id = sqlc.arg(user_id) AND e.watched_at IS NOT NULL
),
totals AS (
  SELECT
    date_trunc('year', w.watched_at) AS bucket,
    SUM(w.minutes) FILTER (WHERE w.kind = 'movie') AS movie_minutes,
    SUM(w.minutes) FILTER (WHERE w.kind = 'tv') AS tv_minutes
  FROM watched w
  GROUP BY 1
),
buckets AS (
  -- the earliest bucket comes from the yearly totals rather than a second pass
  -- over every watch, which leaves the history read exactly once
  SELECT generate_series(
    COALESCE((SELECT MIN(bucket) FROM totals), date_trunc('year', NOW())),
    date_trunc('year', NOW()),
    INTERVAL '1 year'
  ) AS bucket
)
SELECT
  b.bucket::date AS bucket,
  COALESCE(t.movie_minutes, 0)::bigint AS movie_minutes,
  COALESCE(t.tv_minutes, 0)::bigint AS tv_minutes
FROM buckets b
  LEFT JOIN totals t ON t.bucket = b.bucket
ORDER BY b.bucket;
