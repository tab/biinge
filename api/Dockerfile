FROM golang:1.26.5-alpine AS builder

ENV CGO_ENABLED=0

RUN apk add --no-cache --update git tzdata ca-certificates

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . ./
RUN go build -o /app/biinge /app/cmd/biinge/main.go

FROM alpine:3.24

WORKDIR /app

# baked at build time so Sentry can tag events with the released version
ARG APP_VERSION
ENV APP_VERSION=${APP_VERSION}

COPY --from=builder /app/biinge /app/biinge

CMD ["/app/biinge"]
