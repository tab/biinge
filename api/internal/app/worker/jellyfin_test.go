package worker

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"go.uber.org/fx/fxtest"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
)

// newTestJellyfinCfg is a config with Jellyfin and its sync on and a one-hour reconcile interval
func newTestJellyfinCfg() *config.Config {
	return &config.Config{
		AppEnv:   config.TestEnv,
		LogLevel: "info",
		Jellyfin: config.JellyfinConfig{
			BaseURL:           "http://jellyfin.test",
			SyncEnabled:       true,
			SyncInterval:      time.Hour,
			ReconcileInterval: time.Hour,
		},
	}
}

// jellyfinMovie is a read item for a movie with the given played flag
func jellyfinMovie(id string, tmdbId uint64, played bool) services.JellyfinItem {
	return services.JellyfinItem{
		Id: id,
		JellyfinChange: services.JellyfinChange{
			Kind:   services.PlayedMovie,
			TmdbId: tmdbId,
			Played: played,
		},
	}
}

func Test_JellyfinWorker_Start(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	disabled := newTestJellyfinCfg()
	disabled.Jellyfin.BaseURL = ""
	switchedOff := newTestJellyfinCfg()
	switchedOff.Jellyfin.SyncEnabled = false

	tests := []struct {
		name    string
		cfg     *config.Config
		running bool
	}{
		{
			name:    "Empty base URL with the sync enabled runs no pass",
			cfg:     disabled,
			running: false,
		},
		{
			name:    "Base URL with the sync switched off runs no pass",
			cfg:     switchedOff,
			running: false,
		},
		{
			name:    "Base URL with the sync enabled starts the loop",
			cfg:     newTestJellyfinCfg(),
			running: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			lifecycle := fxtest.NewLifecycle(t)
			// the mocks hold no expectations, so any pass fails the test
			w := NewJellyfinWorker(
				lifecycle,
				tt.cfg,
				repositories.NewMockIntegrationRepository(ctrl),
				services.NewMockLibrary(ctrl),
				services.NewMockJellyfinSync(ctrl),
				services.NewPlayedMemory(),
				logger.NewLogger(tt.cfg),
			)

			lifecycle.RequireStart()

			assert.Equal(t, tt.running, w.cancel != nil)

			lifecycle.RequireStop()

			select {
			case <-w.done:
			default:
				assert.Fail(t, "the worker did not stop")
			}
		})
	}
}

func Test_JellyfinWorker_SyncUsers(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	cfg := newTestJellyfinCfg()
	integrations := repositories.NewMockIntegrationRepository(ctrl)
	library := services.NewMockLibrary(ctrl)
	sync := services.NewMockJellyfinSync(ctrl)
	w := NewJellyfinWorker(fxtest.NewLifecycle(t), cfg, integrations, library, sync, services.NewPlayedMemory(), logger.NewLogger(cfg))

	failing := uuid.New()
	working := uuid.New()
	read := &services.JellyfinRead{
		Key:   services.PlayedKey{UserId: working, JellyfinUserId: "jf-user"},
		Began: time.Now(),
		Items: []services.JellyfinItem{jellyfinMovie("a", 1, true)},
	}

	tests := []struct {
		name   string
		before func()
	}{
		{
			name: "A failing user leaves the next user's pass alone",
			before: func() {
				integrations.EXPECT().ListUsers(ctx, models.JellyfinProvider).Return([]uuid.UUID{failing, working}, nil)
				gomock.InOrder(
					library.EXPECT().Played(ctx, failing).Return(nil, assert.AnError),
					library.EXPECT().Played(ctx, working).Return(read, nil),
					sync.EXPECT().Reconcile(ctx, read).Return(nil),
				)
			},
		},
		{
			name: "List failure runs no pass",
			before: func() {
				integrations.EXPECT().ListUsers(ctx, models.JellyfinProvider).Return(nil, assert.AnError)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			w.syncUsers(ctx)
		})
	}
}

