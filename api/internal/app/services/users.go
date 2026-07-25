package services

import (
	"context"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/config/logger"
)

const uniqueViolationCode = "23505"

type Users interface {
	Create(ctx context.Context, params *models.User) (*models.User, error)
	Update(ctx context.Context, params *models.User) (*models.User, error)
	FindById(ctx context.Context, id uuid.UUID) (*models.User, error)
	FindByLogin(ctx context.Context, login string) (*models.User, error)
	FindByEmail(ctx context.Context, email string) (*models.User, error)
}

type users struct {
	repository repositories.UserRepository
	log        *logger.Logger
}

func NewUsers(repository repositories.UserRepository, log *logger.Logger) Users {
	return &users{
		repository: repository,
		log:        log.WithComponent("UsersService"),
	}
}

func (u *users) Create(ctx context.Context, params *models.User) (*models.User, error) {
	user, err := u.repository.Create(ctx, db.CreateUserParams{
		Login:             params.Login,
		Email:             params.Email,
		EncryptedPassword: params.EncryptedPassword,
		FirstName:         params.FirstName,
		LastName:          params.LastName,
		Appearance:        db.AppearanceType(params.Appearance),
	})
	if err != nil {
		// registration races on the unique login and email indexes
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == uniqueViolationCode {
			switch pgErr.ConstraintName {
			case "users_login_key":
				return nil, errors.ErrLoginAlreadyExists
			case "users_email_key":
				return nil, errors.ErrEmailAlreadyExists
			}
		}

		u.log.Error().Err(err).Msg("Failed to create user")

		return nil, errors.ErrFailedToProcessUser
	}

	return user, nil
}

func (u *users) Update(ctx context.Context, params *models.User) (*models.User, error) {
	user, err := u.repository.Update(ctx, db.UpdateUserParams{
		ID:         params.ID,
		FirstName:  params.FirstName,
		LastName:   params.LastName,
		Appearance: db.AppearanceType(params.Appearance),
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.ErrUserNotFound
		}

		u.log.Error().Err(err).Msg("Failed to update user")

		return nil, errors.ErrFailedToProcessUser
	}

	return user, nil
}

func (u *users) FindById(ctx context.Context, id uuid.UUID) (*models.User, error) {
	user, err := u.repository.FindById(ctx, id)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.ErrUserNotFound
		}

		u.log.Error().Err(err).Msg("Failed to fetch user by Id")

		return nil, errors.ErrFailedToProcessUser
	}

	return user, nil
}

func (u *users) FindByLogin(ctx context.Context, login string) (*models.User, error) {
	user, err := u.repository.FindByLogin(ctx, login)
	if err != nil {
		// a login nobody holds is the ordinary case on a failed sign-in
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.ErrUserNotFound
		}

		u.log.Error().Err(err).Msg("Failed to fetch user by login")

		return nil, errors.ErrFailedToProcessUser
	}

	return user, nil
}

func (u *users) FindByEmail(ctx context.Context, email string) (*models.User, error) {
	user, err := u.repository.FindByEmail(ctx, email)
	if err != nil {
		// an unregistered email is the ordinary case when checking availability
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.ErrUserNotFound
		}

		u.log.Error().Err(err).Msg("Failed to fetch user by email")

		return nil, errors.ErrFailedToProcessUser
	}

	return user, nil
}
