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
