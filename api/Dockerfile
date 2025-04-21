FROM golang:1.24.1-alpine3.21 AS builder

ENV CGO_ENABLED=0

RUN apk add --no-cache --update git tzdata ca-certificates

WORKDIR /app

COPY go.mod go.sum ./

COPY . ./
RUN go build -o /app/biinge /app/cmd/biinge/main.go

FROM alpine:3.21

WORKDIR /app

COPY --from=builder /app/biinge /app/biinge

CMD ["/app/biinge"]
