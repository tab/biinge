package serializers

import (
	"io"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
)

func Test_MarkShowRequest_Validate(t *testing.T) {
	tests := []struct {
		name     string
		body     io.Reader
		expected error
		wantErr  bool
	}{
		{
			name:     "Success",
			body:     strings.NewReader(`{ "series": { "title": "Show" }, "seasons": [] }`),
			expected: nil,
		},
		{
			name:     "Empty series title",
			body:     strings.NewReader(`{ "series": { "title": "" }, "seasons": [] }`),
			expected: errors.ErrEmptyTitle,
		},
		{
			name:     "Whitespace series title",
			body:     strings.NewReader(`{ "series": { "title": "   " }, "seasons": [] }`),
			expected: errors.ErrEmptyTitle,
		},
		{
			name:    "Malformed JSON",
			body:    strings.NewReader(`{ invalid`),
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var params MarkShowRequestSerializer

			err := params.Validate(tt.body)

			if tt.wantErr {
				require.Error(t, err)
				return
			}

			assert.Equal(t, tt.expected, err)
		})
	}
}

func Test_MarkShowRequest_ToInput(t *testing.T) {
	t.Run("With seasons", func(t *testing.T) {
		params := MarkShowRequestSerializer{
			Series: ProgressSeriesSerializer{
				Title:         " Show ",
				PosterPath:    "/poster.jpg",
				SeasonsCount:  1,
				EpisodesCount: 2,
				Status:        "Ended",
			},
			Seasons: []ProgressSeasonSerializer{
				{
					Id:            1,
					Title:         "Season 1",
					Number:        1,
					EpisodesCount: 2,
					Episodes: []ProgressEpisodeSerializer{
						{Id: 10, Title: "Ep1", Runtime: 20, AirDate: "2020-01-01"},
						{Id: 11, Title: "Ep2", Runtime: 25, AirDate: ""},
					},
				},
			},
		}

		expected := models.ShowInput{
			Series: models.SeriesInput{
				TmdbId:        123,
				Title:         "Show",
				PosterPath:    "/poster.jpg",
				SeasonsCount:  1,
				EpisodesCount: 2,
				Status:        "Ended",
			},
			Seasons: []models.SeasonInput{
				{
					TmdbId:        1,
					Title:         "Season 1",
					Number:        1,
					EpisodesCount: 2,
					Episodes: []models.EpisodeInput{
						{TmdbId: 10, Title: "Ep1", Runtime: 20, AirAt: time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)},
						{TmdbId: 11, Title: "Ep2", Runtime: 25, AirAt: time.Time{}},
					},
				},
			},
		}

		assert.Equal(t, expected, params.ToInput(123))
	})

	t.Run("No seasons", func(t *testing.T) {
		params := MarkShowRequestSerializer{
			Series: ProgressSeriesSerializer{Title: "Show"},
		}

		result := params.ToInput(123)

		assert.Equal(t, "Show", result.Series.Title)
		assert.Equal(t, []models.SeasonInput{}, result.Seasons)
	})
}

func Test_MarkSeasonRequest_Validate(t *testing.T) {
	tests := []struct {
		name     string
		body     io.Reader
		expected error
		wantErr  bool
	}{
		{
			name:     "Success",
			body:     strings.NewReader(`{ "series": { "title": "Show" }, "season": { "title": "Season 1" }, "episodes": [] }`),
			expected: nil,
		},
		{
			name:     "Empty series title",
			body:     strings.NewReader(`{ "series": { "title": "" }, "season": { "title": "Season 1" }, "episodes": [] }`),
			expected: errors.ErrEmptyTitle,
		},
		{
			name:     "Whitespace series title",
			body:     strings.NewReader(`{ "series": { "title": "   " }, "season": { "title": "Season 1" }, "episodes": [] }`),
			expected: errors.ErrEmptyTitle,
		},
		{
			name:    "Malformed JSON",
			body:    strings.NewReader(`{ invalid`),
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var params MarkSeasonRequestSerializer

			err := params.Validate(tt.body)

			if tt.wantErr {
				require.Error(t, err)
				return
			}

			assert.Equal(t, tt.expected, err)
		})
	}
}

func Test_MarkSeasonRequest_ToInputs(t *testing.T) {
	params := MarkSeasonRequestSerializer{
		Series: ProgressSeriesSerializer{
			Title:         "Show",
			PosterPath:    "/poster.jpg",
			SeasonsCount:  1,
			EpisodesCount: 10,
			Status:        "Ended",
		},
		Season: ProgressSeasonMetaSerializer{
			Title:         "Season 1",
			Number:        1,
			EpisodesCount: 2,
		},
		Episodes: []ProgressEpisodeSerializer{
			{Id: 1, Title: "Ep1", Runtime: 20, AirDate: "2020-01-01"},
		},
	}

	seriesInput, seasonInput := params.ToInputs(100, 200)

	assert.Equal(t, models.SeriesInput{
		TmdbId:        100,
		Title:         "Show",
		PosterPath:    "/poster.jpg",
		SeasonsCount:  1,
		EpisodesCount: 10,
		Status:        "Ended",
	}, seriesInput)

	assert.Equal(t, models.SeasonInput{
		TmdbId:        200,
		Title:         "Season 1",
		Number:        1,
		EpisodesCount: 2,
		Episodes: []models.EpisodeInput{
			{TmdbId: 1, Title: "Ep1", Runtime: 20, AirAt: time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)},
		},
	}, seasonInput)
}

