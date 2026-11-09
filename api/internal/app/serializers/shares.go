package serializers

import (
	"encoding/json"
	"io"

	"github.com/google/uuid"

	"biinge-api/internal/app/models"
)

// CreateShareRequestSerializer names the title to share (object_id is the TMDB id of a movie or series, or the IGDB id of a game)
type CreateShareRequestSerializer struct {
	Type models.ShareType `json:"type" validate:"required,oneof=movie tv game"`
	// the shares column is an INTEGER, so larger ids are rejected here rather than at the write
	ObjectId uint64 `json:"object_id" validate:"required,min=1,max=2147483647"`
}

func (params *CreateShareRequestSerializer) Validate(body io.Reader) error {
	if err := json.NewDecoder(body).Decode(params); err != nil {
		return err
	}

	return validate.Struct(params)
}

// ShareSerializer is a created share and its public link
type ShareSerializer struct {
	Id  uuid.UUID `json:"id"`
	URL string    `json:"url"`
}

// SharePageSerializer is what the public share page shows of a title (empty fields stay off the page)
type SharePageSerializer struct {
	// Kind is the label over the title ("Movie", "TV Show" or "Game")
	Kind  string
	Title string
	// Year goes into the document title and og:title
	Year string
	// Meta is the line under the title, its parts joined with " · " as the apps show it
	Meta     string
	Rating   string
	Overview string
	// Description is the overview cut for og:description
	Description string
	ImageURL    string
	Facts       []ShareFactSerializer
	Seasons     []ShareSeasonSerializer
	Credits     []ShareCreditSerializer
	Genres      []string
	Platforms   []string
}

// ShareFactSerializer is one label and value of the share page's facts
type ShareFactSerializer struct {
	Label string
	Value string
}

// ShareSeasonSerializer is one season of a series on the share page (Year is empty without an air date)
type ShareSeasonSerializer struct {
	Name     string
	Year     string
	Episodes string
}

// ShareCreditSerializer is one Cast & Crew person on the share page
type ShareCreditSerializer struct {
	Name     string
	Role     string
	PhotoURL string
}
