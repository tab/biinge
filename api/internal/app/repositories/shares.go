package repositories

import (
	"context"

	"github.com/google/uuid"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/app/repositories/postgres"
)

// shareLifetimeDays is how long a share lives without a visit
const shareLifetimeDays = 30

type ShareRepository interface {
	Upsert(ctx context.Context, params *models.Share) (*models.Share, error)
	FindLive(ctx context.Context, id uuid.UUID) (*models.Share, error)
	TouchVisit(ctx context.Context, id uuid.UUID) error
	DeleteExpired(ctx context.Context) (int64, error)
}

type share struct {
	client postgres.Postgres
}

func NewShareRepository(client postgres.Postgres) ShareRepository {
	return &share{client: client}
}

// Upsert stores the user's share of a title, or extends the one they already have (same id)
func (s *share) Upsert(ctx context.Context, params *models.Share) (*models.Share, error) {
	result, err := s.client.Queries().UpsertShare(ctx, db.UpsertShareParams{
		UserID:   params.UserId,
		Type:     db.ShareType(params.Type),
		ObjectID: params.ObjectId,
	})
	if err != nil {
		return nil, err
	}

	return shareFromRow(result), nil
}

// FindLive returns a share visited within its lifetime, pgx.ErrNoRows when none
func (s *share) FindLive(ctx context.Context, id uuid.UUID) (*models.Share, error) {
	result, err := s.client.Queries().FindLiveShare(ctx, db.FindLiveShareParams{
		ID:           id,
		LifetimeDays: shareLifetimeDays,
	})
	if err != nil {
		return nil, err
	}

	return shareFromRow(result), nil
}

// TouchVisit moves the share's visited_at to now (skipped while the stored visit is under a day old)
func (s *share) TouchVisit(ctx context.Context, id uuid.UUID) error {
	return s.client.Queries().TouchShareVisit(ctx, id)
}

// DeleteExpired removes every share not visited within its lifetime and returns how many it removed
func (s *share) DeleteExpired(ctx context.Context) (int64, error) {
	return s.client.Queries().DeleteExpiredShares(ctx, shareLifetimeDays)
}

// shareFromRow maps a stored row to the model
func shareFromRow(row db.Share) *models.Share {
	return &models.Share{
		ID:        row.ID,
		Type:      models.ShareType(row.Type),
		UserId:    row.UserID,
		ObjectId:  row.ObjectID,
		VisitedAt: row.VisitedAt.Time,
		CreatedAt: row.CreatedAt.Time,
		UpdatedAt: row.UpdatedAt.Time,
	}
}