func Test_MarkEpisodeRequest_Validate(t *testing.T) {
	tests := []struct {
		name     string
		body     io.Reader
		expected error
		wantErr  bool
	}{
		{
			name:     "Success",
			body:     strings.NewReader(`{ "series": { "title": "Show" }, "season": { "title": "Season 1" }, "episode": { "title": "Ep1" } }`),
			expected: nil,
		},
		{
			name:     "Empty series title",
			body:     strings.NewReader(`{ "series": { "title": "" }, "season": { "title": "Season 1" }, "episode": { "title": "Ep1" } }`),
			expected: errors.ErrEmptyTitle,
		},
		{
			name:     "Whitespace series title",
			body:     strings.NewReader(`{ "series": { "title": "   " }, "season": { "title": "Season 1" }, "episode": { "title": "Ep1" } }`),
			expected: errors.ErrEmptyTitle,
		},
		{
			name:    "Malformed JSON",
			body:    strings.NewReader(`{ invalid`),
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var params MarkEpisodeRequestSerializer

			err := params.Validate(tt.body)

			if tt.wantErr {
				require.Error(t, err)
				return
			}

			assert.Equal(t, tt.expected, err)
		})
	}
}

func Test_MarkEpisodeRequest_ToInputs(t *testing.T) {
	params := MarkEpisodeRequestSerializer{
		Series: ProgressSeriesSerializer{
			Title:         "Show",
			PosterPath:    "/poster.jpg",
			SeasonsCount:  1,
			EpisodesCount: 10,
			Status:        "Ended",
		},
		Season: ProgressSeasonMetaSerializer{
			Title:         "Season 1",
			Number:        1,
			EpisodesCount: 2,
		},
		Episode: ProgressEpisodeMetaSerializer{
			Title:      "Ep1",
			PosterPath: "/ep1.jpg",
			Runtime:    20,
			AirDate:    "2020-01-01",
		},
	}

	seriesInput, seasonInput, episodeInput := params.ToInputs(100, 200, 300)

	assert.Equal(t, models.SeriesInput{
		TmdbId:        100,
		Title:         "Show",
		PosterPath:    "/poster.jpg",
		SeasonsCount:  1,
		EpisodesCount: 10,
		Status:        "Ended",
	}, seriesInput)

	assert.Equal(t, models.SeasonInput{
		TmdbId:        200,
		Title:         "Season 1",
		Number:        1,
		EpisodesCount: 2,
		Episodes:      []models.EpisodeInput{},
	}, seasonInput)

	assert.Equal(t, models.EpisodeInput{
		TmdbId:     300,
		Title:      "Ep1",
		PosterPath: "/ep1.jpg",
		Runtime:    20,
		AirAt:      time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC),
	}, episodeInput)
}

func Test_NewProgressResponse(t *testing.T) {
	tests := []struct {
		name     string
		progress *models.SeriesProgress
		expected ProgressResponseSerializer
	}{
		{
			name: "Nil slices become empty",
			progress: &models.SeriesProgress{
				SeriesTmdbId:    1,
				State:           "watching",
				TrackedState:    "watching",
				WatchedSeasons:  nil,
				WatchedEpisodes: nil,
			},
			expected: ProgressResponseSerializer{
				Id:              1,
				State:           "watching",
				TrackedState:    "watching",
				WatchedSeasons:  []uint64{},
				WatchedEpisodes: []uint64{},
			},
		},
		{
			name: "Populated slices pass through",
			progress: &models.SeriesProgress{
				SeriesTmdbId:    2,
				State:           "watched",
				TrackedState:    "",
				WatchedSeasons:  []uint64{1, 2},
				WatchedEpisodes: []uint64{10, 20, 30},
			},
			expected: ProgressResponseSerializer{
				Id:              2,
				State:           "watched",
				TrackedState:    "",
				WatchedSeasons:  []uint64{1, 2},
				WatchedEpisodes: []uint64{10, 20, 30},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, NewProgressResponse(tt.progress))
		})
	}
}

func Test_episodeInputs(t *testing.T) {
	t.Run("Nil episodes", func(t *testing.T) {
		assert.Equal(t, []models.EpisodeInput{}, episodeInputs(nil))
	})

	t.Run("Maps and trims episodes", func(t *testing.T) {
		episodes := []ProgressEpisodeSerializer{
			{Id: 10, Title: " Ep1 ", PosterPath: "/p1.jpg", Runtime: 40, AirDate: "2024-01-01"},
			{Id: 20, Title: "Ep2", PosterPath: "/p2.jpg", Runtime: 45, AirDate: ""},
		}

		expected := []models.EpisodeInput{
			{TmdbId: 10, Title: "Ep1", PosterPath: "/p1.jpg", Runtime: 40, AirAt: time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)},
			{TmdbId: 20, Title: "Ep2", PosterPath: "/p2.jpg", Runtime: 45, AirAt: time.Time{}},
		}

		assert.Equal(t, expected, episodeInputs(episodes))
	})
}

