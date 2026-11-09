package services

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/config"
	"biinge-api/internal/config/cache"
	"biinge-api/internal/config/logger"
	"biinge-api/pkg/igdb"
	"biinge-api/pkg/tmdb"
)

// Shares creates the public links users send for a title
type Shares interface {
	Create(ctx context.Context, params *models.Share) (*serializers.ShareSerializer, error)
	Page(ctx context.Context, id uuid.UUID) (*serializers.SharePageSerializer, error)
}

// shareCreditLimit is how many Cast & Crew people the share page lists, as the Mac details do
const shareCreditLimit = 20

// shareGenreLimit is how many genres the share page's meta line names, as the Mac details do
const shareGenreLimit = 3

// shareDescriptionLimit is how many characters of the overview go into og:description
const shareDescriptionLimit = 200

type shares struct {
	cfg        *config.Config
	repository repositories.ShareRepository
	tmdb       tmdb.Client
	igdb       igdb.Client
	cache      cache.Cache
	log        *logger.Logger
}

func NewShares(
	cfg *config.Config,
	repository repositories.ShareRepository,
	tmdbClient tmdb.Client,
	igdbClient igdb.Client,
	store cache.Cache,
	log *logger.Logger,
) Shares {
	return &shares{
		cfg:        cfg,
		repository: repository,
		tmdb:       tmdbClient,
		igdb:       igdbClient,
		cache:      store,
		log:        log.WithComponent("SharesService"),
	}
}

// Create checks the title exists at its provider, upserts the user's share and returns its id and link (an unknown title stores nothing)
func (s *shares) Create(ctx context.Context, params *models.Share) (*serializers.ShareSerializer, error) {
	// the providers' own keys and TTL, so the check warms the entry the share page reads
	var err error

	switch params.Type {
	case models.ShareTypeMovie:
		_, err = cache.Fetch(ctx, s.cache, s.log, fmt.Sprintf("tmdb:v2:movie:%d", params.ObjectId), cache.DetailsTTL, func() (*tmdb.MovieDetails, error) {
			return s.tmdb.FetchMovieDetails(ctx, params.ObjectId)
		})
	case models.ShareTypeTv:
		_, err = cache.Fetch(ctx, s.cache, s.log, fmt.Sprintf("tmdb:v3:tv:%d", params.ObjectId), cache.DetailsTTL, func() (*tmdb.TvDetails, error) {
			return s.tmdb.FetchTvDetails(ctx, params.ObjectId)
		})
	case models.ShareTypeGame:
		_, err = cache.Fetch(ctx, s.cache, s.log, fmt.Sprintf("igdb:v2:game:%d", params.ObjectId), cache.DetailsTTL, func() (*igdb.GameDetails, error) {
			return s.igdb.FetchGameDetails(ctx, params.ObjectId)
		})
	}

	switch {
	case errors.Is(err, tmdb.ErrNotFound), errors.Is(err, igdb.ErrNotFound):
		return nil, errors.ErrShareObjectNotFound
	case err != nil:
		s.log.Error().Err(err).Str("Type", string(params.Type)).Uint64("Id", params.ObjectId).Msg("Failed to fetch shared title")
		return nil, errors.ErrFailedToFetchResults
	}

	share, err := s.repository.Upsert(ctx, params)
	if err != nil {
		s.log.Error().Err(err).Msg("Failed to create share")
		return nil, errors.ErrFailedToCreateShare
	}

	return &serializers.ShareSerializer{
		Id:  share.ID,
		URL: strings.TrimSuffix(s.cfg.ShareURL, "/") + "/" + share.ID.String(),
	}, nil
}

