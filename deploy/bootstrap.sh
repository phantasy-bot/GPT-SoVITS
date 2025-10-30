#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Bootstrap deployment: models, voices, API v2.

Steps:
  1) Install models/dependencies via install.sh (conda) or skip
  2) Fetch voice samples from Cloudflare R2 per voices.yaml
  3) Start API v2

Options:
  --device <CU126|CU128|ROCM|MPS|CPU>  Device for install.sh
  --source <HF|HF-Mirror|ModelScope>   Model source for install.sh
  --download-uvr5                      Also fetch UVR5 models (optional)
  --skip-models                        Skip running install.sh
  --no-conda                           Do not use conda/install.sh
  --voices-config <path>               Path to voices.yaml (default: deploy/voices.yaml if exists)
  --fetch-voices                       Run voices fetch step
  --start                              Start API after setup
  --bind <host>                        API bind address (default from .env or 127.0.0.1)
  --port <port>                        API port (default from .env or 9880)
  -h, --help                           Show help

Examples:
  bash deploy/bootstrap.sh --device CU128 --source HF --fetch-voices --start --bind 0.0.0.0 --port 9880
USAGE
}

DEVICE=""
SOURCE=""
DOWNLOAD_UVR5=false
SKIP_MODELS=false
NO_CONDA=false
VOICES_CONFIG=""
FETCH_VOICES=false
START=false
BIND="${API_HOST:-}"
PORT="${API_PORT:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2;;
    --source) SOURCE="$2"; shift 2;;
    --download-uvr5) DOWNLOAD_UVR5=true; shift;;
    --skip-models) SKIP_MODELS=true; shift;;
    --no-conda) NO_CONDA=true; shift;;
    --voices-config) VOICES_CONFIG="$2"; shift 2;;
    --fetch-voices) FETCH_VOICES=true; shift;;
    --start) START=true; shift;;
    --bind) BIND="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1;;
  esac
done

# 1) Models and dependencies via install.sh (conda)
if [[ "$SKIP_MODELS" == "false" ]]; then
  if [[ "$NO_CONDA" == "false" && -x "$(command -v conda || true)" ]]; then
    if [[ -z "$DEVICE" || -z "$SOURCE" ]]; then
      echo "[ERROR] --device and --source are required for install.sh" >&2
      usage; exit 1
    fi
    ARGS=(--device "$DEVICE" --source "$SOURCE")
    if [[ "$DOWNLOAD_UVR5" == "true" ]]; then ARGS+=(--download-uvr5); fi
    bash install.sh "${ARGS[@]}"
  else
    echo "[INFO] conda not available or --no-conda set; skipping install.sh"
    echo "[INFO] Ensure you have installed dependencies via pip and downloaded pretrained models per README.md"
  fi
fi

# 2) Fetch voices via R2
if [[ "$FETCH_VOICES" == "true" ]]; then
  VC="${VOICES_CONFIG:-}"
  if [[ -z "$VC" && -f deploy/voices.yaml ]]; then
    VC="deploy/voices.yaml"
  fi
  if [[ -z "$VC" ]]; then
    echo "[ERROR] voices config not provided. Use --voices-config <path> or create deploy/voices.yaml" >&2
    exit 1
  fi
  # Ensure deploy requirements for fetching voices
  python3 -c "import boto3" >/dev/null 2>&1 || pip3 install -r deploy/requirements.txt
  python3 deploy/fetch_r2_voices.py --config "$VC"
fi

# 3) Start API
if [[ "$START" == "true" ]]; then
  ARGS=( )
  [[ -n "$BIND" ]] && ARGS+=(--bind "$BIND")
  [[ -n "$PORT" ]] && ARGS+=(--port "$PORT")
  bash deploy/start_api.sh "${ARGS[@]}"
fi

echo "[DONE] bootstrap complete"