func Test_parseAirDate(t *testing.T) {
	tests := []struct {
		name     string
		value    string
		expected time.Time
	}{
		{name: "Empty", value: "", expected: time.Time{}},
		{name: "Whitespace only", value: "   ", expected: time.Time{}},
		{name: "Malformed", value: "not-a-date", expected: time.Time{}},
		{name: "Valid", value: "2024-01-15", expected: time.Date(2024, 1, 15, 0, 0, 0, 0, time.UTC)},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, parseAirDate(tt.value))
		})
	}
}

func Test_ProgressSeriesSerializer_toInput(t *testing.T) {
	s := ProgressSeriesSerializer{
		Title:         " Show ",
		PosterPath:    "/poster.jpg",
		SeasonsCount:  3,
		EpisodesCount: 30,
		Status:        "Ended",
	}

	expected := models.SeriesInput{
		TmdbId:        99,
		Title:         "Show",
		PosterPath:    "/poster.jpg",
		SeasonsCount:  3,
		EpisodesCount: 30,
		Status:        "Ended",
	}

	assert.Equal(t, expected, s.toInput(99))
}

func Test_ProgressEpisodeSerializer_toInput(t *testing.T) {
	e := ProgressEpisodeSerializer{
		Id:         5,
		Title:      " Pilot ",
		PosterPath: "/e.jpg",
		Runtime:    42,
		AirDate:    "2023-05-06",
	}

	expected := models.EpisodeInput{
		TmdbId:     5,
		Title:      "Pilot",
		PosterPath: "/e.jpg",
		Runtime:    42,
		AirAt:      time.Date(2023, 5, 6, 0, 0, 0, 0, time.UTC),
	}

	assert.Equal(t, expected, e.toInput())
}

func Test_ProgressSeasonSerializer_toInput(t *testing.T) {
	s := ProgressSeasonSerializer{
		Id:            7,
		Title:         " Season 1 ",
		Number:        1,
		EpisodesCount: 2,
		Episodes: []ProgressEpisodeSerializer{
			{Id: 1, Title: "E1", Runtime: 10, AirDate: ""},
			{Id: 2, Title: "E2", Runtime: 20, AirDate: "2022-02-02"},
		},
	}

	expected := models.SeasonInput{
		TmdbId:        7,
		Title:         "Season 1",
		Number:        1,
		EpisodesCount: 2,
		Episodes: []models.EpisodeInput{
			{TmdbId: 1, Title: "E1", Runtime: 10, AirAt: time.Time{}},
			{TmdbId: 2, Title: "E2", Runtime: 20, AirAt: time.Date(2022, 2, 2, 0, 0, 0, 0, time.UTC)},
		},
	}

	assert.Equal(t, expected, s.toInput())
}

func Test_ProgressSeasonMetaSerializer_toInput(t *testing.T) {
	t.Run("With episodes", func(t *testing.T) {
		s := ProgressSeasonMetaSerializer{Title: " Season 2 ", Number: 2, EpisodesCount: 5}
		episodes := []ProgressEpisodeSerializer{
			{Id: 9, Title: "E9", Runtime: 30, AirDate: "2021-01-01"},
		}

		expected := models.SeasonInput{
			TmdbId:        55,
			Title:         "Season 2",
			Number:        2,
			EpisodesCount: 5,
			Episodes: []models.EpisodeInput{
				{TmdbId: 9, Title: "E9", Runtime: 30, AirAt: time.Date(2021, 1, 1, 0, 0, 0, 0, time.UTC)},
			},
		}

		assert.Equal(t, expected, s.toInput(55, episodes))
	})

	t.Run("Nil episodes", func(t *testing.T) {
		s := ProgressSeasonMetaSerializer{Title: "Season 3", Number: 3, EpisodesCount: 0}

		expected := models.SeasonInput{
			TmdbId:        66,
			Title:         "Season 3",
			Number:        3,
			EpisodesCount: 0,
			Episodes:      []models.EpisodeInput{},
		}

		assert.Equal(t, expected, s.toInput(66, nil))
	})
}

func Test_ProgressEpisodeMetaSerializer_toInput(t *testing.T) {
	e := ProgressEpisodeMetaSerializer{
		Title:      " Ep Meta ",
		PosterPath: "/em.jpg",
		Runtime:    33,
		AirDate:    "2020-12-25",
	}

	expected := models.EpisodeInput{
		TmdbId:     44,
		Title:      "Ep Meta",
		PosterPath: "/em.jpg",
		Runtime:    33,
		AirAt:      time.Date(2020, 12, 25, 0, 0, 0, 0, time.UTC),
	}

	assert.Equal(t, expected, e.toInput(44))
}
