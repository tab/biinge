package controllers

import (
	"context"
	"encoding/base64"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config"
	"biinge-api/internal/config/middlewares"
)

func Test_SharesController_HandleCreate(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	shares := services.NewMockShares(ctrl)
	controller := NewSharesController(&config.Config{}, shares)

	user := &models.User{ID: uuid.New()}
	shareId := uuid.MustParse("6f1c3c1e-8a2b-4d4e-9f3a-1b2c3d4e5f60")

	const body = `{"type":"movie","object_id":603}`

	params := &models.Share{UserId: user.ID, Type: models.ShareTypeMovie, ObjectId: 603}

	tests := []struct {
		name     string
		before   func()
		withUser bool
		body     string
		code     int
		response string
	}{
		{
			name: "Success",
			before: func() {
				shares.EXPECT().
					Create(gomock.Any(), params).
					Return(&serializers.ShareSerializer{Id: shareId, URL: "https://share.example.com/" + shareId.String()}, nil)
			},
			withUser: true,
			body:     body,
			code:     http.StatusCreated,
			response: `{"id":"6f1c3c1e-8a2b-4d4e-9f3a-1b2c3d4e5f60","url":"https://share.example.com/6f1c3c1e-8a2b-4d4e-9f3a-1b2c3d4e5f60"}`,
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			body:     body,
			code:     http.StatusUnauthorized,
			response: `{"error":"unauthorized"}`,
		},
		{
			name:     "Malformed body",
			before:   func() {},
			withUser: true,
			body:     `{"type":`,
			code:     http.StatusBadRequest,
			response: `{"error":"unexpected EOF"}`,
		},
		{
			name:     "Unknown type",
			before:   func() {},
			withUser: true,
			body:     `{"type":"book","object_id":603}`,
			code:     http.StatusBadRequest,
			response: `{"error":"Key: 'CreateShareRequestSerializer.Type' Error:Field validation for 'Type' failed on the 'oneof' tag"}`,
		},
		{
			name:     "Missing object id",
			before:   func() {},
			withUser: true,
			body:     `{"type":"movie"}`,
			code:     http.StatusBadRequest,
			response: `{"error":"Key: 'CreateShareRequestSerializer.ObjectId' Error:Field validation for 'ObjectId' failed on the 'required' tag"}`,
		},
		{
			name: "Unknown title",
			before: func() {
				shares.EXPECT().Create(gomock.Any(), params).Return(nil, errors.ErrShareObjectNotFound)
			},
			withUser: true,
			body:     body,
			code:     http.StatusNotFound,
			response: `{"error":"share object not found"}`,
		},
		{
			name: "Provider failure",
			before: func() {
				shares.EXPECT().Create(gomock.Any(), params).Return(nil, errors.ErrFailedToFetchResults)
			},
			withUser: true,
			body:     body,
			code:     http.StatusUnprocessableEntity,
			response: `{"error":"failed to fetch results"}`,
		},
		{
			name: "Failed to create",
			before: func() {
				shares.EXPECT().Create(gomock.Any(), params).Return(nil, errors.ErrFailedToCreateShare)
			},
			withUser: true,
			body:     body,
			code:     http.StatusUnprocessableEntity,
			response: `{"error":"failed to create share"}`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			req := httptest.NewRequest(http.MethodPost, "/api/v1/shares", strings.NewReader(tt.body))
			if tt.withUser {
				req = req.WithContext(context.WithValue(req.Context(), middlewares.CurrentUser{}, user))
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Post("/api/v1/shares", controller.HandleCreate)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			body, err := io.ReadAll(resp.Body)
			require.NoError(t, err)

			assert.Equal(t, tt.code, resp.StatusCode)
			assert.Equal(t, "application/json", resp.Header.Get("Content-Type"))
			assert.JSONEq(t, tt.response, string(body))
		})
	}
}

