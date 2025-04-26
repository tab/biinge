package repositories

import (
	"context"

	"github.com/google/uuid"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/app/repositories/postgres"
)

type UserRepository interface {
	Create(ctx context.Context, params db.CreateUserParams) (*models.User, error)
	Update(ctx context.Context, params db.UpdateUserParams) (*models.User, error)
	FindById(ctx context.Context, id uuid.UUID) (*models.User, error)
	FindByLogin(ctx context.Context, login string) (*models.User, error)
	FindByEmail(ctx context.Context, email string) (*models.User, error)
}

type user struct {
	client postgres.Postgres
}

func NewUserRepository(client postgres.Postgres) UserRepository {
	return &user{client: client}
}

func (u *user) Create(ctx context.Context, params db.CreateUserParams) (*models.User, error) {
	tx, err := u.client.Db().Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	q := u.client.Queries().WithTx(tx)

	result, err := q.CreateUser(ctx, db.CreateUserParams{
		Login:             params.Login,
		Email:             params.Email,
		EncryptedPassword: params.EncryptedPassword,
		FirstName:         params.FirstName,
		LastName:          params.LastName,
		Appearance:        params.Appearance,
	})
	if err != nil {
		return nil, err
	}

	return &models.User{
		ID:         result.ID,
		Login:      result.Login,
		Email:      result.Email,
		FirstName:  result.FirstName,
		LastName:   result.LastName,
		Appearance: result.Appearance,
	}, tx.Commit(ctx)
}

func (u *user) Update(ctx context.Context, params db.UpdateUserParams) (*models.User, error) {
	tx, err := u.client.Db().Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	q := u.client.Queries().WithTx(tx)

	result, err := q.UpdateUser(ctx, db.UpdateUserParams{
		ID:         params.ID,
		FirstName:  params.FirstName,
		LastName:   params.LastName,
		Appearance: params.Appearance,
	})
	if err != nil {
		return nil, err
	}

	return &models.User{
		ID:         result.ID,
		Login:      result.Login,
		Email:      result.Email,
		FirstName:  result.FirstName,
		LastName:   result.LastName,
		Appearance: result.Appearance,
	}, tx.Commit(ctx)
}

func (u *user) FindById(ctx context.Context, id uuid.UUID) (*models.User, error) {
	result, err := u.client.Queries().FindUserById(ctx, id)
	if err != nil {
		return nil, err
	}

	return &models.User{
		ID:         result.ID,
		Login:      result.Login,
		Email:      result.Email,
		FirstName:  result.FirstName,
		LastName:   result.LastName,
		Appearance: result.Appearance,
	}, nil
}

func (u *user) FindByLogin(ctx context.Context, login string) (*models.User, error) {
	result, err := u.client.Queries().FindUserByLogin(ctx, login)
	if err != nil {
		return nil, err
	}

	return &models.User{
		ID:                result.ID,
		Login:             result.Login,
		Email:             result.Email,
		EncryptedPassword: result.EncryptedPassword,
		FirstName:         result.FirstName,
		LastName:          result.LastName,
		Appearance:        result.Appearance,
	}, nil
}

func (u *user) FindByEmail(ctx context.Context, email string) (*models.User, error) {
	result, err := u.client.Queries().FindUserByEmail(ctx, email)
	if err != nil {
		return nil, err
	}

	return &models.User{
		ID:                result.ID,
		Login:             result.Login,
		Email:             result.Email,
		EncryptedPassword: result.EncryptedPassword,
		FirstName:         result.FirstName,
		LastName:          result.LastName,
		Appearance:        result.Appearance,
	}, nil
}
