-- name: CreateUser :one
INSERT INTO users (
  login,
  email,
  encrypted_password,
  first_name,
  last_name,
  appearance
) VALUES (
  $1, $2, $3, $4, $5, $6
) RETURNING id, login, email, first_name, last_name, appearance;

-- name: UpdateUser :one
UPDATE users
SET
  first_name = $2,
  last_name = $3,
  appearance = $4,
  updated_at = NOW()
WHERE id = $1
RETURNING id, login, email, first_name, last_name, appearance;

-- name: FindUserById :one
SELECT id, login, email, first_name, last_name, appearance
FROM users
WHERE id = $1 AND deleted_at IS NULL LIMIT 1;

-- name: FindUserByLogin :one
SELECT id, login, email, encrypted_password, first_name, last_name, appearance
FROM users
WHERE login = $1 AND deleted_at IS NULL LIMIT 1;

-- name: FindUserByEmail :one
SELECT id, login, email, encrypted_password, first_name, last_name, appearance
FROM users
WHERE email = $1 AND deleted_at IS NULL LIMIT 1;

