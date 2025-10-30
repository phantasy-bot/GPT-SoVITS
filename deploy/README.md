Overview

- Provides a reproducible deployment workflow for GPT-SoVITS: download models, fetch voice samples from Cloudflare R2, and start API v2 for one‑shot voice cloning.
- Everything lives under deploy/ and uses env vars for credentials; nothing sensitive is committed.

Quick Start

- Prereqs: Python 3.10+, pip; FFmpeg in PATH; optional conda. For GPU, install a matching CUDA/driver first.
- Copy env and configure R2:
  - cp .env.example .env and fill R2 credentials.
  - cp deploy/voices.example.yaml deploy/voices.yaml and edit samples.
- Fetch voices: python deploy/fetch_r2_voices.py --config deploy/voices.yaml
- Download models and deps (conda users): bash install.sh --device <CU126|CU128|ROCM|MPS|CPU> --source <HF|HF-Mirror|ModelScope>
- Or minimal pip install (CPU): pip install -r extra-req.txt --no-deps && pip install -r requirements.txt
- Start API v2: bash deploy/start_api.sh --bind 0.0.0.0 --port 9880

R2 Voice Samples

- Voices YAML organizes characters, languages, and emotion/sample variants. Supported language codes for API: en, ja, ko, zh. Aliases handled: jp->ja, kr->ko, cn->zh.
- Files download to assets/voices/<character>/<lang>/<name>.wav and an index is generated at assets/voices/voices_index.json.

Example voices.yaml

- See deploy/voices.example.yaml. Example minimal structure:
- characters:
  rally:
    en:
      - name: default
        key: rally-en-default.wav
    jp:
      - name: happy
        key: alchemist-jp-happy.wav

Security

- Credentials come from env vars in .env; do not commit them.
- API binds to 127.0.0.1 by default. Use a reverse proxy (nginx/caddy) and TLS, or set firewall rules if binding publicly.
- Limit file permissions on .env and assets/voices/.

Systemd (optional)

- See deploy/systemd/gpt-sovits-api.service for a template unit. Adjust paths, user, and ExecStart as needed, then:
- sudo cp deploy/systemd/gpt-sovits-api.service /etc/systemd/system/
- sudo systemctl daemon-reload && sudo systemctl enable --now gpt-sovits-api

API Usage

- GET example:
- curl "http://127.0.0.1:9880/tts?text=Hello&text_lang=en&ref_audio_path=assets/voices/rally/en/default.wav&prompt_lang=en&prompt_text=Hello"

Cloning To New Servers

- git clone <your fork>; cp .env; prepare voices.yaml; run fetch_r2_voices.py; install models via install.sh or pip; start API.

Notes

- Models are placed under GPT_SoVITS/pretrained_models; defaults are configured in GPT_SoVITS/configs/tts_infer.yaml.
- For Chinese TTS tools (G2PW), install.sh can download extras; see README.md for ASR/UVR5 optional models.

Cloudflare Tunnel + Access

- Keep the API bound to localhost (default 127.0.0.1). Expose it securely via Cloudflare Tunnel and protect with Zero Trust Access.
- See deploy/cloudflare/ for a ready config and step‑by‑step guide.
- Quick flow:
  - Install cloudflared on the server.
  - Create a named tunnel, map hostname to http://localhost:9880, and start cloudflared as a service.
  - In Zero Trust > Access > Applications, add a Self‑hosted app for your hostname (e.g., tts.example.com) and add policies (emails/groups).
