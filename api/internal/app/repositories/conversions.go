package repositories

import (
	"time"

	"github.com/jackc/pgx/v5/pgtype"
)

// toInt32Slice converts a slice of uint64 identifiers (used across the domain
// models) into the []int32 representation expected by the sqlc-generated
// `= ANY($1::integer[])` query parameters.
func toInt32Slice(ids []uint64) []int32 {
	result := make([]int32, len(ids))
	for i, id := range ids {
		result[i] = int32(id)
	}
	return result
}

// timestampFromTime maps a domain time.Time into a nullable pgtype.Timestamp,
// treating the zero time as SQL NULL (e.g. an episode without an air date).
func timestampFromTime(t time.Time) pgtype.Timestamp {
	if t.IsZero() {
		return pgtype.Timestamp{Valid: false}
	}
	return pgtype.Timestamp{Time: t, Valid: true}
}
