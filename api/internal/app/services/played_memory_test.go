package services

import (
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
)

func Test_PlayedMemory_Previous(t *testing.T) {
	userId := uuid.New()
	key := PlayedKey{UserId: userId, JellyfinUserId: "jf-user"}
	other := PlayedKey{UserId: userId, JellyfinUserId: "jf-other"}

	tests := []struct {
		name     string
		before   func(memory PlayedMemory)
		expected map[string]bool
		found    bool
	}{
		{
			name:   "No previous read",
			before: func(PlayedMemory) {},
		},
		{
			name: "Same Jellyfin user",
			before: func(memory PlayedMemory) {
				memory.Replace(key, map[string]bool{"movie": true, "episode": false}, time.Time{})
			},
			expected: map[string]bool{"movie": true, "episode": false},
			found:    true,
		},
		{
			name: "Another Jellyfin user",
			before: func(memory PlayedMemory) {
				memory.Replace(other, map[string]bool{"movie": true}, time.Time{})
			},
		},
		{
			name: "Another biinge user",
			before: func(memory PlayedMemory) {
				memory.Replace(PlayedKey{UserId: uuid.New(), JellyfinUserId: "jf-user"}, map[string]bool{"movie": true}, time.Time{})
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			memory := NewPlayedMemory()
			tt.before(memory)

			result, found := memory.Previous(key)

			assert.Equal(t, tt.found, found)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func Test_PlayedMemory_Copies(t *testing.T) {
	userId := uuid.New()
	key := PlayedKey{UserId: userId, JellyfinUserId: "jf-user"}
	memory := NewPlayedMemory()
	read := map[string]bool{"movie": true}

	memory.Replace(key, read, time.Time{})
	read["movie"] = false
	read["episode"] = true

	previous, _ := memory.Previous(key)
	previous["movie"] = false

	result, found := memory.Previous(key)

	assert.True(t, found)
	assert.Equal(t, map[string]bool{"movie": true}, result)
}

func Test_PlayedMemory_Replace(t *testing.T) {
	userId := uuid.New()
	key := PlayedKey{UserId: userId, JellyfinUserId: "jf-user"}
	other := PlayedKey{UserId: userId, JellyfinUserId: "jf-other"}
	// Record stamps its write with the current time, so the read begins an hour either side of it
	before := time.Now().Add(-time.Hour)
	after := time.Now().Add(time.Hour)

	tests := []struct {
		name     string
		before   func(memory PlayedMemory)
		read     map[string]bool
		began    time.Time
		expected map[string]bool
	}{
		{
			name:     "First read is kept",
			before:   func(PlayedMemory) {},
			read:     map[string]bool{"movie": true, "episode": false},
			began:    before,
			expected: map[string]bool{"movie": true, "episode": false},
		},
		{
			name: "New read takes each item's flag",
			before: func(memory PlayedMemory) {
				memory.Replace(key, map[string]bool{"movie": true, "episode": false}, time.Time{})
			},
			read:     map[string]bool{"movie": false, "episode": true},
			began:    before,
			expected: map[string]bool{"movie": false, "episode": true},
		},
		{
			name: "Write after the read began keeps the written flag",
			before: func(memory PlayedMemory) {
				memory.Replace(key, map[string]bool{"movie": false, "episode": false}, time.Time{})
				memory.Record(key, "movie", true)
			},
			read:     map[string]bool{"movie": false, "episode": true},
			began:    before,
			expected: map[string]bool{"movie": true, "episode": true},
		},
		{
			name: "Write before the read began takes the read's flag",
			before: func(memory PlayedMemory) {
				memory.Replace(key, map[string]bool{"movie": false}, time.Time{})
				memory.Record(key, "movie", true)
			},
			read:     map[string]bool{"movie": false},
			began:    after,
			expected: map[string]bool{"movie": false},
		},
		{
			name: "Kept write gives way to a read that began after it",
			before: func(memory PlayedMemory) {
				memory.Replace(key, map[string]bool{"movie": false}, time.Time{})
				memory.Record(key, "movie", true)
				memory.Replace(key, map[string]bool{"movie": false}, before)
			},
			read:     map[string]bool{"movie": false},
			began:    after,
			expected: map[string]bool{"movie": false},
		},
		{
			name: "Items the read lacks go away",
			before: func(memory PlayedMemory) {
				memory.Replace(key, map[string]bool{"movie": true, "episode": true}, time.Time{})
				memory.Record(key, "episode", false)
			},
			read:     map[string]bool{"movie": true},
			began:    before,
			expected: map[string]bool{"movie": true},
		},
		{
			name: "First read keeps a write that landed while it ran",
			before: func(memory PlayedMemory) {
				// the first read captured the movie unplayed, then a played write succeeded before it returned
				memory.Record(key, "movie", true)
			},
			read:     map[string]bool{"movie": false, "episode": false},
			began:    before,
			expected: map[string]bool{"movie": true, "episode": false},
		},
		{
			name: "First read takes its flag over a write from before it began",
			before: func(memory PlayedMemory) {
				memory.Record(key, "movie", true)
			},
			read:     map[string]bool{"movie": false},
			began:    after,
			expected: map[string]bool{"movie": false},
		},
		{
			name: "Another Jellyfin user's write drops the writes waiting for a first read",
			before: func(memory PlayedMemory) {
				memory.Record(key, "movie", true)
				memory.Record(other, "episode", true)
			},
			read:     map[string]bool{"movie": false, "episode": false},
			began:    before,
			expected: map[string]bool{"movie": false, "episode": false},
		},
		{
			name: "Reconnect keeps a write that landed during the new user's first read",
			before: func(memory PlayedMemory) {
				memory.Replace(other, map[string]bool{"movie": false, "episode": true}, time.Time{})
				memory.Record(key, "movie", true)
			},
			read:     map[string]bool{"movie": false, "episode": false},
			began:    before,
			expected: map[string]bool{"movie": true, "episode": false},
		},
		{
			name: "Another Jellyfin user's writes are not kept",
			before: func(memory PlayedMemory) {
				memory.Replace(other, map[string]bool{"movie": false}, time.Time{})
				memory.Record(other, "movie", true)
			},
			read:     map[string]bool{"movie": false},
			began:    before,
			expected: map[string]bool{"movie": false},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			memory := NewPlayedMemory()
			tt.before(memory)

			memory.Replace(key, tt.read, tt.began)

			result, found := memory.Previous(key)

			assert.True(t, found)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func Test_PlayedMemory_Record(t *testing.T) {
	userId := uuid.New()
	key := PlayedKey{UserId: userId, JellyfinUserId: "jf-user"}
	other := PlayedKey{UserId: userId, JellyfinUserId: "jf-other"}

	tests := []struct {
		name     string
		before   func(memory PlayedMemory)
		lookup   PlayedKey
		expected map[string]bool
		found    bool
	}{
		{
			// the write waits for the first read, so a first pass still finds no previous read
			name:   "Without a previous read is not found",
			before: func(PlayedMemory) {},
			lookup: key,
		},
		{
			// a write as another Jellyfin user means a reconnect, so the old user's read goes away
			name: "Drops another Jellyfin user's read",
			before: func(memory PlayedMemory) {
				memory.Replace(other, map[string]bool{"movie": false}, time.Time{})
			},
			lookup: other,
		},
		{
			name: "Sets the item's flag",
			before: func(memory PlayedMemory) {
				memory.Replace(key, map[string]bool{"movie": false, "episode": false}, time.Time{})
			},
			lookup:   key,
			expected: map[string]bool{"movie": true, "episode": false},
			found:    true,
		},
		{
			name: "Adds an item the read lacked",
			before: func(memory PlayedMemory) {
				memory.Replace(key, map[string]bool{"episode": false}, time.Time{})
			},
			lookup:   key,
			expected: map[string]bool{"movie": true, "episode": false},
			found:    true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			memory := NewPlayedMemory()
			tt.before(memory)

			memory.Record(key, "movie", true)

			result, found := memory.Previous(tt.lookup)

			assert.Equal(t, tt.found, found)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func Test_PlayedMemory_Forget(t *testing.T) {
	userId := uuid.New()
	key := PlayedKey{UserId: userId, JellyfinUserId: "jf-user"}
	otherKey := PlayedKey{UserId: uuid.New(), JellyfinUserId: "jf-other"}
	memory := NewPlayedMemory()

	memory.Replace(key, map[string]bool{"movie": true}, time.Time{})
	memory.Replace(otherKey, map[string]bool{"movie": false}, time.Time{})

	memory.Forget(userId)

	result, found := memory.Previous(key)
	assert.False(t, found)
	assert.Nil(t, result)

	other, found := memory.Previous(otherKey)
	assert.True(t, found)
	assert.Equal(t, map[string]bool{"movie": false}, other)
}

func Test_PlayedMemory_Concurrent(t *testing.T) {
	userId := uuid.New()
	key := PlayedKey{UserId: userId, JellyfinUserId: "jf-user"}
	memory := NewPlayedMemory()
	memory.Replace(key, map[string]bool{}, time.Time{})

	var wg sync.WaitGroup

	// the race detector fails the run if any two of these touch the store unguarded
	for i := range 8 {
		item := fmt.Sprintf("item-%d", i)

		wg.Go(func() {
			for range 100 {
				memory.Record(key, item, true)
				memory.Replace(key, map[string]bool{item: false}, time.Now())
				memory.Previous(key)
				memory.Forget(uuid.New())
			}
		})
	}

	wg.Wait()

	_, found := memory.Previous(key)
	assert.True(t, found)
}
