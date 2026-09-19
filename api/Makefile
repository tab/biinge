DB_USER=postgres
DB_DEV_NAME=biinge-development
DB_TEST_NAME=biinge-test
DB_PROD_NAME=biinge-production
DB_HOST=localhost
DB_PORT=5432

DB_SERVICE_NAME=database

GOOSE_DRIVER=postgres
GOOSE_MIGRATION_DIR=db/migrate

GO_ENV ?= development
BASE ?= origin/master
DOCKER_COMPOSE_CMD=docker compose
INFRA_NETWORK=biinge-network

ifeq ($(GO_ENV),test)
	ENV_FILE=.env.test
	LOCAL_ENV_FILE=.env.test.local
	DB_NAME=$(DB_TEST_NAME)
	ifeq ($(DATABASE_DSN),)
		GOOSE_DBSTRING="host=$(DB_HOST) port=$(DB_PORT) user=$(DB_USER) password=$(DB_USER) dbname=$(DB_TEST_NAME) sslmode=disable"
	else
		GOOSE_DBSTRING=$(DATABASE_DSN)
	endif
else ifeq ($(GO_ENV),production)
	ENV_FILE=.env.production
	LOCAL_ENV_FILE=.env.production.local
	DB_NAME=$(DB_PROD_NAME)
	ifeq ($(DATABASE_DSN),)
		GOOSE_DBSTRING="host=$(DB_HOST) port=$(DB_PORT) user=$(DB_USER) password=$(DB_USER) dbname=$(DB_PROD_NAME) sslmode=disable"
	else
		GOOSE_DBSTRING=$(DATABASE_DSN)
	endif
else
	ENV_FILE=.env.development
	LOCAL_ENV_FILE=.env.development.local
	DB_NAME=$(DB_DEV_NAME)
	ifeq ($(DATABASE_DSN),)
		GOOSE_DBSTRING="host=$(DB_HOST) port=$(DB_PORT) user=$(DB_USER) password=$(DB_USER) dbname=$(DB_DEV_NAME) sslmode=disable"
	else
		GOOSE_DBSTRING=$(DATABASE_DSN)
	endif
endif

ifneq (,$(wildcard $(ENV_FILE)))
	include $(ENV_FILE)
	export $(shell sed 's/=.*//' $(ENV_FILE))
endif

ifneq (,$(wildcard $(LOCAL_ENV_FILE)))
	include $(LOCAL_ENV_FILE)
	export $(shell sed 's/=.*//' $(LOCAL_ENV_FILE))
endif

.PHONY: db\:create
db\:create:
	@echo "Creating $(DB_NAME) database..."
	docker-compose exec -T $(DB_SERVICE_NAME) createdb -U $(DB_USER) $(DB_NAME)

.PHONY: db\:drop
db\:drop:
	@echo "Dropping $(DB_NAME) database..."
	docker-compose exec -T $(DB_SERVICE_NAME) dropdb -U $(DB_USER) --if-exists $(DB_NAME)

.PHONY: db\:migrate
db\:migrate:
	@echo "Applying migrations to $(DB_NAME) database..."
	GOOSE_DRIVER=$(GOOSE_DRIVER) GOOSE_DBSTRING=$(GOOSE_DBSTRING) goose -dir $(GOOSE_MIGRATION_DIR) up

.PHONY: db\:migrate\:status
db\:migrate\:status:
	@echo "Migration status in $(DB_NAME) database..."
	GOOSE_DRIVER=$(GOOSE_DRIVER) GOOSE_DBSTRING=$(GOOSE_DBSTRING) goose -dir $(GOOSE_MIGRATION_DIR) status

.PHONY: db\:rollback
db\:rollback:
	@echo "Rolling back last migration in $(DB_NAME) database..."
	GOOSE_DRIVER=$(GOOSE_DRIVER) GOOSE_DBSTRING=$(GOOSE_DBSTRING) goose -dir $(GOOSE_MIGRATION_DIR) down

.PHONY: db\:schema\:dump
db\:schema\:dump:
	@echo "Dumping database schema from $(DB_NAME) to db/schema.sql..."
	docker-compose exec -T $(DB_SERVICE_NAME) pg_dump -U $(DB_USER) -d $(DB_NAME) --schema-only --no-owner --no-privileges --exclude-table=goose_db_version > db/schema.sql

.PHONY: db\:schema\:load
db\:schema\:load:
	@echo "Loading schema from db/schema.sql into $(DB_NAME) database..."
	cat db/schema.sql | docker-compose exec -T $(DB_SERVICE_NAME) psql -U $(DB_USER) -d $(DB_NAME)

.PHONY: run
run:
	@echo "Starting biinge app..."
	$(DOCKER_COMPOSE_CMD) up -d

.PHONY: stop
stop:
	@echo "Stopping biinge app..."
	$(DOCKER_COMPOSE_CMD) down

.PHONY: logs
logs:
	@echo "Showing logs..."
	$(DOCKER_COMPOSE_CMD) logs -f

.PHONY: fmt
fmt:
	@echo "Formatting code..."
	go fmt ./...

.PHONY: lint
lint:
	@echo "Running golangci-lint..."
	golangci-lint run

.PHONY: lint\:fix
lint\:fix:
	@echo "Running golangci-lint --fix ..."
	golangci-lint run --fix

.PHONY: doc-comments
doc-comments:
	@echo "Checking doc comments..."
	@../.github/scripts/doc-comments.sh api

# Compares against BASE, so it needs the branch history rather than a shallow clone
.PHONY: drift
drift:
	@echo "Checking schema and spec drift..."
	@../.github/scripts/schema.sh $(BASE)
	@../.github/scripts/swagger.sh $(BASE)

.PHONY: vet
vet:
	@echo "Running go vet..."
	go vet ./...

.PHONY: staticcheck
staticcheck:
	@echo "Running staticcheck..."
	go run honnef.co/go/tools/cmd/staticcheck@latest ./...

.PHONY: test
test:
	@echo "Running tests..."
	GO_ENV=test go test -p=1 -cover ./...

.PHONY: test\:race
test\:race:
	@echo "Running tests with race detector..."
	GO_ENV=test go test -p=1 -race -cover -coverprofile=coverage.out -covermode=atomic ./...

.PHONY: coverage
coverage:
	@echo "Generating test coverage report..."
	GO_ENV=test go test -p=1 ./... -coverprofile=coverage.out && go tool cover -html=coverage.out

# Full verification loop — run before committing to catch everything CI checks.
# Steps are invoked via recursive $(MAKE) so the colon-named test:race target
# resolves reliably; escaped-colon names silently no-op as prerequisites.
.PHONY: check
check:
	@$(MAKE) fmt
	@$(MAKE) lint
	@$(MAKE) doc-comments
	@$(MAKE) test
	@$(MAKE) test:race
	@echo "✓ All checks passed"

.PHONY: all
all: check
