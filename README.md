# Workshop AI Key Manager — Labspace

A [Docker Labspace](https://github.com/dockersamples/labspace-starter) that solves the API key sharing problem for workshops and labs with 50–100+ attendees.

Instead of sharing a single OpenAI or Anthropic key with the entire group, each attendee gets a **personal, time-boxed key** with a spend cap — issued in seconds from a self-hosted portal. The organiser keeps real keys private; attendees only ever see their workshop token.

## Architecture

```
┌─────────────────────────────────┐     ┌──────────────────────────────────┐
│     Organiser machine (private) │     │    Attendee machine (public)     │
│                                 │     │                                  │
│  ┌─────────────────────────┐    │     │  ┌──────────────────────────┐   │
│  │   LiteLLM proxy :4000   │◄───┼─────┼──│    Attendee code         │   │
│  │   rate limits, budgets  │    │     │  │    OpenAI SDK → :4000    │   │
│  └────────────┬────────────┘    │     │  └──────────────────────────┘   │
│               │                 │     │                                  │
│  ┌────────────▼────────────┐    │     │  ┌──────────────────────────┐   │
│  │   Key manager   :8000   │◄───┼─────┼──│    Attendee portal :8080 │   │
│  │   issue / revoke keys   │    │     │  │    enter name → get key  │   │
│  └─────────────────────────┘    │     │  └──────────────────────────┘   │
│                                 │     │                                  │
│  ┌─────────────────────────┐    │     │  ┌──────────────────────────┐   │
│  │  Model Runner   :12434  │◄───┼─────┼──│    Attendee code         │   │
│  │  local inference, free  │    │     │  │    no key needed         │   │
│  └─────────────────────────┘    │     │  └──────────────────────────┘   │
│                                 │     └──────────────────────────────────┘
│  ┌─────────────────────────┐    │
│  │  Admin dashboard :9000  │    │     ┌──────────────────────────────────┐
│  │  spend · keys · revoke  │    │     │          External APIs           │
│  └─────────────────────────┘    │     │   OpenAI  ·  Anthropic (Claude)  │
│                                 │     └──────────────────────────────────┘
│  .env  ← real keys, never push  │
└─────────────────────────────────┘
```

**Key principle:** Real API keys never leave the organiser's machine. Attendees only receive a short-lived workshop token with a $2 spend cap.

## What's in this repo

```
labspace-keymanager/
├── compose.yaml                   # Labspace include pattern
├── compose.override.yaml          # Portal + LiteLLM + Model Runner services
├── .env.example                   # Key template — copy to .env, never commit
├── setup.sh                       # One-shot project setup script
├── labspace/                      # Lab content (markdown steps)
└── project/
    ├── litellm-config.yaml        # Model routing + rate limits
    ├── portal/
    │   └── index.html             # Attendee key pickup page
    └── key-manager/
        ├── main.py                # FastAPI — issue / revoke / status
        └── Dockerfile
```

## Quick start

### 1 — Prerequisites

- Docker Desktop with Model Runner enabled
- An OpenAI API key (Anthropic optional)

### 2 — Setup

```bash
git clone https://github.com/ajeetraina/labspace-keymanager
cd labspace-keymanager
bash setup.sh
```

The script creates all files and prompts for your OpenAI key. It auto-generates secure `LITELLM_MASTER_KEY` and `LITELLM_SALT_KEY` values.

### 3 — Pull a local model (optional, free)

```bash
docker model pull llama3.2
```

Attendees can use this at `http://localhost:12434/v1` with no key at all.

### 4 — Start the stack

```bash
docker compose up -d
```

### 5 — Run the Labspace

```bash
CONTENT_PATH=$PWD docker compose up --watch
```

Open `http://localhost:3030` to see the Labspace UI.

## How it works for attendees

1. Open `http://localhost:8080`
2. Enter your name → receive a personal API key
3. Use the key in your code:

```python
from openai import OpenAI

# Cloud model via proxy
client = OpenAI(
    base_url="http://localhost:4000/v1",
    api_key="sk-workshop-<your-key>",
)

# Local model — no key needed
local = OpenAI(
    base_url="http://localhost:12434/v1",
    api_key="none",
)
```

Every workshop key has:

| Property | Value |
|---|---|
| Spend cap | $2.00 |
| Expiry | 8 hours |
| Rate limit | 60 req/min · 20k tokens/min |
| Models | gpt-4o-mini, gpt-4o, llama3.2 |

## How it works for organisers

**Before the session:**
```bash
cp .env.example .env
# Fill in OPENAI_API_KEY and optionally ANTHROPIC_API_KEY
docker compose up -d
docker model pull llama3.2
```

**During the session** — point attendees to `http://<your-ip>:8080`.

**At session end:**
```bash
# Revoke all keys instantly
curl -X POST http://localhost:8000/revoke

# Tear down
docker compose down
```

**Monitor spend in real time:**
```bash
curl http://localhost:8000/status \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"
```

## Ports reference

| Port | Service | Who accesses it |
|---|---|---|
| `3030` | Labspace UI | Attendees |
| `8080` | Attendee portal | Attendees |
| `4000` | LiteLLM proxy | Attendees (via workshop key) |
| `12434` | Docker Model Runner | Attendees (no key) |
| `8000` | Key manager API | Organiser only |

## Configuration

**Change spend cap per attendee** — edit `project/litellm-config.yaml`:
```yaml
default_team_settings:
  max_budget: 2.00       # USD per key
  budget_duration: 24h
```

**Add more models** — add a block under `model_list` in `litellm-config.yaml`, then:
```bash
docker compose restart litellm
```

**Add Anthropic support** — set `ANTHROPIC_API_KEY` in `.env` and uncomment the Claude entries in `litellm-config.yaml`.

**GPU acceleration for Model Runner** — uncomment the `deploy.resources` block in `compose.override.yaml` (requires NVIDIA Container Toolkit).

## Related projects

- [dockersamples/labspace-starter](https://github.com/dockersamples/labspace-starter) — template this repo was built from
- [dockersamples/labspace-agentic-apps-with-docker](https://github.com/dockersamples/labspace-agentic-apps-with-docker) — agentic apps Labspace
- [dockersamples/awesome-labspaces](https://github.com/dockersamples/awesome-labspaces) — all available Labspaces

## License

Apache 2.0 — see [LICENSE](LICENSE)
