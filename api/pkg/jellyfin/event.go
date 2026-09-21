package jellyfin

import (
	"bytes"
	"encoding/json"
	"io"
)

// Item types and user-data save reasons the Webhook plugin sends on a "User Data Saved" event
const (
	ItemTypeMovie   = "Movie"
	ItemTypeEpisode = "Episode"

	SaveReasonPlaybackFinished = "PlaybackFinished"
	SaveReasonTogglePlayed     = "TogglePlayed"
)

// Event is the subset of a Webhook plugin event a consumer reads (keys match case-insensitively; the plugin lowercases provider names)
type Event struct {
	ItemType     string `json:"ItemType"`
	SaveReason   string `json:"SaveReason"`
	Played       bool   `json:"Played"`
	ProviderTmdb string `json:"Provider_tmdb"`
	ProviderTvdb string `json:"Provider_tvdb"`
	ProviderImdb string `json:"Provider_imdb"`
	Name         string `json:"Name"`

	// Raw is the body as received, so a consumer can keep every key the plugin sent
	Raw json.RawMessage `json:"-"`
}

// ParseEvent reads a plugin request body and requires a JSON object
func ParseEvent(body io.Reader) (*Event, error) {
	raw, err := io.ReadAll(body)
	if err != nil {
		return nil, err
	}

	// one answer for null, arrays and scalars instead of the decoder's per-type messages
	if !bytes.HasPrefix(bytes.TrimSpace(raw), []byte("{")) {
		return nil, ErrNotAnObject
	}

	var event Event
	if err = json.Unmarshal(raw, &event); err != nil {
		return nil, err
	}

	event.Raw = raw

	return &event, nil
}

// Finished reports whether the event records a completed play or a manual played mark (the saves that carry a watched state)
func (e *Event) Finished() bool {
	return e.Played && (e.SaveReason == SaveReasonPlaybackFinished || e.SaveReason == SaveReasonTogglePlayed)
}
