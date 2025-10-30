SHELL := bash

.PHONY: help install voices api api-daemon stop bootstrap fmt

DEVICE ?=
SOURCE ?=
UVR5 ?= false
VOICES_CONFIG ?= deploy/voices.yaml
HOST ?= $(or $(API_HOST),127.0.0.1)
PORT ?= $(or $(API_PORT),9880)

help:
	@echo "Targets:"
	@echo "  install        Install models/deps via install.sh (requires conda)"
	@echo "                Vars: DEVICE=<CU126|CU128|ROCM|MPS|CPU> SOURCE=<HF|HF-Mirror|ModelScope> UVR5=true"
	@echo "  voices         Fetch voice samples from R2/HTTP per voices.yaml"
	@echo "                Vars: VOICES_CONFIG=deploy/voices.yaml"
	@echo "  api            Start API v2 in foreground"
	@echo "                Vars: HOST=$(HOST) PORT=$(PORT)"
	@echo "  api-daemon     Start API v2 in background (nohup)"
	@echo "                Vars: HOST=$(HOST) PORT=$(PORT)"
	@echo "  stop           Stop background API (if running)"
	@echo "  bootstrap      Install (optional) + voices + start"
	@echo "                Vars: DEVICE, SOURCE, UVR5, VOICES_CONFIG, HOST, PORT"

install:
	@if [[ -z "$(DEVICE)" || -z "$(SOURCE)" ]]; then \
		echo "Usage: make install DEVICE=<...> SOURCE=<...> [UVR5=true]"; \
		exit 1; \
	fi
	bash install.sh --device $(DEVICE) --source $(SOURCE) $(if $(filter true,$(UVR5)),--download-uvr5,)

voices:
	@pip3 show boto3 >/dev/null 2>&1 || pip3 install -r deploy/requirements.txt
	python3 deploy/fetch_r2_voices.py --config $(VOICES_CONFIG)

api:
	bash deploy/start_api.sh --bind $(HOST) --port $(PORT)

api-daemon:
	bash deploy/start_api.sh --bind $(HOST) --port $(PORT) --daemon

stop:
	@if [[ -f logs/api_v2.pid ]]; then \
		PID=$$(cat logs/api_v2.pid); \
		echo "Stopping API (PID $$PID)"; \
		kill $$PID || true; \
		rm -f logs/api_v2.pid; \
	else \
		echo "No PID file at logs/api_v2.pid"; \
	fi

bootstrap:
	@set -e; \
	ARGS=(); \
	if [[ -n "$(DEVICE)" && -n "$(SOURCE)" ]]; then \
		ARGS+=(--device "$(DEVICE)" --source "$(SOURCE)"); \
		if [[ "$(UVR5)" == "true" ]]; then ARGS+=(--download-uvr5); fi; \
	else \
		ARGS+=(--skip-models); \
	fi; \
	if [[ -n "$(VOICES_CONFIG)" ]]; then ARGS+=(--fetch-voices --voices-config "$(VOICES_CONFIG)"); fi; \
	ARGS+=(--start --bind "$(HOST)" --port "$(PORT)"); \
	bash deploy/bootstrap.sh "$${ARGS[@]}"

