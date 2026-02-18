from supabase import create_client, Client
import logging
from typing import Optional

from app.config import (
    SUPABASE_URL,
    SUPABASE_SERVICE_ROLE_KEY,
    SUPABASE_ANON_KEY,
)

logger = logging.getLogger("untapgo")


def _require_env(name: str, value: Optional[str]) -> str:
    if value is None or str(value).strip() == "":
        # This will be caught by the global exception handler in main.py
        msg = f"Missing required config: {name}. Did you source .env?"
        logger.error(msg)
        raise RuntimeError(msg)
    return value


# Validate required config at import time (fail fast, fail loud)
SUPABASE_URL = _require_env("SUPABASE_URL", SUPABASE_URL)
SUPABASE_SERVICE_ROLE_KEY = _require_env(
    "SUPABASE_SERVICE_ROLE_KEY", SUPABASE_SERVICE_ROLE_KEY
)
SUPABASE_ANON_KEY = _require_env("SUPABASE_ANON_KEY", SUPABASE_ANON_KEY)

# -------------------------------------------------
# Service role client (admin / server-side only)
# -------------------------------------------------
supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
supabase_admin = supabase

# -------------------------------------------------
# User-scoped client (uses anon key + user access token)
# Needed for RLS / auth.uid()
# -------------------------------------------------
def get_supabase_for_user(access_token: str) -> Client:
    client = create_client(SUPABASE_URL, SUPABASE_ANON_KEY)
    client.postgrest.auth(access_token)
    return client
