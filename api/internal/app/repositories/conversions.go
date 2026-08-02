package repositories

import (
	"time"

	"github.com/jackc/pgx/v5/pgtype"
)

// toInt32Slice converts uint64 ids into the []int32 expected by ANY($1::integer[]) params
func toInt32Slice(ids []uint64) []int32 {
	result := make([]int32, len(ids))
	for i, id := range ids {
		result[i] = int32(id)
	}

	return result
}

// timestampFromTime maps a time.Time into a nullable pgtype.Timestamptz (zero time → SQL NULL)
func timestampFromTime(t time.Time) pgtype.Timestamptz {
	if t.IsZero() {
		return pgtype.Timestamptz{Valid: false}
	}

	return pgtype.Timestamptz{Time: t, Valid: true}
}
