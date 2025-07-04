package serializers

type TokenSerializer struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
}
