# app/routes/profiles.py

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from postgrest.exceptions import APIError

from app.auth import get_current_user
from app.http_errors import raise_http_for_api_error
from app.supabase_client import supabase_admin
from app.supabase_user_client import get_supabase_for_user

router = APIRouter(prefix="/profiles", tags=["profiles"])


# -------------------------------------------------
# Helpers
# -------------------------------------------------

def _get_supabase(current_user: dict):
    # DEV_AUTH or dev user: use admin client
    if current_user.get("dev") or not current_user.get("access_token"):
        return supabase_admin
    return get_supabase_for_user(current_user["access_token"])


# -------------------------------------------------
# Profile
# -------------------------------------------------

@router.get("/{user_id}")
def get_profile(user_id: UUID, current_user=Depends(get_current_user)):
    supabase = _get_supabase(current_user)

    # -------- Public profile --------
    try:
        res = supabase.rpc(
            "get_public_profile",
            {"p_user_id": str(user_id)},
        ).execute()
    except APIError as e:
        raise_http_for_api_error(e)

    data = res.data
    if not data:
        raise HTTPException(
            status_code=404,
            detail={"error": "PROFILE_NOT_FOUND", "message": "Profile not found"},
        )

    profile = data[0]

    # -------- Profile stats (hosted / played) --------
    try:
        stats_res = supabase.rpc(
            "get_profile_stats",
            {"p_user_id": str(user_id)},
        ).execute()
    except APIError as e:
        raise_http_for_api_error(e)

    stats_row = None
    if getattr(stats_res, "data", None):
        stats_row = (
            stats_res.data[0]
            if isinstance(stats_res.data, list)
            else stats_res.data
        )

    profile["hosted_count"] = int((stats_row or {}).get("hosted_count") or 0)
    profile["played_count"] = int((stats_row or {}).get("played_count") or 0)

    return profile


# -------------------------------------------------
# Public decks (profile)
# -------------------------------------------------

@router.get("/{user_id}/decks")
def get_profile_decks(user_id: UUID, current_user=Depends(get_current_user)):
    """
    Public decks for a profile page.
    NOTE: Public read only. Editing lives in /me/decks.
    """
    supabase = _get_supabase(current_user)

    try:
        res = (
            supabase.table("decks")
            .select(
                "id,"
                "commander_name,"
                "deck_url,"
                "export_text,"
                "format_slug,"
                "color_white,"
                "color_blue,"
                "color_black,"
                "color_red,"
                "color_green,"
                "color_colorless,"
                "created_at,"
                "image_url,"
                "updated_at"
            )
            .eq("user_id", str(user_id))
            .order("updated_at", desc=True)
            .execute()
        )
    except APIError as e:
        raise_http_for_api_error(e)
    except Exception:
        raise HTTPException(
            status_code=503,
            detail={"code": "UPSTREAM_UNAVAILABLE"},
        )

    return {"decks": res.data or []}
