import os
from typing import Optional, Dict, Any

import httpx
from cachetools import TTLCache
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import jwt

# -----------------------------
# Config
# -----------------------------
SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
if not SUPABASE_URL:
    raise RuntimeError("Missing SUPABASE_URL in environment")

JWT_ISSUER = os.getenv("SUPABASE_JWT_ISSUER", f"{SUPABASE_URL}/auth/v1").rstrip("/")
JWT_AUD = os.getenv("SUPABASE_JWT_AUD", "authenticated")

# Optional fallback for legacy HS256 setups
JWT_SECRET = os.getenv("SUPABASE_JWT_SECRET")  # legacy only

# JWKS (preferred)
JWKS_URL = os.getenv("SUPABASE_JWKS_URL", f"{JWT_ISSUER}/.well-known/jwks.json")

# Cache JWKS for 1 hour
_jwks_cache = TTLCache(maxsize=1, ttl=60 * 60)

bearer_scheme = HTTPBearer(auto_error=False)


async def _get_jwks() -> Dict[str, Any]:
    cached = _jwks_cache.get("jwks")
    if cached:
        return cached

    async with httpx.AsyncClient(timeout=10) as client:
        r = await client.get(JWKS_URL)
        r.raise_for_status()
        jwks = r.json()

    keys = jwks.get("keys") or []
    if not keys:
        raise RuntimeError("JWKS endpoint returned no keys")

    _jwks_cache["jwks"] = jwks
    return jwks


async def _verify_and_decode(token: str) -> Dict[str, Any]:
    try:
        header = jwt.get_unverified_header(token)
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")

    alg = header.get("alg")
    kid = header.get("kid")

    # Preferred: JWKS (Supabase, usually ES256)
    try:
        jwks = await _get_jwks()

        if not kid:
            raise HTTPException(status_code=401, detail="Token missing kid")

        key = next((k for k in jwks.get("keys", []) if k.get("kid") == kid), None)
        if not key:
            raise HTTPException(status_code=401, detail="Unknown signing key")

        claims = jwt.decode(
            token,
            key,
            algorithms=[alg] if alg else ["ES256", "RS256"],
            audience=JWT_AUD,
            issuer=JWT_ISSUER,
            options={"verify_aud": True, "verify_iss": True},
        )
        return claims

    except HTTPException:
        raise
    except Exception:
        # Legacy HS256 fallback (only if configured)
        if JWT_SECRET and (alg == "HS256" or alg is None):
            try:
                return jwt.decode(
                    token,
                    JWT_SECRET,
                    algorithms=["HS256"],
                    audience=JWT_AUD,
                    issuer=JWT_ISSUER,
                    options={"verify_aud": True, "verify_iss": True},
                )
            except Exception:
                raise HTTPException(status_code=401, detail="Invalid token")

        raise HTTPException(status_code=401, detail="Invalid token")


async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
) -> Dict[str, Any]:
    """
    Devuelve SIEMPRE un dict con:
    - id / sub
    - access_token (str | None)
    - dev (bool)
    """

    dev_auth = os.getenv("DEV_AUTH", "0") == "1"
    dev_user_id = os.getenv("DEV_USER_ID")

    # DEV_AUTH bypass (sin Bearer)
    if credentials is None or credentials.scheme.lower() != "bearer":
        if dev_auth and dev_user_id:
            return {
                "sub": dev_user_id,
                "id": dev_user_id,
                "access_token": None,
                "role": "authenticated",
                "aud": JWT_AUD,
                "iss": JWT_ISSUER,
                "dev": True,
            }
        raise HTTPException(status_code=401, detail="Missing Bearer token")

    # HTTPBearer YA elimina "Bearer "
    token = credentials.credentials

    claims = await _verify_and_decode(token)

    user_id = claims.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="Token missing sub")

    # Campos de compatibilidad usados en routes
    claims["id"] = user_id
    claims["access_token"] = token
    claims["dev"] = False

    return claims
