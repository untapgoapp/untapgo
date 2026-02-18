import json

from fastapi import HTTPException
from postgrest.exceptions import APIError


def raise_http_for_api_error(e: APIError) -> None:
    """
    Convert Supabase/PostgREST APIError into sensible HTTP errors.
    Use everywhere so we don't drift.
    """
    try:
        j = e.json()
    except Exception:
        raise HTTPException(status_code=503, detail={"code": "UPSTREAM_ERROR"})

    msg = (j.get("message") or "").lower()

    # Auth-ish
    if (
        ("jwt" in msg)
        or ("token" in msg)
        or ("auth" in msg)
        or ("permission" in msg)
    ):
        raise HTTPException(status_code=401, detail={"code": "AUTH_INVALID"})

    # Upstream/network-ish (best effort)
    if ("timeout" in msg) or ("connection" in msg) or ("fetch" in msg):
        raise HTTPException(
            status_code=503,
            detail={"code": "UPSTREAM_UNAVAILABLE"},
        )

    # Cooldown: surface structured info (details contains JSON string)
    if j.get("message") in ("JOIN_COOLDOWN_ACTIVE", "KICK_COOLDOWN_ACTIVE"):
        details = j.get("details")
        if isinstance(details, str) and details.strip():
            try:
                d = json.loads(details)
                if isinstance(d, dict):
                    d.setdefault("code", j.get("message"))
                    raise HTTPException(status_code=400, detail=d)
            except Exception:
                pass

    # Default: client error with full PostgREST payload
    raise HTTPException(status_code=400, detail=j)
