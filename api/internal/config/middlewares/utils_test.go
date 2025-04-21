package middlewares

import (
    "context"
    "testing"

    "github.com/stretchr/testify/assert"
)

func Test_CurrentTraceIdFromContext(t *testing.T) {
    tests := []struct {
        name    string
        ctx     context.Context
        traceId string
        exists  bool
    }{
        {
            name:    "Success",
            ctx:     context.WithValue(context.Background(), TraceId{}, "9809b3e0-484b-438c-80b2-73cb9af51cd4"),
            traceId: "9809b3e0-484b-438c-80b2-73cb9af51cd4",
            exists:  true,
        },
        {
            name:    "TraceId does not exist",
            ctx:     context.Background(),
            traceId: "",
            exists:  false,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            traceId, exists := CurrentTraceIdFromContext(tt.ctx)
            assert.Equal(t, tt.exists, exists)

            if tt.exists {
                assert.Equal(t, tt.traceId, traceId)
            } else {
                assert.Empty(t, traceId)
            }
        })
    }
}
