#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'USAGE'
Start GPT-SoVITS API v2 with safe defaults.

Options:
  --bind <host>        Bind address (default: from $API_HOST or 127.0.0.1)
  --port <port>        Port (default: from $API_PORT or 9880)
  --config <path>      TTS config path (default: GPT_SoVITS/configs/tts_infer.yaml)
  --daemon             Run in background with nohup
  --no-autodetect      Skip device autodetect; use config as-is
  -h, --help           Show help

Reads .env at repo root if present.
USAGE
}

HOST_DEFAULT="${API_HOST:-127.0.0.1}"
PORT_DEFAULT="${API_PORT:-9880}"
CONFIG_DEFAULT="GPT_SoVITS/configs/tts_infer.yaml"

HOST="$HOST_DEFAULT"
PORT="$PORT_DEFAULT"
CONFIG="$CONFIG_DEFAULT"
DAEMON=false
AUTODETECT=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bind)
      HOST="$2"; shift 2;;
    --port)
      PORT="$2"; shift 2;;
    --config)
      CONFIG="$2"; shift 2;;
    --daemon)
      DAEMON=true; shift;;
    --no-autodetect)
      AUTODETECT=false; shift;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown argument: $1" >&2; usage; exit 1;;
  esac
done

# Load .env if available
if [[ -f .env ]]; then
  # shellcheck source=/dev/null
  set -a; source .env; set +a
  HOST="${HOST:-${API_HOST:-$HOST_DEFAULT}}"
  PORT="${PORT:-${API_PORT:-$PORT_DEFAULT}}"
fi

if [[ "$AUTODETECT" == "true" ]]; then
  python3 deploy/update_tts_config.py --config "$CONFIG" >/dev/null || true
fi

echo "Starting API v2 at ${HOST}:${PORT} with config ${CONFIG}"

mkdir -p logs
CMD=(python3 api_v2.py -a "$HOST" -p "$PORT" -c "$CONFIG")
if [[ "$DAEMON" == "true" ]]; then
  nohup "${CMD[@]}" > logs/api_v2.log 2>&1 &
  echo $! > logs/api_v2.pid
  echo "API started in background (PID $(cat logs/api_v2.pid)). Logs: logs/api_v2.log"
else
  exec "${CMD[@]}"
fi

