from __future__ import annotations

from typing import Any, Dict, List, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from postgrest.exceptions import APIError

from app.auth import get_current_user
from app.http_errors import raise_http_for_api_error
from app.supabase_user_client import get_supabase_for_user

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("")
def list_notifications(
    unread_only: bool = Query(False),
    limit: int = Query(50, ge=1, le=200),
    user=Depends(get_current_user),
):
    token = user.get("access_token")
    if not token:
        raise HTTPException(status_code=401, detail={"code": 
"AUTH_REQUIRED"})
    supa = get_supabase_for_user(token)

    try:
        q = (
            supa.table("notifications")
            
.select("id,user_id,event_id,type,title,body,meta,is_read,created_at")
            .eq("user_id", str(user["id"]))
            .order("created_at", desc=True)
            .limit(limit)
        )
        if unread_only:
            q = q.eq("is_read", False)

        rows = q.execute().data or []

        # unread count (cheap separate query)
        c = (
            supa.table("notifications")
            .select("id", count="exact")
            .eq("user_id", str(user["id"]))
            .eq("is_read", False)
            .execute()
        )
        unread_count = int(getattr(c, "count", 0) or 0)

        return {"unread_count": unread_count, "items": rows}

    except APIError as e:
        raise_http_for_api_error(e)


@router.post("/{notification_id}/read")
def mark_read(notification_id: UUID, user=Depends(get_current_user)):
    token = user.get("access_token")
    if not token:
        raise HTTPException(status_code=401, detail={"code": 
"AUTH_REQUIRED"})
    supa = get_supabase_for_user(token)

    try:
        r = (
            supa.table("notifications")
            .update({"is_read": True})
            .eq("id", str(notification_id))
            .eq("user_id", str(user["id"]))
            .execute()
        )
        return {"ok": True, "updated": len(r.data or [])}

    except APIError as e:
        raise_http_for_api_error(e)


@router.post("/read_for_event/{event_id}")
def mark_read_for_event(event_id: UUID, user=Depends(get_current_user)):
    token = user.get("access_token")
    if not token:
        raise HTTPException(status_code=401, detail={"code": 
"AUTH_REQUIRED"})
    supa = get_supabase_for_user(token)

    try:
        r = (
            supa.table("notifications")
            .update({"is_read": True})
            .eq("user_id", str(user["id"]))
            .eq("event_id", str(event_id))
            .eq("is_read", False)
            .execute()
        )
        return {"ok": True, "updated": len(r.data or [])}

    except APIError as e:
        raise_http_for_api_error(e)


@router.post("/clear")
def clear_notifications(user=Depends(get_current_user)):
    token = user.get("access_token")
    if not token:
        raise HTTPException(status_code=401, detail={"code": 
"AUTH_REQUIRED"})
    supa = get_supabase_for_user(token)

    try:
        # "Clear" = mark all read (safer than delete)
        r = (
            supa.table("notifications")
            .update({"is_read": True})
            .eq("user_id", str(user["id"]))
            .eq("is_read", False)
            .execute()
        )
        return {"ok": True, "updated": len(r.data or [])}

    except APIError as e:
        raise_http_for_api_error(e)

