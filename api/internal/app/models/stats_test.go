package models

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func Test_StatsPeriod_String(t *testing.T) {
	assert.Equal(t, "week", StatsPeriodWeek.String())
	assert.Equal(t, "month", StatsPeriodMonth.String())
	assert.Equal(t, "year", StatsPeriodYear.String())
	assert.Equal(t, "all", StatsPeriodAll.String())
}

func Test_NewStatsPeriod(t *testing.T) {
	cases := []struct {
		name  string
		value string
		want  StatsPeriod
	}{
		{
			name:  "week",
			value: "week",
			want:  StatsPeriodWeek,
		},
		{
			name:  "month",
			value: "month",
			want:  StatsPeriodMonth,
		},
		{
			name:  "year",
			value: "year",
			want:  StatsPeriodYear,
		},
		{
			name:  "all",
			value: "all",
			want:  StatsPeriodAll,
		},
		{
			name:  "an omitted period covers all history",
			value: "",
			want:  StatsPeriodAll,
		},
		{
			name:  "an unknown period covers all history",
			value: "decade",
			want:  StatsPeriodAll,
		},
		{
			name:  "the match is case sensitive",
			value: "Week",
			want:  StatsPeriodAll,
		},
	}

	for _, tt := range cases {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, NewStatsPeriod(tt.value))
		})
	}
}
