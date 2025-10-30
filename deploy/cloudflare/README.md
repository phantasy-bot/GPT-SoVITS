Cloudflare Tunnel + Access

Goal: keep api_v2 bound to localhost and expose it securely over a Cloudflare Tunnel protected by Zero Trust Access.

Prereqs

- A domain on Cloudflare and Zero Trust enabled.
- cloudflared installed on your server.
  - Debian/Ubuntu: curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o cloudflared.deb && sudo dpkg -i cloudflared.deb
  - See Cloudflare docs for other OS/architectures.

Run the API locally

- Keep it on localhost for safety (default):
- make api HOST=127.0.0.1 PORT=9880

Option A: Named Tunnel (recommended)

1) Authenticate and create a tunnel

- cloudflared login
- cloudflared tunnel create gpt-sovits
  - Note the credentials file path it prints (e.g., /etc/cloudflared/<UUID>.json) and the tunnel UUID.

2) Configure ingress to localhost:9880

- Copy deploy/cloudflare/config.example.yml to /etc/cloudflared/config.yml and edit:
  - Set tunnel: to your tunnel UUID or name (e.g., gpt-sovits)
  - Ensure service: http://localhost:9880 under ingress for your hostname

3) Route DNS

- cloudflared tunnel route dns gpt-sovits tts.example.com

4) Run as a service

- sudo cloudflared service install
- sudo systemctl enable --now cloudflared
- Check status: systemctl status cloudflared; logs: journalctl -u cloudflared -f

Option B: Token-based Quick Tunnel

- In Cloudflare Zero Trust > Networks > Tunnels, create a tunnel and copy the token.
- Run: cloudflared tunnel --no-autoupdate run --token <TUNNEL_TOKEN>
- Add a public hostname in the tunnel config pointing to http://localhost:9880.

Protect with Cloudflare Access

1) Add application

- Zero Trust > Access > Applications > Add an application > Self-hosted
- Application domain: tts.example.com
- Session duration: as needed (e.g., 24 hours)

2) Policy

- Add Include rules (emails, IdP groups, or login methods) to allow your team.
- Optionally add device posture or country restrictions.

3) Test

- Visit https://tts.example.com/tts?text=Hello&text_lang=en&ref_audio_path=assets/voices/rally/en/default.wav&prompt_lang=en&prompt_text=Hello
- You should be prompted for Access login and then receive audio.

Notes

- API remains bound to 127.0.0.1; do not open firewall ports.
- For long/streaming responses, default Tunnel settings usually work; adjust Cloudflare timeouts if your requests exceed ~100s.
- If you run in Docker, ensure the cloudflared container/network can reach the service at the same host/port (use host.docker.internal or network aliases as appropriate).

