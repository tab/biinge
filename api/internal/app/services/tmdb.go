package services

import (
	"context"

	"github.com/google/uuid"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/config/logger"
	"biinge-api/pkg/tmdb"
)

type TmdbProvider interface {
	FetchMovieDetails(ctx context.Context, id uint64, userId uuid.UUID) (*serializers.MovieDetailsSerializer, error)
	FetchTvDetails(ctx context.Context, id uint64, userId uuid.UUID) (*serializers.SeriesDetailsSerializer, error)
	FetchPersonDetails(ctx context.Context, id uint64, userId uuid.UUID) (*serializers.PersonDetailsSerializer, error)
}

type tmdbProvider struct {
	client tmdb.Client
	movies Movies
	series Series
	log    *logger.Logger
}

func NewTmdbProvider(client tmdb.Client, movies Movies, series Series, log *logger.Logger) TmdbProvider {
	return &tmdbProvider{
		client: client,
		movies: movies,
		series: series,
		log:    log.WithComponent("TmdbProvider"),
	}
}

func (p *tmdbProvider) FetchMovieDetails(ctx context.Context, id uint64, userId uuid.UUID) (*serializers.MovieDetailsSerializer, error) {
	p.log.Debug().Uint64("Id", id).Msg("Fetching movie details")

	response, err := p.client.FetchMovieDetails(ctx, id)
	if err != nil {
		p.log.Error().
			Err(err).
			Uint64("Id", id).
			Msg("Failed to fetch movie details")
		return nil, tmdb.ErrFailedToFetchMovieDetails
	}

	details := tmdb.TransformMovieDetails(response)

	p.log.Debug().
		Uint64("Id", id).
		Msg("Successfully fetched and transformed movie details")

	recommendationIds := make([]uint64, 0, len(details.Recommendations))
	for _, item := range details.Recommendations {
		recommendationIds = append(recommendationIds, item.Id)
	}

	moviesList, err := p.movies.FindMoviesByTmdbIds(ctx, recommendationIds, userId)
	if err != nil {
		p.log.Error().
			Err(err).
			Msg("Failed to fetch recommendation states")
		return nil, errors.ErrFailedToFetchResults
	}

	recommendationStatesMap := make(map[uint64]string)
	for _, movie := range moviesList {
		recommendationStatesMap[movie.TmdbId] = movie.State
	}

	recommendations := make([]serializers.RecommendationSerializer, 0, len(details.Recommendations))
	for _, item := range details.Recommendations {
		state := models.StateTypeNone
		if movieState, exists := recommendationStatesMap[item.Id]; exists {
			state = movieState
		}

		recommendations = append(recommendations, serializers.RecommendationSerializer{
			Id:         item.Id,
			Title:      item.Title,
			PosterPath: item.PosterPath,
			State:      state,
		})
	}

	credits := make([]serializers.PersonSerializer, 0, len(details.Credits))
	for _, item := range details.Credits {
		credits = append(credits, serializers.PersonSerializer{
			Id:          item.Id,
			Name:        item.Name,
			Description: item.Description,
			ProfilePath: item.ProfilePath,
		})
	}

	videos := make([]serializers.VideoSerializer, 0, len(details.Videos))
	for _, item := range details.Videos {
		videos = append(videos, serializers.VideoSerializer{
			Id:  item.Id,
			Key: item.Key,
		})
	}

	movie, err := p.movies.FindByTmdbId(ctx, id, userId)
	if err != nil {
		if errors.Is(err, errors.ErrMovieNotFound) {
			p.log.Debug().
				Err(err).
				Uint64("Id", id).
				Msg("Movie not found in database")
			return &serializers.MovieDetailsSerializer{
				Id:              id,
				Pinned:          false,
				State:           models.StateTypeNone,
				Status:          details.Status,
				Title:           details.Title,
				PosterPath:      details.PosterPath,
				Overview:        details.Overview,
				ReleaseDate:     details.ReleaseDate,
				Runtime:         details.Runtime,
				Rating:          details.Rating,
				Credits:         credits,
				Recommendations: recommendations,
				Videos:          videos,
			}, nil
		}
		p.log.Error().
			Err(err).
			Uint64("Id", id).
			Msg("Failed to fetch movie state")
		return nil, errors.ErrFailedToFetchMovie
	}

	return &serializers.MovieDetailsSerializer{
		Id:              id,
		Pinned:          movie.Pinned,
		State:           movie.State,
		Status:          details.Status,
		Title:           details.Title,
		PosterPath:      details.PosterPath,
		Overview:        details.Overview,
		ReleaseDate:     details.ReleaseDate,
		Runtime:         details.Runtime,
		Rating:          details.Rating,
		Credits:         credits,
		Recommendations: recommendations,
		Videos:          videos,
	}, nil
}

