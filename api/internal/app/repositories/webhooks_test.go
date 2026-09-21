package repositories

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/app/models"
)

func Test_WebhookRepository_Create(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewWebhookRepository(client)
	userID := newProgressTestUser(t, client, "integr.webhook")

	link, err := NewIntegrationRepository(client).Upsert(ctx, &models.Integration{
		UserId:    userID,
		Provider:  models.JellyfinProvider,
		TokenHash: "f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6",
	})
	require.NoError(t, err)

	tests := []struct {
		name    string
		payload json.RawMessage
		status  models.WebhookStatus
		error   string
	}{
		{
			name:    "Stores the payload and status",
			payload: json.RawMessage(`{"ItemType":"Movie","Provider_tmdb":"603","Extra":true}`),
			status:  models.WebhookStatusMarked,
		},
		{
			name:    "Stores the error text",
			payload: json.RawMessage(`{"ItemType":"Episode"}`),
			status:  models.WebhookStatusUnresolved,
			error:   "no provider id",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.NoError(t, repository.Create(ctx, &models.Webhook{
				IntegrationId: link.ID,
				Payload:       tt.payload,
				Status:        tt.status,
				Error:         tt.error,
			}))

			var (
				payload []byte
				status  string
				reason  *string
			)

			err := client.Db().QueryRow(ctx,
				`SELECT payload, status, error FROM webhooks WHERE integration_id = $1 ORDER BY created_at DESC LIMIT 1`, link.ID,
			).Scan(&payload, &status, &reason)
			require.NoError(t, err)

			assert.JSONEq(t, string(tt.payload), string(payload))
			assert.Equal(t, string(tt.status), status)

			if tt.error == "" {
				assert.Nil(t, reason)
			} else {
				require.NotNil(t, reason)
				assert.Equal(t, tt.error, *reason)
			}
		})
	}

	t.Run("Unknown status is rejected by the enum", func(t *testing.T) {
		require.Error(t, repository.Create(ctx, &models.Webhook{
			IntegrationId: link.ID,
			Payload:       json.RawMessage(`{}`),
			Status:        models.WebhookStatus("skipped"),
		}))
	})

	t.Run("Unknown integration fails foreign key", func(t *testing.T) {
		require.Error(t, repository.Create(ctx, &models.Webhook{
			IntegrationId: uuid.New(),
			Payload:       json.RawMessage(`{}`),
			Status:        models.WebhookStatusIgnored,
		}))
	})
}
