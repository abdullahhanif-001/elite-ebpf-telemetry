# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# CONTAINER_TOOL defines the container tool to be used for building images.
# Be aware that the target commands are only tested with Docker which is
# scaffolded by default. However, you might want to replace it to use other
# tools. (i.e. podman)
CONTAINER_TOOL ?= docker
BUILDER_IMAGE ?= kubeskoop/ci-builder:go125clang211

# Setting SHELL to bash allows bash commands to be executed by recipes.
# This is a requirement for 'setup-envtest.sh' in the test target.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec
VERSION_PKG=github.com/alibaba/kubeskoop/version
TARGETOS?=linux
TARGETARCH?=amd64

TAG?=${shell git describe --tags --abbrev=7}
GIT_COMMIT=${shell git rev-parse HEAD}
ldflags="-X $(VERSION_PKG).Version=$(TAG) -X $(VERSION_PKG).Commit=${GIT_COMMIT} -w -s"

.PHONY: all
all: build-exporter build-skoop build-controller build-collector build-btfhack build-webconsole

##@ General

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

##@ Build

.PHONY: build-exporter build-elite-agent
build-exporter build-elite-agent: ## Build Elite telemetry agent binary (bin/elite-agent).
	CGO_ENABLED=0 go build -o bin/elite-agent -ldflags $(ldflags) ./cmd/exporter

.PHONY: build-elite-updater
build-elite-updater: ## Build Elite auto-updater (bin/elite-updater).
	CGO_ENABLED=0 go build -o bin/elite-updater -ldflags $(ldflags) ./cmd/elite-updater

.PHONY: build-elite-dcic
build-elite-dcic: ## Build Soft DCIC binary.
	CGO_ENABLED=0 go build -o bin/elite-dcic -ldflags $(ldflags) ./cmd/elite-dcic

.PHONY: build-elite-ecgf
build-elite-ecgf: ## Build ECGF-lite binary.
	CGO_ENABLED=0 go build -o bin/elite-ecgf -ldflags $(ldflags) ./cmd/elite-ecgf

.PHONY: build-skoop
build-skoop: ## Build skoop binary.
	cd cmd/skoop && CGO_ENABLED=0 go build -o ../../bin/skoop -ldflags $(ldflags) .

.PHONY: build-collector
build-collector: ## Build collector binary.
	cd cmd/collector && CGO_ENABLED=0 go build -o ../../bin/pod-collector -ldflags $(ldflags) .

.PHONY: build-controller
build-controller: ## Build controller binary.
	cd cmd/controller && CGO_ENABLED=0 go build -o ../../bin/controller -ldflags $(ldflags) .

.PHONY: build-btfhack
build-btfhack: ## Build btfhack binary.
	CGO_ENABLED=0 go build -o bin/btfhack -ldflags $(ldflags) ./cmd/btfhack

.PHONY: build-webconsole
build-webconsole: ## Build webconsole binary.
	cd webui && CGO_ENABLED=0 go build -o ../bin/webconsole -ldflags $(ldflags) .

##@ Dependencies
ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: generate-bpf
generate-bpf: ## Generate bpf (core probes; connecttrace BPF is optional via generate-connect-bpf).
	cd tools/bpf2go && go install -mod=readonly github.com/cilium/ebpf/cmd/bpf2go
	PATH="$$(go env GOPATH)/bin:$$PATH" go generate ./pkg/exporter/probe/...

.PHONY: generate-connect-bpf
generate-connect-bpf: ## Generate connect_trace bpf only.
	cd pkg/exporter/probe/traceconnect && GOARCH=amd64 go generate .

.PHONY: build-builder
build-builder: ## Build the local BPF builder image.
	$(CONTAINER_TOOL) build --build-arg GOPROXY="$(GOPROXY)" -f tools/builder/Dockerfile -t $(BUILDER_IMAGE) .

.PHONY: generate-bpf-in-container
generate-bpf-in-container: build-builder ## Generate bpf in container.
	$(CONTAINER_TOOL) run --rm -v $(PWD):/go/src/github.com/alibaba/kubeskoop --workdir /go/src/github.com/alibaba/kubeskoop $(BUILDER_IMAGE) make generate-bpf
