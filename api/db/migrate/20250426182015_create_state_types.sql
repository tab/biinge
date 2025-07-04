-- +goose Up
CREATE TYPE state_types AS ENUM ('want', 'watching', 'watched', 'none');

-- +goose Down
DROP TYPE state_types;