// Page returns what the public page shows of a live share's title and records the visit (an expired share, or a title its provider no longer knows, is not found)
func (s *shares) Page(ctx context.Context, id uuid.UUID) (*serializers.SharePageSerializer, error) {
	share, err := s.repository.FindLive(ctx, id)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		return nil, errors.ErrShareNotFound
	case err != nil:
		s.log.Error().Err(err).Str("Id", id.String()).Msg("Failed to find share")
		return nil, errors.ErrFailedToFetchShare
	}

	// the same keys and TTL as Create and the details screens, so the page reads the entry they warmed
	var page *serializers.SharePageSerializer

	now := time.Now()

	switch share.Type {
	case models.ShareTypeMovie:
		var details *tmdb.MovieDetails
		if details, err = cache.Fetch(ctx, s.cache, s.log, fmt.Sprintf("tmdb:v2:movie:%d", share.ObjectId), cache.DetailsTTL, func() (*tmdb.MovieDetails, error) {
			return s.tmdb.FetchMovieDetails(ctx, share.ObjectId)
		}); err == nil {
			page = moviePage(details, now)
		}
	case models.ShareTypeTv:
		var details *tmdb.TvDetails
		if details, err = cache.Fetch(ctx, s.cache, s.log, fmt.Sprintf("tmdb:v3:tv:%d", share.ObjectId), cache.DetailsTTL, func() (*tmdb.TvDetails, error) {
			return s.tmdb.FetchTvDetails(ctx, share.ObjectId)
		}); err == nil {
			page = seriesPage(details, now)
		}
	case models.ShareTypeGame:
		var details *igdb.GameDetails
		if details, err = cache.Fetch(ctx, s.cache, s.log, fmt.Sprintf("igdb:v2:game:%d", share.ObjectId), cache.DetailsTTL, func() (*igdb.GameDetails, error) {
			return s.igdb.FetchGameDetails(ctx, share.ObjectId)
		}); err == nil {
			page = gamePage(details, now)
		}
	}

	switch {
	case errors.Is(err, tmdb.ErrNotFound), errors.Is(err, igdb.ErrNotFound):
		return nil, errors.ErrShareNotFound
	case err != nil:
		s.log.Error().Err(err).Str("Type", string(share.Type)).Uint64("Id", share.ObjectId).Msg("Failed to fetch shared title")
		return nil, errors.ErrFailedToFetchResults
	}

	// a fact with no value stays off the page
	facts := make([]serializers.ShareFactSerializer, 0, len(page.Facts))
	for _, fact := range page.Facts {
		if fact.Value != "" {
			facts = append(facts, fact)
		}
	}

	page.Facts = facts

	// a missed visit only shortens the link's life, so the page still renders
	if err := s.repository.TouchVisit(ctx, share.ID); err != nil {
		s.log.Warn().Err(err).Str("Id", share.ID.String()).Msg("Failed to record share visit")
	}

	return page, nil
}

// moviePage maps a movie's TMDB details to the share page
func moviePage(details *tmdb.MovieDetails, now time.Time) *serializers.SharePageSerializer {
	movie := tmdb.TransformMovieDetails(details)

	return &serializers.SharePageSerializer{
		Kind:        "Movie",
		Title:       movie.Title,
		Year:        shareYear(movie.ReleaseDate),
		Meta:        shareMeta(shareRelease(movie.ReleaseDate, now), shareRuntime(movie.Runtime), strings.Join(movie.Genres[:min(len(movie.Genres), shareGenreLimit)], ", ")),
		Rating:      shareRating(movie.Rating),
		Overview:    movie.Overview,
		Description: shareDescription(movie.Overview),
		ImageURL:    tmdbImageURL(movie.PosterPath, "w500"),
		Facts: []serializers.ShareFactSerializer{
			{Label: "Director", Value: strings.Join(movie.Directors, ", ")},
			{Label: shareReleaseLabel(movie.ReleaseDate, now, "Released", "Releases"), Value: shareDay(movie.ReleaseDate)},
			{Label: "Status", Value: shareStatus(movie.Status)},
		},
		Credits: shareCredits(movie.Credits),
	}
}

// seriesPage maps a series' TMDB details to the share page
func seriesPage(details *tmdb.TvDetails, now time.Time) *serializers.SharePageSerializer {
	series := tmdb.TransformTvDetails(details)

	count := ""

	switch {
	case series.SeasonsCount == 1:
		count = "1 Season"
	case series.SeasonsCount > 1:
		count = fmt.Sprintf("%d Seasons", series.SeasonsCount)
	}

	// every season the app's season picker offers, Specials included
	seasons := make([]serializers.ShareSeasonSerializer, 0, len(series.Seasons))
	for _, season := range series.Seasons {
		episodes := fmt.Sprintf("%d episodes", season.EpisodesCount)
		if season.EpisodesCount == 1 {
			episodes = "1 episode"
		}

		seasons = append(seasons, serializers.ShareSeasonSerializer{
			Name:     season.Title,
			Year:     shareYear(season.AirDate),
			Episodes: episodes,
		})
	}

	return &serializers.SharePageSerializer{
		Kind:        "TV Show",
		Title:       series.Title,
		Year:        shareYear(series.ReleaseDate),
		Meta:        shareMeta(shareRelease(series.ReleaseDate, now), count, strings.Join(series.Genres[:min(len(series.Genres), shareGenreLimit)], ", ")),
		Rating:      shareRating(series.Rating),
		Overview:    series.Overview,
		Description: shareDescription(series.Overview),
		ImageURL:    tmdbImageURL(series.PosterPath, "w500"),
		Facts: []serializers.ShareFactSerializer{
			{Label: "Created by", Value: strings.Join(series.Creators, ", ")},
			{Label: shareReleaseLabel(series.ReleaseDate, now, "First aired", "First airs"), Value: shareRelease(series.ReleaseDate, now)},
			{Label: "Status", Value: shareStatus(series.Status)},
		},
		Seasons: seasons,
		Credits: shareCredits(series.Credits),
	}
}

