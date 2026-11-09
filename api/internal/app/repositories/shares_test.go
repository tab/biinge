package repositories

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories/postgres"
)

// ageShare moves a share's visited_at and updated_at back by age
func ageShare(t *testing.T, client postgres.Postgres, id uuid.UUID, age time.Duration) {
	t.Helper()

	_, err := client.Db().Exec(
		context.Background(),
		"UPDATE shares SET visited_at = $1, updated_at = $1 WHERE id = $2",
		time.Now().Add(-age), id,
	)
	require.NoError(t, err)
}

// shareExists reports whether a share row is stored, live or not
func shareExists(t *testing.T, client postgres.Postgres, id uuid.UUID) bool {
	t.Helper()

	var exists bool

	err := client.Db().QueryRow(context.Background(), "SELECT EXISTS (SELECT 1 FROM shares WHERE id = $1)", id).Scan(&exists)
	require.NoError(t, err)

	return exists
}

func Test_ShareRepository_Upsert(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewShareRepository(client)
	userID := newProgressTestUser(t, client, "share.upsert")
	otherID := newProgressTestUser(t, client, "share.upsert.other")

	first, err := repository.Upsert(ctx, &models.Share{
		UserId:   userID,
		Type:     models.ShareTypeMovie,
		ObjectId: 900001,
	})
	require.NoError(t, err)
	ageShare(t, client, first.ID, 48*time.Hour)

	tests := []struct {
		name   string
		params *models.Share
		sameID bool
		fails  bool
	}{
		{
			name: "Re-share keeps the id",
			params: &models.Share{
				UserId:   userID,
				Type:     models.ShareTypeMovie,
				ObjectId: 900001,
			},
			sameID: true,
		},
		{
			name: "Another type with the same object id is a new share",
			params: &models.Share{
				UserId:   userID,
				Type:     models.ShareTypeTv,
				ObjectId: 900001,
			},
		},
		{
			name: "Another user is a new share",
			params: &models.Share{
				UserId:   otherID,
				Type:     models.ShareTypeMovie,
				ObjectId: 900001,
			},
		},
		{
			name: "Unknown user is an error",
			params: &models.Share{
				UserId:   uuid.MustParse("00000000-0000-0000-0000-00000000dead"),
				Type:     models.ShareTypeMovie,
				ObjectId: 900001,
			},
			fails: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := repository.Upsert(ctx, tt.params)

			if tt.fails {
				require.Error(t, err)
				assert.Nil(t, result)

				return
			}

			require.NoError(t, err)
			assert.Equal(t, tt.params.UserId, result.UserId)
			assert.Equal(t, tt.params.Type, result.Type)
			assert.Equal(t, tt.params.ObjectId, result.ObjectId)
			assert.WithinDuration(t, time.Now(), result.VisitedAt, time.Minute)
			assert.WithinDuration(t, time.Now(), result.UpdatedAt, time.Minute)

			if tt.sameID {
				assert.Equal(t, first.ID, result.ID)
				assert.Equal(t, first.CreatedAt, result.CreatedAt)

				return
			}

			assert.NotEqual(t, first.ID, result.ID)
		})
	}
}

func Test_ShareRepository_FindLive(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewShareRepository(client)
	userID := newProgressTestUser(t, client, "share.find")

	tests := []struct {
		name  string
		age   time.Duration
		error error
	}{
		{
			name: "Fresh share is found",
		},
		{
			name: "Share visited 29 days ago is found",
			age:  29 * 24 * time.Hour,
		},
		{
			name:  "Share visited 31 days ago is no rows",
			age:   31 * 24 * time.Hour,
			error: pgx.ErrNoRows,
		},
	}

	for i, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			created, err := repository.Upsert(ctx, &models.Share{
				UserId:   userID,
				Type:     models.ShareTypeGame,
				ObjectId: uint64(900100 + i),
			})
			require.NoError(t, err)
			ageShare(t, client, created.ID, tt.age)

			result, err := repository.FindLive(ctx, created.ID)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, result)

				return
			}

			require.NoError(t, err)
			assert.Equal(t, created.ID, result.ID)
			assert.Equal(t, models.ShareTypeGame, result.Type)
			assert.Equal(t, uint64(900100+i), result.ObjectId)
		})
	}

	t.Run("Unknown id is no rows", func(t *testing.T) {
		result, err := repository.FindLive(ctx, uuid.New())

		require.ErrorIs(t, err, pgx.ErrNoRows)
		assert.Nil(t, result)
	})
}

func Test_ShareRepository_TouchVisit(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewShareRepository(client)
	userID := newProgressTestUser(t, client, "share.touch")

	tests := []struct {
		name  string
		age   time.Duration
		moved bool
	}{
		{
			name: "Visit under a day old is left as it is",
			age:  2 * time.Hour,
		},
		{
			name:  "Visit over a day old moves to now",
			age:   48 * time.Hour,
			moved: true,
		},
	}

	for i, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			created, err := repository.Upsert(ctx, &models.Share{
				UserId:   userID,
				Type:     models.ShareTypeMovie,
				ObjectId: uint64(900200 + i),
			})
			require.NoError(t, err)
			ageShare(t, client, created.ID, tt.age)

			err = repository.TouchVisit(ctx, created.ID)

			require.NoError(t, err)
			result, err := repository.FindLive(ctx, created.ID)
			require.NoError(t, err)

			if tt.moved {
				assert.WithinDuration(t, time.Now(), result.VisitedAt, time.Minute)

				return
			}

			assert.WithinDuration(t, time.Now().Add(-tt.age), result.VisitedAt, time.Minute)
		})
	}
}

func Test_ShareRepository_DeleteExpired(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewShareRepository(client)
	userID := newProgressTestUser(t, client, "share.expire")

	tests := []struct {
		name string
		age  time.Duration
		kept bool
	}{
		{
			name: "Share visited 29 days ago is kept",
			age:  29 * 24 * time.Hour,
			kept: true,
		},
		{
			name: "Share visited 31 days ago is deleted",
			age:  31 * 24 * time.Hour,
		},
	}

	ids := make([]uuid.UUID, len(tests))
	for i, tt := range tests {
		created, err := repository.Upsert(ctx, &models.Share{
			UserId:   userID,
			Type:     models.ShareTypeTv,
			ObjectId: uint64(900300 + i),
		})
		require.NoError(t, err)
		ageShare(t, client, created.ID, tt.age)
		ids[i] = created.ID
	}

	// other tests leave their own rows in the shared database, so the count is a lower bound
	deleted, err := repository.DeleteExpired(ctx)
	require.NoError(t, err)
	assert.GreaterOrEqual(t, deleted, int64(1))

	for i, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.kept, shareExists(t, client, ids[i]))
		})
	}
}

func Test_ShareRepository_UserDeleteCascades(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewShareRepository(client)
	userID := newProgressTestUser(t, client, "share.cascade")

	created, err := repository.Upsert(ctx, &models.Share{
		UserId:   userID,
		Type:     models.ShareTypeGame,
		ObjectId: 900400,
	})
	require.NoError(t, err)

	_, err = client.Db().Exec(ctx, "DELETE FROM users WHERE id = $1", userID)
	require.NoError(t, err)

	assert.False(t, shareExists(t, client, created.ID))
}
