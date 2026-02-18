from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from postgrest.exceptions import APIError

from app.auth import get_current_user
from app.supabase_user_client import get_supabase_for_user
from app.supabase_client import supabase_admin
from app.http_errors import raise_http_for_api_error

import logging

router = APIRouter(tags=["me"])

logger = logging.getLogger(__name__)

# --------------------------------------------------
# Utils
# --------------------------------------------------

def _get_supabase(current_user: dict):
    if current_user.get("dev") or "access_token" not in current_user:
        return supabase_admin
    return get_supabase_for_user(current_user["access_token"])


# --------------------------------------------------
# /me
# --------------------------------------------------

@router.get("/me")
def me(current_user: dict = Depends(get_current_user)):
    return {
        "user": {
            "id": current_user["id"],
            "email": current_user.get("email"),
        }
    }


# --------------------------------------------------
# /me/profile
# --------------------------------------------------

class UpdateMyProfileIn(BaseModel):
    nickname: str
    avatar_url: Optional[str] = None
    bio: Optional[str] = None
    mtg_arena_username: Optional[str] = None


@router.patch("/me/profile")
def update_my_profile(
    payload: UpdateMyProfileIn,
    current_user: dict = Depends(get_current_user),
):
    supabase = _get_supabase(current_user)

    nickname = payload.nickname.strip()
    if len(nickname) < 2:
        raise HTTPException(
            status_code=400,
            detail={"code": "NICKNAME_TOO_SHORT"},
        )

    bio = payload.bio.strip() if payload.bio else None
    if bio is not None and len(bio) > 200:
        raise HTTPException(
            status_code=400,
            detail={"code": "BIO_TOO_LONG"},
        )

    body = {
        "id": current_user["id"],
        "nickname": nickname,
        "avatar_url": payload.avatar_url,
        "mtg_arena_username": payload.mtg_arena_username,
        "bio": bio,
    }

    try:
        supabase.table("profiles").upsert(
            body,
            on_conflict="id",
        ).execute()
    except APIError as e:
        raise_http_for_api_error(e)

    try:
        res = (
            supabase.table("profiles")
            .select("id,nickname,avatar_url,bio,mtg_arena_username")
            .eq("id", current_user["id"])
            .single()
            .execute()
        )
    except APIError as e:
        raise_http_for_api_error(e)

    data = getattr(res, "data", None)
    if not data:
        raise HTTPException(
            status_code=404,
            detail={"code": "PROFILE_NOT_FOUND"},
        )

    return data


# --------------------------------------------------
# /me (delete account)
# --------------------------------------------------

@router.delete("/me")
async def delete_account(current_user: dict = Depends(get_current_user)):
    user_id = current_user["id"]

    try:
        # 1. Atomic delete inside Postgres
        supabase_admin.rpc(
            "delete_user_atomic",
            {"p_user_id": user_id}
        ).execute()

        # 2. Delete auth user (outside DB transaction)
        supabase_admin.auth.admin.delete_user(user_id)

        return {"success": True}

    except APIError as e:
        logger.exception("Supabase API error during account deletion")
        raise_http_for_api_error(e)

    except Exception:
        logger.exception("Unexpected error during account deletion")
        raise HTTPException(
            status_code=500,
            detail={"code": "ACCOUNT_DELETE_FAILED"},
        )
