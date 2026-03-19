import os, uuid, httpx
from datetime import datetime, timedelta
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(title="Workshop Key Manager")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

MASTER_KEY  = os.environ.get("LITELLM_MASTER_KEY", "sk-workshop-changeme")
MAX_BUDGET  = float(os.environ.get("MAX_BUDGET_USD", "2.00"))
DURATION_H  = int(os.environ.get("SESSION_DURATION_HOURS", "8"))

# In-memory key store: key -> metadata
_keys: dict[str, dict] = {}

class Req(BaseModel):
    name: str
    email: str | None = None

@app.post("/issue")
async def issue(req: Req):
    key = f"sk-workshop-{uuid.uuid4().hex[:16]}"
    _keys[key] = {
        "attendee": req.name,
        "email": req.email or "",
        "issued_at": datetime.utcnow().isoformat(),
        "expires_at": (datetime.utcnow() + timedelta(hours=DURATION_H)).isoformat(),
        "spend_cap_usd": MAX_BUDGET,
        "spend": 0.0,
    }
    return {
        "key": key,
        "expires_in": f"{DURATION_H} hours",
        "spend_cap_usd": MAX_BUDGET,
        "proxy_url": "http://localhost:4000/v1",
        "local_model_url": "http://localhost:12434/v1",
    }

@app.post("/revoke")
async def revoke():
    count = len(_keys)
    _keys.clear()
    return {"revoked": count}

@app.get("/status")
async def status():
    return {"active_keys": len(_keys), "keys": list(_keys.values())}
