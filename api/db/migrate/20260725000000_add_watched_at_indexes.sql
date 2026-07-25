-- +goose Up
-- The statistics screen windows watched history by calendar period. Both indexes are
-- partial because only watched rows carry a watched_at, which keeps them small.
-- Episodes have no user_id of their own, so the period has to be narrowed on
-- watched_at before joining up through seasons to series.
CREATE INDEX episodes_watched_at_idx ON episodes (watched_at) WHERE watched_at IS NOT NULL;
CREATE INDEX movies_user_id_watched_at_idx ON movies (user_id, watched_at) WHERE watched_at IS NOT NULL;

-- +goose Down
DROP INDEX movies_user_id_watched_at_idx;
DROP INDEX episodes_watched_at_idx;
