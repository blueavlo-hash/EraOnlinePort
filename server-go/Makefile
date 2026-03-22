# Era Online Go Server — Makefile
BINARY   = eraonline-server
CMD      = ./cmd/server
VERSION  = $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
LDFLAGS  = -s -w -X main.Version=$(VERSION)

.PHONY: all build build-linux run tidy test clean install deploy health setup-vps

## Default: build for the current OS.
all: build

## Build for the current OS/arch.
build:
	go build -ldflags "$(LDFLAGS)" -o $(BINARY) $(CMD)

## Cross-compile a static Linux amd64 binary (for VPS deployment).
build-linux:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
		go build -ldflags "$(LDFLAGS)" -o $(BINARY)-linux-amd64 $(CMD)

## Run in development mode with the default config.
run:
	go run $(CMD) --config config/server.yaml

## Download dependencies.
tidy:
	go mod tidy
	go mod download

## Run tests.
test:
	go test ./...

## Remove build artifacts.
clean:
	rm -f $(BINARY) $(BINARY)-linux-amd64

## Install the systemd service (run as root on the VPS).
install:
	@echo "Installing to /opt/eraonline..."
	install -d /opt/eraonline/config
	install -m 755 $(BINARY)-linux-amd64 /opt/eraonline/$(BINARY)
	install -m 640 config/server.yaml /opt/eraonline/config/server.yaml
	install -m 644 deploy/eraonline-server.service /etc/systemd/system/
	systemctl daemon-reload
	@echo "Done. Run: systemctl enable --now eraonline-server"

## Deploy to a VPS. Usage: make deploy VPS=user@ip
## Example: make deploy VPS=root@203.0.113.10
deploy:
	@if [ -z "$(VPS)" ]; then \
		echo "Error: VPS target is required. Usage: make deploy VPS=user@ip"; \
		exit 1; \
	fi
	./deploy/build-and-deploy.sh $(VPS)

## Run the health check against a running server (local or remote).
## Usage: make health                         (checks localhost)
##        make health VPS=root@203.0.113.10  (checks remote server)
health:
	@if [ -n "$(VPS)" ]; then \
		ssh $(VPS) "/opt/eraonline/health-check.sh"; \
	else \
		./deploy/health-check.sh; \
	fi

## Run the first-time VPS setup script on the target server.
## Usage: make setup-vps VPS=root@203.0.113.10
setup-vps:
	@if [ -z "$(VPS)" ]; then \
		echo "Error: VPS target is required. Usage: make setup-vps VPS=user@ip"; \
		exit 1; \
	fi
	scp -r deploy/ $(VPS):/tmp/eo3-deploy/
	ssh $(VPS) "bash /tmp/eo3-deploy/setup-vps.sh"