// gamePage maps a game's IGDB details to the share page
func gamePage(details *igdb.GameDetails, now time.Time) *serializers.SharePageSerializer {
	game := igdb.TransformGameDetails(details)

	imageURL := ""
	if game.PosterPath != "" {
		imageURL = "https://images.igdb.com/igdb/image/upload/t_cover_big_2x/" + game.PosterPath + ".jpg"
	}

	playTime := ""
	if hours := game.Runtime / 60; hours > 0 {
		playTime = fmt.Sprintf("%dh", hours)
	}

	return &serializers.SharePageSerializer{
		Kind:        "Game",
		Title:       game.Title,
		Year:        shareYear(game.ReleaseDate),
		Meta:        shareMeta(shareRelease(game.ReleaseDate, now), playTime),
		Rating:      shareRating(game.Rating),
		Overview:    game.Overview,
		Description: shareDescription(game.Overview),
		ImageURL:    imageURL,
		Facts: []serializers.ShareFactSerializer{
			{Label: "Developer", Value: strings.Join(game.Developers, ", ")},
			{Label: shareReleaseLabel(game.ReleaseDate, now, "Released", "Releases"), Value: shareDay(game.ReleaseDate)},
			{Label: "Status", Value: shareStatus(game.Status)},
		},
		Genres:    game.Genres,
		Platforms: game.Platforms,
	}
}

// shareCredits keeps the first Cast & Crew people of the transformed credits (each has a photo)
func shareCredits(credits []tmdb.CreditItem) []serializers.ShareCreditSerializer {
	items := make([]serializers.ShareCreditSerializer, 0, shareCreditLimit)

	for _, person := range credits[:min(len(credits), shareCreditLimit)] {
		items = append(items, serializers.ShareCreditSerializer{
			Name:     person.Name,
			Role:     person.Description,
			PhotoURL: tmdbImageURL(person.ProfilePath, "w185"),
		})
	}

	return items
}

// tmdbImageURL builds a TMDB CDN image URL (empty without a path)
func tmdbImageURL(path string, size string) string {
	if path == "" {
		return ""
	}

	return "https://image.tmdb.org/t/p/" + size + path
}

// shareYear is the year of an ISO date (empty without one)
func shareYear(date string) string {
	if len(date) < len("2006") {
		return ""
	}

	return date[:4]
}

// shareDay reads an ISO date as "1 Mar 2024" in UTC (empty when it doesn't parse)
func shareDay(date string) string {
	day, err := time.Parse(time.DateOnly, date[:min(len(date), len(time.DateOnly))])
	if err != nil {
		return ""
	}

	return day.Format("2 Jan 2006")
}

// shareRelease reads a release as its day from six months before today in UTC on (the future too) and as its year before, as the apps' meta line does (empty without a date)
func shareRelease(date string, now time.Time) string {
	today := now.UTC()

	// a month too short for today's day clamps to its last day, as Foundation's calendar does
	cutoff := today.AddDate(0, -6, 0)
	if cutoff.Day() != today.Day() {
		cutoff = cutoff.AddDate(0, 0, -cutoff.Day())
	}

	if day := shareDay(date); day != "" && date[:len(time.DateOnly)] >= cutoff.Format(time.DateOnly) {
		return day
	}

	return shareYear(date)
}

// shareMeta joins the meta line's parts with " · " and skips the empty ones
func shareMeta(parts ...string) string {
	kept := make([]string, 0, len(parts))

	for _, part := range parts {
		if part != "" {
			kept = append(kept, part)
		}
	}

	return strings.Join(kept, " · ")
}

// shareReleaseLabel picks the future label for a date after today in UTC, as the apps do (ISO days sort as text)
func shareReleaseLabel(date string, now time.Time, past string, future string) string {
	if date[:min(len(date), len(time.DateOnly))] > now.UTC().Format(time.DateOnly) {
		return future
	}

	return past
}

// shareRating reads a 0-10 rating with one decimal (empty when unrated)
func shareRating(rating float64) string {
	if rating <= 0 {
		return ""
	}

	return strconv.FormatFloat(rating, 'f', 1, 64)
}

// shareRuntime reads minutes as "2h 16m", or "45 min" under an hour, as the apps do (empty without a runtime)
func shareRuntime(minutes int) string {
	switch {
	case minutes <= 0:
		return ""
	case minutes < 60:
		return fmt.Sprintf("%d min", minutes)
	default:
		return fmt.Sprintf("%dh %dm", minutes/60, minutes%60)
	}
}

// shareStatus reads a release status the way the apps label it (empty on none and on Released)
func shareStatus(status string) string {
	switch status {
	case "Released":
		return ""
	case "Canceled":
		return "Cancelled"
	case "Returning Series":
		return "Returning"
	case "Post Production":
		return "Post-production"
	case "In Production":
		return "In production"
	default:
		return status
	}
}

// shareDescription cuts an overview to the og:description length at a word break
func shareDescription(overview string) string {
	overview = strings.TrimSpace(overview)
	if utf8.RuneCountInString(overview) <= shareDescriptionLimit {
		return overview
	}

	cut := string([]rune(overview)[:shareDescriptionLimit])
	if space := strings.LastIndex(cut, " "); space > 0 {
		cut = cut[:space]
	}

	return strings.TrimRight(cut, " ,.;:") + "…"
}
