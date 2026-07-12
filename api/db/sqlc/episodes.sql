-- name: UpsertEpisode :one
INSERT INTO episodes (
  season_id,
  tmdb_id,
  title,
  poster_path,
  runtime,
  state,
  air_at
) VALUES (
  $1, $2, $3, $4, $5, $6, $7
)
ON CONFLICT (season_id, tmdb_id) DO UPDATE SET
  title = EXCLUDED.title,
  poster_path = EXCLUDED.poster_path,
  runtime = EXCLUDED.runtime,
  state = EXCLUDED.state,
  air_at = EXCLUDED.air_at,
  updated_at = NOW()
RETURNING
  id,
  season_id,
  tmdb_id,
  title,
  poster_path,
  runtime,
  state,
  air_at,
  created_at,
  updated_at;

-- name: DeleteEpisodeBySeasonAndTmdbId :exec
DELETE FROM episodes WHERE season_id = $1 AND tmdb_id = $2;
