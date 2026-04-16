<p align="center">
  <img src="assets/logo.png" alt="Claude Phone" width="200">
</p>

# Claude Phone — Self-Hosted (Kamailio)

Voice interface for Claude Code using a fully self-hosted SIP stack. Call your AI, and your AI can call you — no cloud PBX required.

## What is this?

Claude Phone gives your Claude Code installation a phone number. You can:

- **Inbound**: Call an extension and talk to Claude — run commands, check server status, ask questions
- **Outbound**: Your server can call YOU with alerts, then hold a full conversation about what to do
- **Multi-extension**: Each SIP extension gets its own AI personality, name, and voice

## How it works

```
Softphone (Linphone / Zoiper / Bria)
        │  REGISTER / INVITE  (SIP :5060)
        ▼
  ┌─────────────────────────────────────────────────────────┐
  │  HOST NETWORK (all containers bind to the real NIC)     │
  │                                                         │
  │  [KAMAILIO :5060]  ──INVITE──►  [DRACHTIO :5070]       │
  │   SIP registrar + proxy          SIP application server │
  │                                         │               │
  │                                  [FREESWITCH :5080]     │
  │                                   RTP 30000–30100       │
  │                                         │               │
  │                                  [VOICE-APP :3000]      │
  │                                   Node.js orchestrator  │
  └─────────────────────────────────────────────────────────┘
                                            │  HTTP
                               [CLAUDE-API-SERVER :3333]
                                Native Node.js on host
                                (spawns `claude` CLI)
                                            │
                                   Claude Pro / Max subscription
```

**Port layout**

| Service | Port | Role |
|---|---|---|
| Kamailio | 5060 UDP/TCP | SIP registrar + proxy |
| drachtio | 5070 UDP | SIP app server (AI call handler) |
| FreeSWITCH | 5080 / 30000–30100 | RTP media |
| voice-app | 3000 HTTP / 3001 WS | API + audio fork |
| claude-api-server | 3333 HTTP | Claude CLI wrapper (runs natively) |

## Prerequisites

| Requirement | Notes |
|---|---|
| **Docker + Docker Compose** | v2.x or later |
| **Node.js 18+** | For `claude-api-server` (runs natively) |
| **Claude Code CLI** (`claude`) | `npm i -g @anthropic-ai/claude-code` — Claude Pro or Max subscription |
| **ElevenLabs API key** | Text-to-speech |
| **OpenAI API key** | Whisper speech-to-text |
| **A SIP softphone** | Linphone, Zoiper, or Bria to place / receive calls |

## Platform Support

| Platform | Status |
|---|---|
| **macOS** | ✅ Fully supported |
| **Linux (x86-64)** | ✅ Fully supported |
| **Raspberry Pi (arm64 / armv7)** | ✅ Supported — Kamailio image is multi-arch |
| **Windows** | ❌ Not supported (may work under WSL) |

---

## Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/JayWolfPower/claude-phone.git
cd claude-phone
cp .env.example .env
```

Open `.env` and set at minimum:

```bash
EXTERNAL_IP=192.168.1.100   # your server's LAN IP
SIP_DOMAIN=pbx.local        # domain softphones register under
OPENAI_API_KEY=sk-...
ELEVENLABS_API_KEY=...
```

### 2. Start the Docker stack

```bash
docker compose up -d
```

First run builds the Kamailio image (~2 min). Subsequent starts are instant.

Verify everything is up:

```bash
docker compose ps
docker compose logs kamailio | grep "Starting Kamailio"
docker compose logs drachtio  | grep "listening"
```

### 3. Add a softphone user

```bash
./kamailio/init-db.sh alice secretpass
```

This calls `kamctl add` inside the Kamailio container and prints softphone config instructions.

### 4. Start the Claude bridge (natively)

```bash
cd claude-api-server && node server.js
```

This wraps the `claude` CLI in an HTTP server on port 3333. It must run natively (not in Docker) so it can reach the `claude` binary and `~/.claude` credentials. No `ANTHROPIC_API_KEY` needed — it uses your Claude Pro / Max subscription.

### 5. Configure your softphone

| Field | Value |
|---|---|
| SIP server / registrar | `EXTERNAL_IP` (from your `.env`) |
| Port | `5060` |
| Username | `alice` (or whatever you passed to `init-db.sh`) |
| Password | `secretpass` |
| Domain / realm | `pbx.local` (your `SIP_DOMAIN`) |

Dial `9000` → Claude answers.

---

## Device Personalities

Each SIP extension can have its own AI name, voice, and system prompt. Edit `voice-app/config/devices.json` (copy from `devices.json.example`):

```json
{
  "9000": {
    "name": "Morpheus",
    "extension": "9000",
    "voiceId": "JAgnJveGGUh4qy4kh6dF",
    "prompt": "You are Morpheus. Keep voice responses under 40 words."
  },
  "9002": {
    "name": "Cephanie",
    "extension": "9002",
    "voiceId": "your-elevenlabs-voice-id",
    "prompt": "You are Cephanie, a storage monitoring bot."
  }
}
```

Kamailio routes any four-digit extension starting with `9` (regex `^9[0-9]{3}$`) to drachtio. To change the pattern, edit `AI_EXT_REGEX` in `kamailio/kamailio.cfg` (the define is regenerated by the entrypoint from `kamailio-local.cfg`).

---

## Kamailio SIP users

Add users with the helper script:

```bash
./kamailio/init-db.sh <username> <password>
```

Or directly via `kamctl`:

```bash
docker compose exec kamailio kamctl add alice secretpass
docker compose exec kamailio kamctl ul show   # verify registrations
```

---

## API Endpoints

The voice-app exposes these endpoints on port 3000:

| Method | Endpoint | Purpose |
|---|---|---|
| POST | `/api/outbound-call` | Initiate an outbound call to a registered extension |
| GET | `/api/call/:callId` | Get call status |
| GET | `/api/calls` | List active calls |
| POST | `/api/query` | Query Claude programmatically (no phone call) |
| GET | `/api/devices` | List configured device extensions |

See [Outbound API Reference](voice-app/README-OUTBOUND.md) for request/response details.

---

## Troubleshooting

| Problem | Likely Cause | Fix |
|---|---|---|
| Calls connect but no audio | Wrong `EXTERNAL_IP` | Check `.env`, ensure it's your LAN IP, restart stack |
| Softphone shows "Registration failed" | Wrong SIP_DOMAIN or credentials | Re-run `init-db.sh`; verify domain matches `.env` |
| `docker compose logs kamailio` shows DB errors | subscriber.db not initialized | Restart container — entrypoint auto-inits the DB |
| "Sorry, something went wrong" during call | claude-api-server not running | `cd claude-api-server && node server.js` |
| `claude: command not found` in api-server | Claude Code CLI not installed | `npm i -g @anthropic-ai/claude-code` then `claude login` |
| Port 5060 already in use | Another SIP service on the host | Stop it or change `KAMAILIO_PORT` in docker-compose.yml |

View live logs:

```bash
docker compose logs -f kamailio    # SIP registration / routing
docker compose logs -f drachtio    # SIP app server
docker compose logs -f voice-app   # conversation loop
docker compose logs -f freeswitch  # RTP media
```

---

## Configuration reference

| Variable | Default | Description |
|---|---|---|
| `EXTERNAL_IP` | — | Host LAN IP — goes into SDP so phones find the RTP stream |
| `SIP_DOMAIN` | `pbx.local` | Kamailio realm; softphones use this as their domain |
| `KAM_REALM` | `= SIP_DOMAIN` | Digest auth realm (usually same as SIP_DOMAIN) |
| `SIP_REGISTRAR` | `127.0.0.1:5060` | Where voice-app sends outbound INVITEs |
| `DRACHTIO_SECRET` | `cymru` | Shared secret between voice-app and drachtio |
| `FREESWITCH_SECRET` | `JambonzR0ck$` | ESL password |
| `ELEVENLABS_API_KEY` | — | TTS |
| `OPENAI_API_KEY` | — | Whisper STT |
| `CLAUDE_API_URL` | `http://127.0.0.1:3333` | URL of the claude-api-server |

---

## Development

```bash
npm test        # run tests
npm run lint    # lint
npm run lint:fix
```

---

## Documentation

- [Outbound API](voice-app/README-OUTBOUND.md) — outbound calling reference
- [Deployment](voice-app/DEPLOYMENT.md) — production deployment notes
- [Claude Code Skill](docs/CLAUDE-CODE-SKILL.md) — build a "call me" skill for Claude Code

---

## License

MIT