func Test_SharesController_HandleShow(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	shares := services.NewMockShares(ctrl)
	controller := NewSharesController(&config.Config{}, shares)
	linked := NewSharesController(&config.Config{SiteURL: "https://site.example.com"}, shares)

	// the viewer's own session never reaches the page, and the page model has no sharer to show
	viewer := &models.User{ID: uuid.New(), Login: "sharer-login", FirstName: "Sharer"}
	shareId := uuid.MustParse("6f1c3c1e-8a2b-4d4e-9f3a-1b2c3d4e5f60")

	movie := &serializers.SharePageSerializer{
		Kind:        "Movie",
		Title:       "The Matrix",
		Year:        "1999",
		Meta:        "1999 · 2h 16m · Action, Science Fiction",
		Rating:      "8.2",
		Overview:    "A hacker learns the truth.",
		Description: "A hacker learns the truth.",
		ImageURL:    "https://image.tmdb.org/t/p/w500/matrix.jpg",
		Facts:       []serializers.ShareFactSerializer{{Label: "Director", Value: "Lana Wachowski"}, {Label: "Released", Value: "31 Mar 1999"}},
		Credits: []serializers.ShareCreditSerializer{
			{Name: "Keanu Reeves", Role: "Neo", PhotoURL: "https://image.tmdb.org/t/p/w185/keanu.jpg"},
			{Name: "Carrie-Anne Moss", Role: "Trinity", PhotoURL: "https://image.tmdb.org/t/p/w185/carrie.jpg"},
		},
	}

	// the template inlines the embedded icon, so its data URI is checked whole (html/template writes "+" in an attribute as "&#43;")
	icon := strings.ReplaceAll("data:image/png;base64,"+base64.StdEncoding.EncodeToString(shareIcon), "+", "&#43;")

	tests := []struct {
		name     string
		before   func()
		linked   bool
		path     string
		code     int
		cache    string
		contains []string
		absent   []string
	}{
		{
			name: "Movie",
			before: func() {
				shares.EXPECT().Page(gomock.Any(), shareId).Return(movie, nil)
			},
			path:  "/s/" + shareId.String(),
			code:  http.StatusOK,
			cache: "public, max-age=86400",
			contains: []string{
				"<title>The Matrix (1999) · biinge</title>",
				`<meta property="og:title" content="The Matrix (1999)">`,
				`<meta property="og:description" content="A hacker learns the truth.">`,
				`<meta property="og:image" content="https://image.tmdb.org/t/p/w500/matrix.jpg">`,
				`<meta property="og:type" content="video.other">`,
				`<meta name="twitter:card" content="summary_large_image">`,
				`<meta name="viewport"`,
				`<link rel="icon" type="image/png" href="` + icon + `">`,
				`<header class="bar"><img src="` + icon + `" alt="" width="28" height="28"><span class="brand">biinge</span></header>`,
				`<div class="backdrop" aria-hidden="true"><img src="https://image.tmdb.org/t/p/w500/matrix.jpg" alt=""></div>`,
				`<p class="kind">Movie</p>`,
				"<h1>The Matrix</h1>",
				`<p class="meta"><span>1999 · 2h 16m · Action, Science Fiction</span><span class="rating"><span>★</span>8.2</span></p>`,
				`<p class="overview">A hacker learns the truth.</p>`,
				"<div><dt>Director</dt><dd>Lana Wachowski</dd></div>",
				"<div><dt>Released</dt><dd>31 Mar 1999</dd></div>",
				"<h2>Cast &amp; Crew</h2>",
				`<li><img src="https://image.tmdb.org/t/p/w185/keanu.jpg" alt="" loading="lazy"><div><strong>Keanu Reeves</strong><small>Neo</small></div></li>`,
				`<li><img src="https://image.tmdb.org/t/p/w185/carrie.jpg" alt="" loading="lazy"><div><strong>Carrie-Anne Moss</strong><small>Trinity</small></div></li>`,
			},
			absent: []string{"sharer-login", "Sharer", "<script", "<button", "<a ", "TMDB", "themoviedb.org", "IGDB", "Seasons", "Genres", "Platforms"},
		},
		{
			name: "Series",
			before: func() {
				shares.EXPECT().Page(gomock.Any(), shareId).Return(&serializers.SharePageSerializer{
					Kind:  "TV Show",
					Title: "Game of Thrones",
					Meta:  "2011 · 8 Seasons · Drama",
					Facts: []serializers.ShareFactSerializer{{Label: "Created by", Value: "David Benioff"}},
					Seasons: []serializers.ShareSeasonSerializer{
						{Name: "Specials", Episodes: "1 episode"},
						{Name: "Season 1", Year: "2011", Episodes: "10 episodes"},
					},
				}, nil)
			},
			path:  "/s/" + shareId.String(),
			code:  http.StatusOK,
			cache: "public, max-age=86400",
			contains: []string{
				`<meta property="og:type" content="video.other">`,
				`<p class="kind">TV Show</p>`,
				`<p class="meta"><span>2011 · 8 Seasons · Drama</span></p>`,
				"<div><dt>Created by</dt><dd>David Benioff</dd></div>",
				"<h2>Seasons</h2>",
				"<li><strong>Specials</strong><span>1 episode</span></li>",
				"<li><strong>Season 1</strong><span>2011 · 10 episodes</span></li>",
			},
			absent: []string{"<script", "TMDB", "★", "Cast &amp; Crew", `class="backdrop" aria-hidden="true"><img`},
		},
		{
			name: "Game",
			before: func() {
				shares.EXPECT().Page(gomock.Any(), shareId).Return(&serializers.SharePageSerializer{
					Kind:      "Game",
					Title:     "The Witcher 3: Wild Hunt and its expansions",
					ImageURL:  "https://images.igdb.com/igdb/image/upload/t_cover_big_2x/co1wyy.jpg",
					Facts:     []serializers.ShareFactSerializer{{Label: "Developer", Value: "CD Projekt RED"}},
					Genres:    []string{"RPG", "Adventure"},
					Platforms: []string{"PS4", "PC"},
				}, nil)
			},
			path:  "/s/" + shareId.String(),
			code:  http.StatusOK,
			cache: "public, max-age=86400",
			contains: []string{
				`<meta property="og:type" content="website">`,
				`<p class="kind">Game</p>`,
				`<h1 class="long">The Witcher 3: Wild Hunt and its expansions</h1>`,
				"<div><dt>Developer</dt><dd>CD Projekt RED</dd></div>",
				"<h2>Genres</h2>",
				`<ul class="tags"><li>RPG</li><li>Adventure</li></ul>`,
				"<h2>Platforms</h2>",
				`<ul class="tags"><li>PS4</li><li>PC</li></ul>`,
			},
			absent: []string{"<script", "IGDB", "www.igdb.com", "TMDB", "Cast &amp; Crew", "<h2>Seasons</h2>"},
		},
		{
			name: "A fact with no value is absent",
			before: func() {
				shares.EXPECT().Page(gomock.Any(), shareId).Return(&serializers.SharePageSerializer{Title: "Untitled"}, nil)
			},
			path:     "/s/" + shareId.String(),
			code:     http.StatusOK,
			cache:    "public, max-age=86400",
			contains: []string{"<title>Untitled · biinge</title>", `<meta name="twitter:card" content="summary">`, `<div class="poster"></div>`},
			absent:   []string{"og:image", "og:description", "★", "<dl", "<h2>", `class="meta"`, `class="overview"`},
		},
		{
			name: "Title is escaped",
			before: func() {
				shares.EXPECT().Page(gomock.Any(), shareId).Return(&serializers.SharePageSerializer{Title: `<script>alert("x")</script>`}, nil)
			},
			path:   "/s/" + shareId.String(),
			code:   http.StatusOK,
			cache:  "public, max-age=86400",
			absent: []string{`<script>alert`},
		},
		{
			name: "Logo links to the landing site",
			before: func() {
				shares.EXPECT().Page(gomock.Any(), shareId).Return(movie, nil)
			},
			linked: true,
			path:   "/s/" + shareId.String(),
			code:   http.StatusOK,
			cache:  "public, max-age=86400",
			contains: []string{
				`<header class="bar"><a href="https://site.example.com"><img src="` + icon + `" alt="" width="28" height="28"><span class="brand">biinge</span></a></header>`,
			},
		},
		{
			name:     "Logo links to the landing site on the not-found page",
			before:   func() {},
			linked:   true,
			path:     "/s/not-a-uuid",
			code:     http.StatusNotFound,
			cache:    "no-store",
			contains: []string{`<header class="bar"><a href="https://site.example.com"><img src="` + icon + `"`},
		},
		{
			name:     "Malformed id",
			before:   func() {},
			path:     "/s/not-a-uuid",
			code:     http.StatusNotFound,
			cache:    "no-store",
			contains: []string{"This link isn't available", `<header class="bar"><img src="` + icon + `"`},
		},
		{
			name: "Unknown or expired share",
			before: func() {
				shares.EXPECT().Page(gomock.Any(), shareId).Return(nil, errors.ErrShareNotFound)
			},
			path:     "/s/" + shareId.String(),
			code:     http.StatusNotFound,
			cache:    "no-store",
			contains: []string{"This link isn't available"},
		},
		{
			name: "Provider failure",
			before: func() {
				shares.EXPECT().Page(gomock.Any(), shareId).Return(nil, errors.ErrFailedToFetchResults)
			},
			path:     "/s/" + shareId.String(),
			code:     http.StatusServiceUnavailable,
			cache:    "no-store",
			contains: []string{"This page can't load right now", `<header class="bar"><img src="` + icon + `"`},
		},
		{
			name: "Repository failure",
			before: func() {
				shares.EXPECT().Page(gomock.Any(), shareId).Return(nil, errors.ErrFailedToFetchShare)
			},
			path:     "/s/" + shareId.String(),
			code:     http.StatusServiceUnavailable,
			cache:    "no-store",
			contains: []string{"This page can't load right now"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			req := httptest.NewRequest(http.MethodGet, tt.path, nil)
			req = req.WithContext(context.WithValue(req.Context(), middlewares.CurrentUser{}, viewer))

			w := httptest.NewRecorder()

			handler := controller.HandleShow
			if tt.linked {
				handler = linked.HandleShow
			}

			r := chi.NewRouter()
			r.Get("/s/{id}", handler)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			body, err := io.ReadAll(resp.Body)
			require.NoError(t, err)

			assert.Equal(t, tt.code, resp.StatusCode)
			assert.Equal(t, "text/html; charset=utf-8", resp.Header.Get("Content-Type"))
			assert.Equal(t, tt.cache, resp.Header.Get("Cache-Control"))

			for _, text := range tt.contains {
				assert.Contains(t, string(body), text)
			}

			for _, text := range tt.absent {
				assert.NotContains(t, string(body), text)
			}
		})
	}
}
