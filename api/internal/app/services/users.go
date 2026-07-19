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
		return nil, u.wrapError(err)
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
		return nil, u.wrapError(err)
	}

	return user, nil
}

func (u *users) FindById(ctx context.Context, id uuid.UUID) (*models.User, error) {
	user, err := u.repository.FindById(ctx, id)
	if err != nil {
		return nil, u.wrapError(err)
	}

	return user, nil
}

func (u *users) FindByLogin(ctx context.Context, login string) (*models.User, error) {
	user, err := u.repository.FindByLogin(ctx, login)
	if err != nil {
		return nil, u.wrapError(err)
	}

	return user, nil
}

func (u *users) FindByEmail(ctx context.Context, email string) (*models.User, error) {
	user, err := u.repository.FindByEmail(ctx, email)
	if err != nil {
		return nil, u.wrapError(err)
	}

	return user, nil
}

// wrapError maps a repository error to a sentinel that is safe to surface to callers
func (u *users) wrapError(err error) error {
	if errors.Is(err, pgx.ErrNoRows) {
		return errors.ErrUserNotFound
	}

	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == uniqueViolationCode {
		switch pgErr.ConstraintName {
		case "users_login_key":
			return errors.ErrLoginAlreadyExists
		case "users_email_key":
			return errors.ErrEmailAlreadyExists
		}
	}

	u.log.Error().Err(err).Msg("User repository error")

	return errors.ErrFailedToProcessUser
}