func Test_JellyfinWorker_SyncUser(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	cfg := newTestJellyfinCfg()
	library := services.NewMockLibrary(ctrl)
	sync := services.NewMockJellyfinSync(ctrl)
	w := NewJellyfinWorker(
		fxtest.NewLifecycle(t),
		cfg,
		repositories.NewMockIntegrationRepository(ctrl),
		library,
		sync,
		services.NewPlayedMemory(),
		logger.NewLogger(cfg),
	)

	userId := uuid.New()
	key := services.PlayedKey{UserId: userId, JellyfinUserId: "jf-user"}
	otherKey := services.PlayedKey{UserId: userId, JellyfinUserId: "jf-other"}

	// a read that began after every write in a case, and one that was still running when a case's write landed
	after := time.Now().Add(time.Hour)
	during := time.Now().Add(-time.Hour)

	// a reconcile an interval ago is due, one just now is not
	due := time.Now().Add(-2 * time.Hour)
	recent := time.Now()

	aPlayed := jellyfinMovie("a", 1, true)
	aUnplayed := jellyfinMovie("a", 1, false)
	bPlayed := jellyfinMovie("b", 2, true)
	bUnplayed := jellyfinMovie("b", 2, false)
	cPlayed := jellyfinMovie("c", 3, true)

	// readOf is the user's read as the given Jellyfin user
	readOf := func(key services.PlayedKey, began time.Time, items ...services.JellyfinItem) *services.JellyfinRead {
		return &services.JellyfinRead{Key: key, Began: began, Items: items}
	}

	tests := []struct {
		name   string
		last   time.Time
		before func()
		key    services.PlayedKey
		// expected is the previous read after the pass (nil when there is none)
		expected   map[string]bool
		reconciled bool
		forgotten  bool
	}{
		{
			name: "First pass records the read and reconciles without applying",
			before: func() {
				read := readOf(key, after, aPlayed, bUnplayed)
				library.EXPECT().Played(ctx, userId).Return(read, nil)
				sync.EXPECT().Reconcile(ctx, read).Return(nil)
			},
			key:        key,
			expected:   map[string]bool{"a": true, "b": false},
			reconciled: true,
		},
		{
			name: "First pass whose reconcile fails keeps the read and no reconcile time",
			before: func() {
				read := readOf(key, after, aPlayed)
				library.EXPECT().Played(ctx, userId).Return(read, nil)
				sync.EXPECT().Reconcile(ctx, read).Return(assert.AnError)
			},
			key:      key,
			expected: map[string]bool{"a": true},
		},
		{
			name: "Played flip applies",
			last: recent,
			before: func() {
				w.memory.Replace(key, map[string]bool{"a": false}, after)
				library.EXPECT().Played(ctx, userId).Return(readOf(key, after, aPlayed), nil)
				sync.EXPECT().Apply(ctx, userId, aPlayed.JellyfinChange).Return(nil)
			},
			key:      key,
			expected: map[string]bool{"a": true},
		},
		{
			name: "Unplayed flip applies",
			last: recent,
			before: func() {
				w.memory.Replace(key, map[string]bool{"a": true}, after)
				library.EXPECT().Played(ctx, userId).Return(readOf(key, after, aUnplayed), nil)
				sync.EXPECT().Apply(ctx, userId, aUnplayed.JellyfinChange).Return(nil)
			},
			key:      key,
			expected: map[string]bool{"a": false},
		},
		{
			name: "Item new to the read counts as previously unplayed",
			last: recent,
			before: func() {
				w.memory.Replace(key, map[string]bool{}, after)
				library.EXPECT().Played(ctx, userId).Return(readOf(key, after, aPlayed, bUnplayed), nil)
				sync.EXPECT().Apply(ctx, userId, aPlayed.JellyfinChange).Return(nil)
			},
			key:      key,
			expected: map[string]bool{"a": true, "b": false},
		},
		{
			name: "Unchanged items apply nothing and an undue reconcile waits",
			last: recent,
			before: func() {
				w.memory.Replace(key, map[string]bool{"a": true, "b": false}, after)
				library.EXPECT().Played(ctx, userId).Return(readOf(key, after, aPlayed, bUnplayed), nil)
			},
			key:      key,
			expected: map[string]bool{"a": true, "b": false},
		},
		{
			name: "Failed apply keeps the item's previous flag and skips the due reconcile",
			last: due,
			before: func() {
				w.memory.Replace(key, map[string]bool{"a": false}, after)
				library.EXPECT().Played(ctx, userId).Return(readOf(key, after, aPlayed, bPlayed, cPlayed), nil)
				sync.EXPECT().Apply(ctx, userId, aPlayed.JellyfinChange).Return(assert.AnError)
				sync.EXPECT().Apply(ctx, userId, bPlayed.JellyfinChange).Return(assert.AnError)
				sync.EXPECT().Apply(ctx, userId, cPlayed.JellyfinChange).Return(nil)
			},
			key:      key,
			expected: map[string]bool{"a": false, "c": true},
		},
		{
			name: "Clean due pass reconciles",
			last: due,
			before: func() {
				w.memory.Replace(key, map[string]bool{"a": false}, after)
				read := readOf(key, after, aPlayed)
				library.EXPECT().Played(ctx, userId).Return(read, nil)
				gomock.InOrder(
					sync.EXPECT().Apply(ctx, userId, aPlayed.JellyfinChange).Return(nil),
					sync.EXPECT().Reconcile(ctx, read).Return(nil),
				)
			},
			key:        key,
			expected:   map[string]bool{"a": true},
			reconciled: true,
		},
		{
			name: "Failed reconcile keeps the last reconcile time",
			last: due,
			before: func() {
				w.memory.Replace(key, map[string]bool{"a": true}, after)
				read := readOf(key, after, aPlayed)
				library.EXPECT().Played(ctx, userId).Return(read, nil)
				sync.EXPECT().Reconcile(ctx, read).Return(assert.AnError)
			},
			key:      key,
			expected: map[string]bool{"a": true},
		},
		{
			name: "Jellyfin failure keeps the previous read and the reconcile time",
			last: due,
			before: func() {
				w.memory.Replace(key, map[string]bool{"a": true}, after)
				library.EXPECT().Played(ctx, userId).Return(nil, assert.AnError)
			},
			key:      key,
			expected: map[string]bool{"a": true},
		},
		{
			name: "No connection forgets the read and the reconcile time",
			last: recent,
			before: func() {
				w.memory.Replace(key, map[string]bool{"a": true}, after)
				library.EXPECT().Played(ctx, userId).Return(nil, nil)
			},
			key:       key,
			forgotten: true,
		},
		{
			name: "Reconnect as another Jellyfin user is a first pass",
			last: recent,
			before: func() {
				w.memory.Replace(key, map[string]bool{"a": false}, after)
				read := readOf(otherKey, after, aPlayed)
				library.EXPECT().Played(ctx, userId).Return(read, nil)
				sync.EXPECT().Reconcile(ctx, read).Return(nil)
			},
			key:        otherKey,
			expected:   map[string]bool{"a": true},
			reconciled: true,
		},
		{
			name: "Reconnect keeps a queued write that landed during the new user's first read",
			last: recent,
			before: func() {
				w.memory.Replace(key, map[string]bool{"a": false}, after)

				read := readOf(otherKey, during, aUnplayed)

				library.EXPECT().
					Played(ctx, userId).
					DoAndReturn(func(context.Context, uuid.UUID) (*services.JellyfinRead, error) {
						// the read as the new Jellyfin user began, then a queued write marked the item played
						w.memory.Record(otherKey, "a", true)

						return read, nil
					})
				sync.EXPECT().Reconcile(ctx, read).Return(nil)
			},
			key:        otherKey,
			expected:   map[string]bool{"a": true},
			reconciled: true,
		},
		{
			name: "User reversing a reconcile write before the next poll is applied",
			last: recent,
			before: func() {
				w.memory.Replace(key, map[string]bool{"a": false}, during)
				// the reconcile marked the item played
				w.memory.Record(key, "a", true)
				library.EXPECT().Played(ctx, userId).Return(readOf(key, after, aUnplayed), nil)
				sync.EXPECT().Apply(ctx, userId, aUnplayed.JellyfinChange).Return(nil)
			},
			key:      key,
			expected: map[string]bool{"a": false},
		},
		{
			name: "Queued write that succeeds and a later one that fails is no change",
			last: recent,
			before: func() {
				w.memory.Replace(key, map[string]bool{"a": false}, during)
				// the played write landed, the unplayed write after it failed and recorded nothing
				w.memory.Record(key, "a", true)
				library.EXPECT().Played(ctx, userId).Return(readOf(key, after, aPlayed), nil)
			},
			key:      key,
			expected: map[string]bool{"a": true},
		},
		{
			name: "Queued write that lands during the read is no change",
			last: recent,
			before: func() {
				w.memory.Replace(key, map[string]bool{"a": false}, during)
				library.EXPECT().
					Played(ctx, userId).
					DoAndReturn(func(context.Context, uuid.UUID) (*services.JellyfinRead, error) {
						// the read began, then the queued write marked the item played before it returned
						w.memory.Record(key, "a", true)

						return readOf(key, during, aUnplayed), nil
					})
			},
			key:      key,
			expected: map[string]bool{"a": true},
		},
		{
			name: "First pass keeps a queued write that landed during the read",
			before: func() {
				read := readOf(key, during, aUnplayed)

				library.EXPECT().
					Played(ctx, userId).
					DoAndReturn(func(context.Context, uuid.UUID) (*services.JellyfinRead, error) {
						// the read began, then the queued write marked the item played before it returned
						w.memory.Record(key, "a", true)

						return read, nil
					})
				sync.EXPECT().Reconcile(ctx, read).Return(nil)
			},
			key: key,
			// the next poll that reads the item played sees no change
			expected:   map[string]bool{"a": true},
			reconciled: true,
		},
		{
			name: "Queued write that lands while another change applies is no change",
			last: recent,
			before: func() {
				w.memory.Replace(key, map[string]bool{"a": false, "b": false}, during)
				library.EXPECT().Played(ctx, userId).Return(readOf(key, during, aPlayed, bPlayed), nil)
				sync.EXPECT().
					Apply(ctx, userId, aPlayed.JellyfinChange).
					DoAndReturn(func(context.Context, uuid.UUID, services.JellyfinChange) error {
						// the user marked and then unmarked b, and the unplayed write landed after the read
						w.memory.Record(key, "b", false)

						return nil
					})
			},
			key:      key,
			expected: map[string]bool{"a": true, "b": false},
		},
		{
			name: "Unclean pass keeps the queued writes that landed during the read",
			last: due,
			before: func() {
				w.memory.Replace(key, map[string]bool{"a": false, "b": false}, during)
				library.EXPECT().
					Played(ctx, userId).
					DoAndReturn(func(context.Context, uuid.UUID) (*services.JellyfinRead, error) {
						// the read began, then the queued write marked the item played before it returned
						w.memory.Record(key, "a", true)

						return readOf(key, during, aUnplayed, bPlayed), nil
					})
				sync.EXPECT().
					Apply(ctx, userId, bPlayed.JellyfinChange).
					DoAndReturn(func(context.Context, uuid.UUID, services.JellyfinChange) error {
						// a queued write for the same item lands while the change fails
						w.memory.Record(key, "b", true)

						return assert.AnError
					})
			},
			key:      key,
			expected: map[string]bool{"a": true, "b": true},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w.memory = services.NewPlayedMemory()
			w.reconciled = map[uuid.UUID]time.Time{}

			if !tt.last.IsZero() {
				w.reconciled[userId] = tt.last
			}

			tt.before()

			start := time.Now()

			w.syncUser(ctx, userId)

			previous, found := w.memory.Previous(tt.key)
			at, reconciled := w.reconciled[userId]

			if tt.forgotten {
				assert.False(t, found)
				assert.False(t, reconciled)

				return
			}

			assert.True(t, found)
			assert.Equal(t, tt.expected, previous)

			if tt.reconciled {
				assert.False(t, at.Before(start))

				return
			}

			assert.Equal(t, tt.last, at)
		})
	}
}

