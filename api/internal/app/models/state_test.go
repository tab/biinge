package models

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func Test_StateType_String(t *testing.T) {
	assert.Equal(t, "want", StateTypeWant.String())
	assert.Equal(t, "watching", StateTypeWatching.String())
	assert.Equal(t, "watched", StateTypeWatched.String())
	assert.Equal(t, "none", StateTypeNone.String())
}

func Test_NewMovieListState(t *testing.T) {
	cases := []struct {
		name  string
		value string
		want  StateType
	}{
		{
			name:  "watched is browsable",
			value: "watched",
			want:  StateTypeWatched,
		},
		{
			name:  "want is the default",
			value: "want",
			want:  StateTypeWant,
		},
		{
			name:  "an empty filter falls back to want",
			value: "",
			want:  StateTypeWant,
		},
		{
			name:  "watching is not a movie state",
			value: "watching",
			want:  StateTypeWant,
		},
		{
			name:  "an unknown filter falls back to want",
			value: "somewhere-in-between",
			want:  StateTypeWant,
		},
	}

	for _, tt := range cases {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, NewMovieListState(tt.value))
		})
	}
}

func Test_NewSeriesListState(t *testing.T) {
	cases := []struct {
		name  string
		value string
		want  StateType
	}{
		{
			name:  "watching is browsable",
			value: "watching",
			want:  StateTypeWatching,
		},
		{
			name:  "watched is browsable",
			value: "watched",
			want:  StateTypeWatched,
		},
		{
			name:  "want is the default",
			value: "want",
			want:  StateTypeWant,
		},
		{
			name:  "an empty filter falls back to want",
			value: "",
			want:  StateTypeWant,
		},
		{
			name:  "none is not browsable",
			value: "none",
			want:  StateTypeWant,
		},
		{
			name:  "an unknown filter falls back to want",
			value: "binged",
			want:  StateTypeWant,
		},
	}

	for _, tt := range cases {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, NewSeriesListState(tt.value))
		})
	}
}
