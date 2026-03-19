#!/bin/bash
# Run this inside your cloned labspace-keymanager folder
# git clone https://github.com/ajeetraina/labspace-keymanager && cd labspace-keymanager

mkdir -p project/portal project/key-manager

# ── compose.override.yaml ──────────────────────────────────────────
cat > compose.override.yaml << 'EOF'
services:
  configurator:
    environment:
      PROJECT_CLONE_URL: https://github.com/ajeetraina/labspace-keymanager

  portal:
    image: nginx:alpine
    ports:
      - "8080:80"
    volumes:
      - ./project/portal:/usr/share/nginx/html:ro
    restart: unless-stopped

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    ports:
      - "4000:4000"
    volumes:
      - ./project/litellm-config.yaml:/app/config.yaml:ro
    environment:
      OPENAI_API_KEY: ${OPENAI_API_KEY:-}
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:-}
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY:-sk-workshop-changeme}
      LITELLM_SALT_KEY: ${LITELLM_SALT_KEY:-changeme}
    command: --config /app/config.yaml --port 4000
    restart: unless-stopped

  model-runner:
    image: docker/model-runner:latest
    ports:
      - "12434:12434"
    volumes:
      - model-cache:/root/.docker/models
    restart: unless-stopped

volumes:
  model-cache:
EOF

# ── project/litellm-config.yaml ────────────────────────────────────
cat > project/litellm-config.yaml << 'EOF'
model_list:
  - model_name: gpt-4o-mini
    litellm_params:
      model: openai/gpt-4o-mini
      api_key: os.environ/OPENAI_API_KEY

  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY

  - model_name: llama3.2
    litellm_params:
      model: openai/llama3.2
      api_base: http://model-runner:12434/v1
      api_key: none

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  salt_key: os.environ/LITELLM_SALT_KEY
  default_team_settings:
    max_budget: 2.00
    budget_duration: 24h
    tpm_limit: 20000
    rpm_limit: 60

litellm_settings:
  drop_params: true
EOF

# ── project/key-manager/Dockerfile ─────────────────────────────────
cat > project/key-manager/Dockerfile << 'EOF'
FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir fastapi uvicorn httpx
COPY main.py .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

# ── project/key-manager/main.py ────────────────────────────────────
cat > project/key-manager/main.py << 'PYEOF'
import os, httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="Workshop Key Manager")
LITELLM_BASE = os.environ["LITELLM_BASE_URL"]
MASTER_KEY   = os.environ["LITELLM_MASTER_KEY"]
MAX_BUDGET   = float(os.environ.get("MAX_BUDGET_USD", "2.00"))
DURATION_H   = int(os.environ.get("SESSION_DURATION_HOURS", "8"))
HEADERS      = {"Authorization": f"Bearer {MASTER_KEY}"}
_keys: list[str] = []

class Req(BaseModel):
    name: str
    email: str | None = None

@app.post("/issue")
async def issue(req: Req):
    payload = {"key_alias": f"workshop-{req.name.lower().replace(' ','-')}",
               "max_budget": MAX_BUDGET, "budget_duration": f"{DURATION_H}h",
               "tpm_limit": 20000, "rpm_limit": 60,
               "models": ["gpt-4o-mini","gpt-4o","llama3.2"],
               "metadata": {"attendee": req.name}}
    async with httpx.AsyncClient() as c:
        r = await c.post(f"{LITELLM_BASE}/key/generate", json=payload, headers=HEADERS)
    if r.status_code != 200: raise HTTPException(500, r.text)
    data = r.json(); _keys.append(data["key"])
    return {"key": data["key"], "expires_in": f"{DURATION_H} hours",
            "spend_cap_usd": MAX_BUDGET,
            "proxy_url": "http://localhost:4000/v1",
            "local_model_url": "http://localhost:12434/v1"}

@app.post("/revoke")
async def revoke():
    async with httpx.AsyncClient() as c:
        for k in _keys: await c.post(f"{LITELLM_BASE}/key/delete", json={"keys":[k]}, headers=HEADERS)
    _keys.clear(); return {"revoked": True}

@app.get("/status")
async def status():
    async with httpx.AsyncClient() as c:
        r = await c.get(f"{LITELLM_BASE}/key/list", headers=HEADERS)
    return r.json()
PYEOF

# ── project/portal/index.html ───────────────────────────────────────
# (copy from the earlier generated file or run setup-workshop.sh)
cp ~/workshop-ai/project/portal/index.html project/portal/index.html 2>/dev/null \
  || echo "⚠ Copy portal/index.html manually from the earlier download"

# ── .env.example ────────────────────────────────────────────────────
cat > .env.example << 'EOF'
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
LITELLM_MASTER_KEY=sk-workshop-changeme
LITELLM_SALT_KEY=changeme
EOF

git add .
git commit -m "Add workshop key manager: portal, LiteLLM proxy, Model Runner, key-manager service"
git push

echo ""
echo "✅ All files committed and pushed to https://github.com/ajeetraina/labspace-keymanager"
