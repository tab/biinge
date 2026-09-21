package jellyfin

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_ParseEvent(t *testing.T) {
	const body = `{"ItemType":"Episode","SaveReason":"PlaybackFinished","Played":true,"Provider_tvdb":"3254641","Provider_imdb":"tt1480055","Name":"Winter Is Coming","SeriesName":"Game of Thrones","SeasonNumber":1}`

	tests := []struct {
		name     string
		body     string
		expected *Event
		error    error
		wantErr  bool
	}{
		{
			name: "Reads the typed keys and keeps the raw body with the rest",
			body: body,
			expected: &Event{
				ItemType:     "Episode",
				SaveReason:   "PlaybackFinished",
				Played:       true,
				ProviderTvdb: "3254641",
				ProviderImdb: "tt1480055",
				Name:         "Winter Is Coming",
				Raw:          json.RawMessage(body),
			},
		},
		{
			name: "Keys match case-insensitively",
			body: `{"itemtype":"Movie","savereason":"TogglePlayed","played":true,"provider_TMDB":"603"}`,
			expected: &Event{
				ItemType:     "Movie",
				SaveReason:   "TogglePlayed",
				Played:       true,
				ProviderTmdb: "603",
				Raw:          json.RawMessage(`{"itemtype":"Movie","savereason":"TogglePlayed","played":true,"provider_TMDB":"603"}`),
			},
		},
		{
			name:     "Empty object is an event with nothing set",
			body:     `{}`,
			expected: &Event{Raw: json.RawMessage(`{}`)},
		},
		{
			name:  "Null is not an object",
			body:  `null`,
			error: ErrNotAnObject,
		},
		{
			name:  "Array is not an object",
			body:  `[{"ItemType":"Movie"}]`,
			error: ErrNotAnObject,
		},
		{
			name:  "Scalar is not an object",
			body:  `"Movie"`,
			error: ErrNotAnObject,
		},
		{
			name:    "Malformed JSON",
			body:    `{"ItemType":`,
			wantErr: true,
		},
		{
			name:    "Empty body",
			body:    ``,
			wantErr: true,
		},
		{
			name:    "Wrong type for a typed key",
			body:    `{"Played":"yes"}`,
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			event, err := ParseEvent(strings.NewReader(tt.body))

			switch {
			case tt.error != nil:
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, event)
			case tt.wantErr:
				require.Error(t, err)
				assert.Nil(t, event)
			default:
				require.NoError(t, err)
				assert.Equal(t, tt.expected, event)
			}
		})
	}
}

func Test_Event_Finished(t *testing.T) {
	tests := []struct {
		name     string
		event    Event
		expected bool
	}{
		{
			name:     "Playback finished",
			event:    Event{Played: true, SaveReason: SaveReasonPlaybackFinished},
			expected: true,
		},
		{
			name:     "Marked played by hand",
			event:    Event{Played: true, SaveReason: SaveReasonTogglePlayed},
			expected: true,
		},
		{
			name:     "Marked unplayed by hand",
			event:    Event{Played: false, SaveReason: SaveReasonTogglePlayed},
			expected: false,
		},
		{
			name:     "Progress save mid-play",
			event:    Event{Played: false, SaveReason: "PlaybackProgress"},
			expected: false,
		},
		{
			name:     "Progress save on an already played item",
			event:    Event{Played: true, SaveReason: "PlaybackProgress"},
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, tt.event.Finished())
		})
	}
}