func (p *tmdbProvider) FetchTvDetails(ctx context.Context, id uint64, userId uuid.UUID) (*serializers.SeriesDetailsSerializer, error) {
	p.log.Debug().Uint64("Id", id).Msg("Fetching tv details")

	response, err := p.client.FetchTvDetails(ctx, id)
	if err != nil {
		p.log.Error().
			Err(err).
			Uint64("Id", id).
			Msg("Failed to fetch tv details")
		return nil, tmdb.ErrFailedToFetchTvDetails
	}

	details := tmdb.TransformTvDetails(response)

	p.log.Debug().
		Uint64("Id", id).
		Msg("Successfully fetched and transformed tv details")

	recommendationIds := make([]uint64, 0, len(details.Recommendations))
	for _, item := range details.Recommendations {
		recommendationIds = append(recommendationIds, item.Id)
	}

	tvShowsList, err := p.series.FindSeriesByTmdbIds(ctx, recommendationIds, userId)
	if err != nil {
		p.log.Error().
			Err(err).
			Msg("Failed to fetch recommendation states")
		return nil, errors.ErrFailedToFetchResults
	}

	recommendationStatesMap := make(map[uint64]string)
	for _, tvShow := range tvShowsList {
		recommendationStatesMap[tvShow.TmdbId] = tvShow.State
	}

	recommendations := make([]serializers.RecommendationSerializer, 0, len(details.Recommendations))
	for _, item := range details.Recommendations {
		state := models.StateTypeNone
		if tvShowState, exists := recommendationStatesMap[item.Id]; exists {
			state = tvShowState
		}

		recommendations = append(recommendations, serializers.RecommendationSerializer{
			Id:         item.Id,
			Title:      item.Title,
			PosterPath: item.PosterPath,
			State:      state,
		})
	}

	credits := make([]serializers.PersonSerializer, 0, len(details.Credits))
	for _, item := range details.Credits {
		credits = append(credits, serializers.PersonSerializer{
			Id:          item.Id,
			Name:        item.Name,
			Description: item.Description,
			ProfilePath: item.ProfilePath,
		})
	}

	videos := make([]serializers.VideoSerializer, 0, len(details.Videos))
	for _, item := range details.Videos {
		videos = append(videos, serializers.VideoSerializer{
			Id:  item.Id,
			Key: item.Key,
		})
	}

	tvShow, err := p.series.FindSeriesByTmdbId(ctx, id, userId)
	if err != nil {
		if errors.Is(err, errors.ErrSeriesNotFound) {
			p.log.Debug().
				Err(err).
				Uint64("Id", id).
				Msg("Series not found in database")
			return &serializers.SeriesDetailsSerializer{
				Id:              id,
				Pinned:          false,
				State:           models.StateTypeNone,
				Status:          details.Status,
				Title:           details.Title,
				PosterPath:      details.PosterPath,
				Overview:        details.Overview,
				ReleaseDate:     details.ReleaseDate,
				Rating:          details.Rating,
				Credits:         credits,
				Recommendations: recommendations,
				Videos:          videos,
			}, nil
		}
		p.log.Error().
			Err(err).
			Uint64("Id", id).
			Msg("Failed to fetch series state")
		return nil, errors.ErrFailedToFetchSeries
	}

	return &serializers.SeriesDetailsSerializer{
		Id:              id,
		Pinned:          tvShow.Pinned,
		State:           tvShow.State,
		Status:          details.Status,
		Title:           details.Title,
		PosterPath:      details.PosterPath,
		Overview:        details.Overview,
		ReleaseDate:     details.ReleaseDate,
		Rating:          details.Rating,
		Credits:         credits,
		Recommendations: recommendations,
		Videos:          videos,
	}, nil
}

func (p *tmdbProvider) FetchPersonDetails(ctx context.Context, id uint64, userId uuid.UUID) (*serializers.PersonDetailsSerializer, error) {
	p.log.Debug().Uint64("Id", id).Msg("Fetching person details")

	response, err := p.client.FetchPersonDetails(ctx, id)
	if err != nil {
		p.log.Error().
			Err(err).
			Uint64("Id", id).
			Msg("Failed to fetch person details")
		return nil, tmdb.ErrFailedToFetchPersonDetails
	}

	details := tmdb.TransformPersonDetails(response)

	p.log.Debug().
		Uint64("Id", id).
		Msg("Successfully fetched and transformed person details")

	movieCreditIds := make([]uint64, 0, len(details.MovieCredits))
	for _, item := range details.MovieCredits {
		movieCreditIds = append(movieCreditIds, item.Id)
	}

	moviesList, err := p.movies.FindMoviesByTmdbIds(ctx, movieCreditIds, userId)
	if err != nil {
		p.log.Error().
			Err(err).
			Msg("Failed to fetch credit states")
		return nil, errors.ErrFailedToFetchResults
	}

	movieCreditStatesMap := make(map[uint64]string)
	for _, movie := range moviesList {
		movieCreditStatesMap[movie.TmdbId] = movie.State
	}

	movieCredits := make([]serializers.MovieCreditSerializer, 0, len(details.MovieCredits))
	for _, item := range details.MovieCredits {
		state := models.StateTypeNone
		if movieState, exists := movieCreditStatesMap[item.Id]; exists {
			state = movieState
		}

		movieCredits = append(movieCredits, serializers.MovieCreditSerializer{
			Id:         item.Id,
			Title:      item.Title,
			PosterPath: item.PosterPath,
			State:      state,
			Type:       item.Type,
		})
	}

	return &serializers.PersonDetailsSerializer{
		Id:           id,
		Name:         details.Name,
		Birthday:     details.Birthday,
		ProfilePath:  details.ProfilePath,
		Gender:       details.Gender,
		MovieCredits: movieCredits,
	}, nil
}
