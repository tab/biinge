package services

import (
	"context"

	"github.com/google/uuid"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/config/logger"
)

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
		return nil, err
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
		return nil, err
	}

	return user, nil
}

func (u *users) FindById(ctx context.Context, id uuid.UUID) (*models.User, error) {
	user, err := u.repository.FindById(ctx, id)
	if err != nil {
		return nil, err
	}

	return user, nil
}

func (u *users) FindByLogin(ctx context.Context, login string) (*models.User, error) {
	user, err := u.repository.FindByLogin(ctx, login)
	if err != nil {
		return nil, err
	}

	return user, nil
}

func (u *users) FindByEmail(ctx context.Context, email string) (*models.User, error) {
	user, err := u.repository.FindByEmail(ctx, email)
	if err != nil {
		return nil, err
	}

	return user, nil
}
