from typing import Optional, Any, Dict

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field, HttpUrl
from postgrest.exceptions import APIError

from app.auth import get_current_user
from app.supabase_user_client import get_supabase_for_user
from app.http_errors import raise_http_for_api_error


router = APIRouter(prefix="/me/decks", tags=["decks"])


# -------------------------------------------------
# Models
# -------------------------------------------------

class DeckCreate(BaseModel):
    commander_name: str = Field(min_length=1, max_length=80)
    deck_url: Optional[HttpUrl] = None
    format_slug: Optional[str] = None
    export_text: Optional[str] = None
    image_url: Optional[HttpUrl] = None
    color_white: bool = False
    color_blue: bool = False
    color_black: bool = False
    color_red: bool = False
    color_green: bool = False
    color_colorless: bool = False


class DeckUpdate(BaseModel):
    commander_name: Optional[str] = Field(default=None, min_length=1, max_length=80)
    deck_url: Optional[HttpUrl] = None
    format_slug: Optional[str] = None
    export_text: Optional[str] = None
    image_url: Optional[HttpUrl] = None
    color_white: Optional[bool] = None
    color_blue: Optional[bool] = None
    color_black: Optional[bool] = None
    color_red: Optional[bool] = None
    color_green: Optional[bool] = None
    color_colorless: Optional[bool] = None


# -------------------------------------------------
# Helpers
# -------------------------------------------------

def _require_auth(current_user: Dict[str, Any]) -> str:
    token = current_user.get("access_token")
    if not token:
        raise HTTPException(status_code=401, detail={"code": "AUTH_REQUIRED"})
    return token


def _normalize_export_text(v: Optional[str]) -> Optional[str]:
    if v is None:
        return None
    s = str(v).strip()
    return s if s else None


def _normalize_format_slug(v: Optional[str]) -> Optional[str]:
    if v is None:
        return None
    s = str(v).strip().lower()
    return s if s else None


# -------------------------------------------------
# Routes
# -------------------------------------------------

@router.post("")
def add_deck(
    payload: DeckCreate,
    current_user: Dict[str, Any] = Depends(get_current_user),
):
    token = _require_auth(current_user)
    supabase = get_supabase_for_user(token)

    data = payload.model_dump()
    data["user_id"] = current_user["id"]

    if data.get("deck_url") is not None:
        data["deck_url"] = str(data["deck_url"])

    if data.get("image_url"):
        data["image_url"] = str(data["image_url"])
    else:
        data["image_url"] = _compute_image_url(
            data.get("format_slug"),
            data.get("commander_name"),
        )

    data["export_text"] = _normalize_export_text(data.get("export_text"))
    data["format_slug"] = _normalize_format_slug(data.get("format_slug"))

    try:
        res = supabase.table("decks").insert(data).execute()
    except APIError as e:
        raise_http_for_api_error(e)

    if not res.data:
        raise HTTPException(status_code=500, detail={"code": "DECK_CREATE_FAILED"})

    return res.data[0]


@router.get("")
def list_my_decks(
    current_user: Dict[str, Any] = Depends(get_current_user),
    format_slug: Optional[str] = Query(default=None),
):
    token = _require_auth(current_user)
    supabase = get_supabase_for_user(token)

    fmt = _normalize_format_slug(format_slug)

    try:
        q = (
            supabase.table("decks")
            .select(
                "id,commander_name,deck_url,"
                "format_slug,export_text,image_url,"
                "color_white,color_blue,color_black,color_red,color_green,color_colorless,"
                "created_at"
            )
            .eq("user_id", current_user["id"])
        )

        if fmt:
            q = q.eq("format_slug", fmt)

        res = q.order("created_at", desc=True).execute()

    except APIError as e:
        raise_http_for_api_error(e)

    return {"decks": getattr(res, "data", None) or []}


@router.patch("/{deck_id}")
def update_deck(
    deck_id: str,
    payload: DeckUpdate,
    current_user: Dict[str, Any] = Depends(get_current_user),
):
    token = _require_auth(current_user)
    supabase = get_supabase_for_user(token)

    patch = payload.model_dump(exclude_unset=True)

    if not patch:
        raise HTTPException(status_code=400, detail={"code": "NOTHING_TO_UPDATE"})

    if "deck_url" in patch and patch["deck_url"] is not None:
        patch["deck_url"] = str(patch["deck_url"])

    if "image_url" in patch and patch["image_url"] is not None:
        patch["image_url"] = str(patch["image_url"])

    if "export_text" in patch:
        patch["export_text"] = _normalize_export_text(patch.get("export_text"))

    if "format_slug" in patch:
        patch["format_slug"] = _normalize_format_slug(patch.get("format_slug"))

    try:
        upd = (
            supabase.table("decks")
            .update(patch)
            .eq("id", deck_id)
            .eq("user_id", current_user["id"])
            .execute()
        )
    except APIError as e:
        raise_http_for_api_error(e)

    if not getattr(upd, "data", None):
        raise HTTPException(status_code=404, detail={"code": "DECK_NOT_FOUND"})

    res = (
        supabase.table("decks")
        .select("*")
        .eq("id", deck_id)
        .eq("user_id", current_user["id"])
        .single()
        .execute()
    )

    return res.data


@router.delete("/{deck_id}")
def delete_deck(
    deck_id: str,
    current_user: Dict[str, Any] = Depends(get_current_user),
):
    token = _require_auth(current_user)
    supabase = get_supabase_for_user(token)

    try:
        res = (
            supabase.table("decks")
            .delete()
            .eq("id", deck_id)
            .eq("user_id", current_user["id"])
            .execute()
        )
    except APIError as e:
        raise_http_for_api_error(e)

    if not getattr(res, "data", None):
        raise HTTPException(status_code=404, detail={"code": "DECK_NOT_FOUND"})

    return {"ok": True}
