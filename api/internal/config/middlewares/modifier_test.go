package middlewares

import (
    "context"
    "testing"

    "github.com/stretchr/testify/assert"
)

func Test_NewContextModifier(t *testing.T) {
    ctx := context.Background()
    ctxModifier := NewContextModifier(ctx)

    assert.NotNil(t, ctxModifier)
    assert.Equal(t, ctx, ctxModifier.Context())
}

func Test_Modifier_WithTraceId(t *testing.T) {
    ctx := context.Background()

    tests := []struct {
        name    string
        traceId string
    }{
        {
            name:    "Valid trace ID",
            traceId: "valid-trace-id",
        },
        {
            name:    "Empty trace ID",
            traceId: "",
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            ctxModifier := NewContextModifier(ctx).WithTraceId(tt.traceId)

            traceId, ok := ctxModifier.Context().Value(TraceId{}).(string)
            assert.True(t, ok)
            assert.Equal(t, tt.traceId, traceId)
        })
    }
}
