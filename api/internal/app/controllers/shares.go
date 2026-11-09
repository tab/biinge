package controllers

import (
	_ "embed"
	"encoding/base64"
	"encoding/json"
	"html/template"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config"
	"biinge-api/internal/config/middlewares"
)

//go:embed templates/share.html
var shareTemplate string

//go:embed templates/icon.png
var shareIcon []byte

type SharesController interface {
	HandleCreate(w http.ResponseWriter, r *http.Request)
	HandleShow(w http.ResponseWriter, r *http.Request)
}

type sharesController struct {
	shares    services.Shares
	templates *template.Template
}

func NewSharesController(cfg *config.Config, shares services.Shares) SharesController {
	// the app icon rides inline as a data URI, so the page needs no route of its own for it
	//nolint:gosec // the URL is the icon embedded in the binary, never request input
	icon := template.URL("data:image/png;base64," + base64.StdEncoding.EncodeToString(shareIcon))

	return &sharesController{
		shares: shares,
		templates: template.Must(template.New("share").Funcs(template.FuncMap{
			"icon": func() template.URL { return icon },
			"site": func() string { return cfg.SiteURL },
		}).Parse(shareTemplate)),
	}
}

// HandleCreate shares a title and returns its link (201 for a new share and a re-share alike, which keeps its id)
func (c *sharesController) HandleCreate(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.ErrUnauthorized)
		return
	}

	var params serializers.CreateShareRequestSerializer
	if err := params.Validate(r.Body); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	response, err := c.shares.Create(r.Context(), &models.Share{
		UserId:   user.ID,
		Type:     params.Type,
		ObjectId: params.ObjectId,
	})
	if err != nil {
		switch {
		case errors.Is(err, errors.ErrShareObjectNotFound):
			writeError(w, http.StatusNotFound, err)
		default:
			writeError(w, http.StatusUnprocessableEntity, err)
		}

		return
	}

	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(response)
}

// HandleShow renders the public page of a live share (the not-found page for a malformed, unknown or expired id)
func (c *sharesController) HandleShow(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")

	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		w.Header().Set("Cache-Control", "no-store")
		w.WriteHeader(http.StatusNotFound)
		_ = c.templates.ExecuteTemplate(w, "not_found", nil)

		return
	}

	page, err := c.shares.Page(r.Context(), id)
	if err != nil {
		// a re-share brings an expired id back, and an outage passes, so neither page is cached
		w.Header().Set("Cache-Control", "no-store")

		switch {
		case errors.Is(err, errors.ErrShareNotFound):
			w.WriteHeader(http.StatusNotFound)
			_ = c.templates.ExecuteTemplate(w, "not_found", nil)
		default:
			w.WriteHeader(http.StatusServiceUnavailable)
			_ = c.templates.ExecuteTemplate(w, "unavailable", nil)
		}

		return
	}

	w.Header().Set("Cache-Control", "public, max-age=86400")
	w.WriteHeader(http.StatusOK)
	_ = c.templates.ExecuteTemplate(w, "page", page)
}
