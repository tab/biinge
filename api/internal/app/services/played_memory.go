package services

import (
	"sync"
	"time"

	"github.com/google/uuid"
)

// playedEntry is one Jellyfin item's previous played flag and when the API last wrote it (zero when it never did)
type playedEntry struct {
	played  bool
	written time.Time
}

// playedRead is a user's previous Jellyfin read and the Jellyfin user it belongs to (before the first read it holds only the API's writes)
type playedRead struct {
	jellyfinUserId string
	items          map[string]playedEntry
	read           bool
}

// PlayedKey names a previous read by its biinge user and the Jellyfin user it was read as
type PlayedKey struct {
	UserId         uuid.UUID
	JellyfinUserId string
}

// PlayedMemory keeps each user's previous Jellyfin played read in memory, with the API's own successful writes applied to it
type PlayedMemory interface {
	Previous(key PlayedKey) (map[string]bool, bool)
	Replace(key PlayedKey, read map[string]bool, began time.Time)
	Record(key PlayedKey, itemId string, played bool)
	Forget(userId uuid.UUID)
}

type playedMemory struct {
	mu    sync.Mutex
	users map[uuid.UUID]playedRead
}

func NewPlayedMemory() PlayedMemory {
	return &playedMemory{users: map[uuid.UUID]playedRead{}}
}

// Previous returns a copy of the user's previous read by item id (not found when there is none or it belongs to another Jellyfin user)
func (m *playedMemory) Previous(key PlayedKey) (map[string]bool, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()

	read, found := m.users[key.UserId]
	if !found || !read.read || read.jellyfinUserId != key.JellyfinUserId {
		return nil, false
	}

	items := make(map[string]bool, len(read.items))
	for id, entry := range read.items {
		items[id] = entry.played
	}

	return items, true
}

// Replace keeps a new read as the user's previous one (an item the API wrote after the read began keeps the written flag, and items the read lacks go away)
func (m *playedMemory) Replace(key PlayedKey, read map[string]bool, began time.Time) {
	m.mu.Lock()
	defer m.mu.Unlock()

	// a read of another Jellyfin user holds nothing this one keeps
	var previous map[string]playedEntry
	if current, found := m.users[key.UserId]; found && current.jellyfinUserId == key.JellyfinUserId {
		previous = current.items
	}

	items := make(map[string]playedEntry, len(read))
	for id, played := range read {
		// the read may have missed a write that landed while it ran
		if entry := previous[id]; entry.written.After(began) {
			items[id] = entry
			continue
		}

		items[id] = playedEntry{played: played}
	}

	m.users[key.UserId] = playedRead{jellyfinUserId: key.JellyfinUserId, items: items, read: true}
}

// Record sets an item's previous state to a successful API write (kept before the first read too, so the first read cannot miss it)
func (m *playedMemory) Record(key PlayedKey, itemId string, played bool) {
	m.mu.Lock()
	defer m.mu.Unlock()

	read, found := m.users[key.UserId]
	if !found || read.jellyfinUserId != key.JellyfinUserId {
		// a write as another Jellyfin user means a reconnect, so the old user's read and writes go away and the next pass is a first pass
		read = playedRead{jellyfinUserId: key.JellyfinUserId, items: map[string]playedEntry{}}
		m.users[key.UserId] = read
	}

	read.items[itemId] = playedEntry{played: played, written: time.Now()}
}

// Forget drops the user's previous read
func (m *playedMemory) Forget(userId uuid.UUID) {
	m.mu.Lock()
	defer m.mu.Unlock()

	delete(m.users, userId)
}
