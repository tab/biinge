package models

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func Test_Appearance_String(t *testing.T) {
	assert.Equal(t, "system", DefaultAppearance.String())
	assert.Equal(t, "light", LightAppearance.String())
	assert.Equal(t, "dark", DarkAppearance.String())
}
