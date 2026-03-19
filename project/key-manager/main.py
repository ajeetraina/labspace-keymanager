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
