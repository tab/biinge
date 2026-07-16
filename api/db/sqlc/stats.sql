-- name: MovieStats :one
SELECT
  COUNT(*) FILTER (WHERE state = 'want')::bigint AS want_count,
  COUNT(*) FILTER (WHERE state = 'watched')::bigint AS watched_count,
  COALESCE(SUM(runtime) FILTER (WHERE state = 'watched'), 0)::bigint AS watched_minutes
FROM movies
WHERE user_id = $1;

-- name: SeriesStats :one
SELECT
  COUNT(*) FILTER (WHERE state = 'want')::bigint AS want_count,
  COUNT(*) FILTER (WHERE state = 'watching')::bigint AS watching_count,
  COUNT(*) FILTER (WHERE state = 'watched')::bigint AS watched_count
FROM series
WHERE user_id = $1;

-- name: EpisodeStats :one
SELECT
  COUNT(*)::bigint AS watched_count,
  COALESCE(SUM(e.runtime), 0)::bigint AS watched_minutes
FROM episodes e
  JOIN seasons s ON e.season_id = s.id
  JOIN series t ON s.series_id = t.id
WHERE t.user_id = $1;

-- name: WatchActivityByMonth :many
-- Watched minutes per month for the last 12 months (dense: months with no
-- activity return zero), split into movie and TV runtime.
WITH months AS (
  SELECT generate_series(
    date_trunc('month', NOW()) - INTERVAL '11 months',
    date_trunc('month', NOW()),
    INTERVAL '1 month'
  ) AS month
),
watched AS (
  SELECT date_trunc('month', mv.watched_at) AS month, mv.runtime AS minutes, 'movie' AS kind
  FROM movies mv
  WHERE mv.user_id = $1 AND mv.watched_at IS NOT NULL
  UNION ALL
  SELECT date_trunc('month', e.watched_at) AS month, e.runtime AS minutes, 'tv' AS kind
  FROM episodes e
    JOIN seasons s ON e.season_id = s.id
    JOIN series t ON s.series_id = t.id
  WHERE t.user_id = $1 AND e.watched_at IS NOT NULL
)
SELECT
  m.month::date AS month,
  COALESCE(SUM(w.minutes) FILTER (WHERE w.kind = 'movie'), 0)::bigint AS movie_minutes,
  COALESCE(SUM(w.minutes) FILTER (WHERE w.kind = 'tv'), 0)::bigint AS tv_minutes
FROM months m
  LEFT JOIN watched w ON w.month = m.month
GROUP BY m.month
ORDER BY m.month;
