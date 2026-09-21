package serializers

// IntegrationTokenSerializer carries a freshly generated integration token, shown once
type IntegrationTokenSerializer struct {
	Token string `json:"token"`
}
