package models

import (
	"encoding/json"

	"github.com/google/uuid"
)

// WebhookStatus is what biinge did with a stored webhook event
type WebhookStatus string

const (
	WebhookStatusMarked     WebhookStatus = "marked"
	WebhookStatusIgnored    WebhookStatus = "ignored"
	WebhookStatusUnresolved WebhookStatus = "unresolved"
	WebhookStatusFailed     WebhookStatus = "failed"
)

// Webhook is one stored event with its raw payload and status
type Webhook struct {
	IntegrationId uuid.UUID
	Payload       json.RawMessage
	Status        WebhookStatus
	Error         string
}