func Test_JellyfinWorker_SyncUser_RetriesAFailedChange(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	cfg := newTestJellyfinCfg()
	library := services.NewMockLibrary(ctrl)
	sync := services.NewMockJellyfinSync(ctrl)
	w := NewJellyfinWorker(
		fxtest.NewLifecycle(t),
		cfg,
		repositories.NewMockIntegrationRepository(ctrl),
		library,
		sync,
		services.NewPlayedMemory(),
		logger.NewLogger(cfg),
	)

	userId := uuid.New()
	key := services.PlayedKey{UserId: userId, JellyfinUserId: "jf-user"}
	played := jellyfinMovie("a", 1, true)
	first := &services.JellyfinRead{Key: key, Began: time.Now(), Items: []services.JellyfinItem{jellyfinMovie("a", 1, false)}}
	second := &services.JellyfinRead{Key: key, Began: time.Now(), Items: []services.JellyfinItem{played}}
	third := &services.JellyfinRead{Key: key, Began: time.Now(), Items: []services.JellyfinItem{played}}

	gomock.InOrder(
		library.EXPECT().Played(ctx, userId).Return(first, nil),
		sync.EXPECT().Reconcile(ctx, first).Return(nil),
		library.EXPECT().Played(ctx, userId).Return(second, nil),
		sync.EXPECT().Apply(ctx, userId, played.JellyfinChange).Return(assert.AnError),
		library.EXPECT().Played(ctx, userId).Return(third, nil),
		sync.EXPECT().Apply(ctx, userId, played.JellyfinChange).Return(nil),
	)

	w.syncUser(ctx, userId)
	w.syncUser(ctx, userId)
	w.syncUser(ctx, userId)
}
