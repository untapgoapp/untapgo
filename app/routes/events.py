from __future__ import annotations

import json
import math
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict
from postgrest.exceptions import APIError

from app.auth import get_current_user
from app.constants.limits import HOST_NOTES_MAX
from app.http_errors import raise_http_for_api_error
from app.supabase_client import supabase_admin
from app.supabase_user_client import get_supabase_for_user

router = APIRouter(prefix="/events", tags=["events"])


# ----------------------------
# Models
# ----------------------------

class EventOut(BaseModel):
    model_config = ConfigDict(extra="allow")

    id: UUID
    title: str

    # Returned by RPCs (get_event/get_events_feed) via join on formats
    format_slug: Optional[str] = None

    address_text: Optional[str] = None
    place_id: Optional[str] = None
    lat: Optional[float] = None
    lng: Optional[float] = None

    starts_at: Optional[str] = None
    duration_minutes: Optional[int] = None
    max_players: int
    status: str

    power_level: Optional[str] = None
    proxies_policy: Optional[str] = None
    host_notes: Optional[str] = None

    host_user_id: UUID
    host_nickname: Optional[str] = None

    attendees_count: int
    is_joined: bool

    pending_requests_count: int = 0

    my_status: Optional[str] = None
    cooldown_seconds: Optional[int] = None


class KickIn(BaseModel):
    user_id: UUID
    cooldown_minutes: int = 10


class RejectIn(BaseModel):
    user_id: UUID
    cooldown_minutes: int = 10


class AcceptIn(BaseModel):
    user_id: UUID


class NotesIn(BaseModel):
    host_notes: Optional[str] = None


class EditEventIn(BaseModel):
    title: Optional[str] = None
    starts_at: Optional[str] = None
    duration_minutes: Optional[int] = None
    max_players: Optional[int] = None

    # Flutter sends slug; DB stores format_id
    format_slug: Optional[str] = None

    power_level: Optional[str] = None
    proxies_policy: Optional[str] = None
    host_notes: Optional[str] = None

    address_text: Optional[str] = None
    place_id: Optional[str] = None
    lat: Optional[float] = None
    lng: Optional[float] = None


# ----------------------------
# Error parsing
# ----------------------------

def _parse_supabase_rpc_error(exc: Exception) -> Dict[str, Any]:
    detail = None
    raw = str(exc)

    if isinstance(exc, APIError):
        try:
            j = exc.json()
            detail = j.get("details") or j.get("detail")
            code = j.get("message")
        except Exception:
            code = None
    else:
        code = None

    out: Dict[str, Any] = {"code": code or "RPC_ERROR"}

    if code in ("KICK_COOLDOWN_ACTIVE", "JOIN_COOLDOWN_ACTIVE") and detail:
        try:
            parsed = json.loads(detail)
            if isinstance(parsed, dict):
                if parsed.get("cooldown_until"):
                    out["cooldown_until"] = str(parsed["cooldown_until"])
                if parsed.get("cooldown_seconds") is not None:
                    out["cooldown_seconds"] = int(parsed["cooldown_seconds"])
                if parsed.get("status"):
                    out["status"] = str(parsed["status"])
                return out
        except Exception:
            pass

        out["cooldown_until"] = detail
        return out

    out["raw"] = raw
    return out


def _normalize_notes(v: Optional[str]) -> Optional[str]:
    if v is None:
        return None
    s = v.strip()
    return s if s else None


# ----------------------------
# Status helpers
# ----------------------------

def _parse_dt_utc(v: Any) -> Optional[datetime]:
    if v is None:
        return None

    if isinstance(v, datetime):
        dt = v
    elif isinstance(v, str):
        s = v.strip()
        if not s:
            return None
        dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
    else:
        return None

    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _effective_status(row: Dict[str, Any]) -> str:
    return (row.get("status") or "Open").strip()



def _is_feed_visible_status(status: str) -> bool:
    return status in ("Open", "Full")


def _event_out_from_row(e: Dict[str, Any], using_user_feed: bool) -> Dict[str, Any]:
    my_status = e.get("my_status")
    cooldown_seconds = e.get("cooldown_seconds")

    raw_is_joined = bool(e.get("is_joined")) if using_user_feed else False
    if not my_status:
        my_status = "joined" if raw_is_joined else None

    is_joined = (str(my_status).strip().lower() == "joined") if my_status else False

    joined_count = e.get("joined_count")
    if joined_count is not None:
        attendees_count = int(joined_count or 0)
    else:
        attendees_count = int(e.get("attendees_count") or e.get("player_count") or 0)

    try:
        pending_requests_count = int(e.get("pending_requests_count") or 0)
    except Exception:
        pending_requests_count = 0

    try:
        cooldown_seconds_i = int(cooldown_seconds) if cooldown_seconds is not None else None
    except Exception:
        cooldown_seconds_i = None

    return {
        "id": e["id"],
        "title": e["title"],
        "format_slug": e.get("format_slug"),
        "address_text": e.get("address_text"),
        "place_id": e.get("place_id"),
        "lat": e.get("lat"),
        "lng": e.get("lng"),
        "starts_at": e.get("starts_at"),
        "duration_minutes": (
            int(e.get("duration_minutes"))
            if e.get("duration_minutes") is not None
            else None
        ),
        "max_players": int(e.get("max_players") or 0),
        "status": _effective_status(e),
        "power_level": e.get("power_level"),
        "proxies_policy": e.get("proxies_policy"),
        "host_notes": e.get("host_notes"),
        "host_user_id": e.get("host_user_id"),
        "host_nickname": e.get("host_nickname"),
        "attendees_count": attendees_count,
        "is_joined": is_joined,
        "pending_requests_count": int(e.get("pending_requests_count") or 0),
        "my_status": my_status,
        "cooldown_seconds": cooldown_seconds_i,
    }


def _require_token(user: Dict[str, Any]) -> str:
    token = user.get("access_token")
    if not token:
        raise HTTPException(status_code=401, detail={"code": "AUTH_REQUIRED"})
    return token


def _get_supa(user: Dict[str, Any]):
    token = user.get("access_token")
    if token:
        return get_supabase_for_user(token)
    if user.get("dev") is True:
        return supabase_admin
    raise HTTPException(status_code=401, detail={"code": "AUTH_REQUIRED"})


def _format_id_from_slug(supa, slug: str) -> int:
    s = (slug or "").strip().lower()
    if not s:
        raise HTTPException(status_code=422, detail={"code": "FORMAT_SLUG_REQUIRED"})

    r = supa.table("formats").select("id").eq("slug", s).limit(1).execute()
    if not r.data:
        raise HTTPException(status_code=422, detail={"code": "FORMAT_SLUG_INVALID", "slug": s})

    return int(r.data[0]["id"])


# ----------------------------
# Nearby helpers
# ----------------------------

def _haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    r = 6371.0
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)

    a = (math.sin(dphi / 2) ** 2) + math.cos(phi1) * math.cos(phi2) * (math.sin(dlambda / 2) ** 2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return r * c


# ----------------------------
# NOTIFICATIONS (ADD)
# ----------------------------

def _notif_create(
    user_id: UUID,
    event_id: Optional[UUID],
    type_: str,
    title: str,
    body: str,
    meta: Optional[Dict[str, Any]] = None,
) -> None:
    # Use service role so we can notify other users (bypass RLS)
    supabase_admin.table("notifications").insert(
        {
            "user_id": str(user_id),
            "event_id": str(event_id) if event_id else None,
            "type": type_,
            "title": title,
            "body": body,
            "meta": meta or {},
            "is_read": False,
        }
    ).execute()


def _notif_upsert_pending_requests(
    host_user_id: UUID,
    event_id: UUID,
    pending_count: int,
) -> None:
    # Dedup unread pending_requests per (host,event)
    existing = (
        supabase_admin.table("notifications")
        .select("id")
        .eq("user_id", str(host_user_id))
        .eq("event_id", str(event_id))
        .eq("type", "pending_requests")
        .eq("is_read", False)
        .order("created_at", desc=True)
        .limit(1)
        .execute()
        .data
        or []
    )

    title = "Pending requests"
    body = f"You have {int(pending_count)} pending request(s)."
    meta = {"request_count": int(pending_count)}
    now_iso = datetime.now(timezone.utc).isoformat()

    if existing:
        # Update the existing unread notif (no spam)
        supabase_admin.table("notifications").update(
            {
                "title": title,
                "body": body,
                "meta": meta,
                "created_at": now_iso,
            }
        ).eq("id", existing[0]["id"]).execute()
    else:
        _notif_create(
            user_id=host_user_id,
            event_id=event_id,
            type_="pending_requests",
            title=title,
            body=body,
            meta=meta,
        )


def _get_event_row_for_notifs(supa, event_id: UUID) -> Optional[Dict[str, Any]]:
    # Best-effort: never break main flow if this fails
    try:
        r = supa.rpc("get_event", {"p_event_id": str(event_id)}).execute()
        if not r.data:
            return None
        return r.data[0] if isinstance(r.data, list) else r.data
    except Exception:
        return None
    

def _count_pending_requests_admin(event_id: UUID) -> int:
    try:
        r = (
            supabase_admin
            .table("event_memberships")
            .select("id", count="exact")
            .eq("event_id", str(event_id))
            .eq("status", "pending")
            .execute()
        )
        return r.count or 0
    except Exception:
        return 0



# ----------------------------
# Routes
# ----------------------------

@router.get("", response_model=List[EventOut])
def get_events(
    include_full: bool = True,
    lat: Optional[float] = Query(None),
    lng: Optional[float] = Query(None),
    user=Depends(get_current_user),
):
    token = _require_token(user)
    supa = get_supabase_for_user(token)

    try:
        params: Dict[str, Any] = {"include_full": include_full}
        r = supa.rpc("get_events_feed", params).execute()
        rows = r.data or []

        out: List[Dict[str, Any]] = []
        for e in rows:
            status = _effective_status(e)
            if not _is_feed_visible_status(status):
                continue

            mapped = _event_out_from_row(e, using_user_feed=True)

            if lat is not None and lng is not None:
                ev_lat = e.get("lat")
                ev_lng = e.get("lng")
                if ev_lat is not None and ev_lng is not None:
                    try:
                        dist = _haversine_km(float(lat), float(lng), float(ev_lat), float(ev_lng))
                        mapped["distance_km"] = dist
                    except Exception:
                        pass

            out.append(mapped)

        return out

    except APIError as e:
        raise_http_for_api_error(e)


@router.get("/nearby", response_model=List[EventOut])
def get_events_nearby(
    lat: float = Query(...),
    lng: float = Query(...),
    radius_km: float = Query(50.0, ge=1.0, le=500.0),
    include_full: bool = True,
    user=Depends(get_current_user),
):
    token = _require_token(user)
    supa = get_supabase_for_user(token)

    try:
        params: Dict[str, Any] = {"include_full": include_full}
        r = supa.rpc("get_events_feed", params).execute()
        rows = r.data or []

        out: List[Dict[str, Any]] = []
        for e in rows:
            if not _is_feed_visible_status(_effective_status(e)):
                continue

            ev_lat = e.get("lat")
            ev_lng = e.get("lng")
            if ev_lat is None or ev_lng is None:
                continue

            try:
                dist = _haversine_km(float(lat), float(lng), float(ev_lat), float(ev_lng))
            except Exception:
                continue

            if dist <= float(radius_km):
                mapped = _event_out_from_row(e, using_user_feed=True)
                mapped["distance_km"] = dist
                out.append(mapped)

        out.sort(key=lambda x: x.get("distance_km", 999999))
        return out

    except APIError as e:
        raise_http_for_api_error(e)


@router.get("/all", response_model=List[EventOut])
def get_all_events(user=Depends(get_current_user)):
    token = _require_token(user)
    supa = get_supabase_for_user(token)
    try:
        r = supa.rpc("get_events", {}).execute()
        rows = r.data or []

        out: List[Dict[str, Any]] = []
        for e in rows:
            if not _is_feed_visible_status(_effective_status(e)):
                continue
            out.append(_event_out_from_row(e, using_user_feed=True))
        return out

    except APIError as e:
        raise_http_for_api_error(e)


@router.get("/mine", response_model=List[EventOut])
def get_my_events(user=Depends(get_current_user)):
    token = _require_token(user)
    supa = get_supabase_for_user(token)

    try:
        # ✅ FIX: call get_my_events(p_user_id) so Ended events appear
        r = supa.rpc(
            "get_my_events",
            {"p_user_id": str(user["id"])},
        ).execute()

        rows = r.data or []
        return [_event_out_from_row(e, using_user_feed=True) for e in rows]

    except APIError as e:
        raise_http_for_api_error(e)


@router.get("/{event_id}/requests")
def get_event_requests(event_id: UUID, user=Depends(get_current_user)):
    token = _require_token(user)
    supa = get_supabase_for_user(token)

    try:
        r = supa.rpc("get_event_requests", {"p_event_id": str(event_id)}).execute()
        return r.data or []
    except APIError as e:
        raise_http_for_api_error(e)


@router.get("/{event_id}", response_model=EventOut)
def get_event(event_id: UUID, user=Depends(get_current_user)):
    token = _require_token(user)
    supa = get_supabase_for_user(token)
    try:
        r = supa.rpc("get_event", {"p_event_id": str(event_id)}).execute()
        if not r.data:
            raise HTTPException(status_code=404, detail={"code": "EVENT_NOT_FOUND"})
        row = r.data[0] if isinstance(r.data, list) else r.data
        return _event_out_from_row(row, using_user_feed=True)
    except APIError as e:
        raise_http_for_api_error(e)


@router.get("/{event_id}/attendees")
def get_attendees(event_id: UUID, user=Depends(get_current_user)):
    token = _require_token(user)
    supa = get_supabase_for_user(token)
    try:
        r = supa.rpc("get_event_attendees", {"p_event_id": str(event_id)}).execute()
        return r.data or []
    except APIError as e:
        raise_http_for_api_error(e)


@router.patch("/{event_id}", response_model=EventOut)
def update_event(event_id: UUID, body: EditEventIn, user=Depends(get_current_user)):
    token = _require_token(user)
    supa = get_supabase_for_user(token)

    event_res = (
        supa.table("events")
        .select("status, host_user_id")
        .eq("id", str(event_id))
        .single()
        .execute()
    )

    if not event_res.data:
        raise HTTPException(status_code=404, detail={"code": "EVENT_NOT_FOUND"})

    event = event_res.data

    # Verify host
    if event["host_user_id"] != user.get("id"):
        raise HTTPException(status_code=403, detail={"code": "NOT_HOST"})

    # Only editable if Open
    if event["status"] != "Open":
        raise HTTPException(status_code=400, detail={"code": "EVENT_NOT_EDITABLE"})


    updates = body.model_dump(exclude_none=True)

    # ✅ FORMAT: slug → format_id (because events table stores format_id)
    if "format_slug" in updates:
        slug = updates.get("format_slug")
        if slug is not None:
            updates["format_id"] = _format_id_from_slug(supa, str(slug))
        del updates["format_slug"]

    # ✅ normalize host_notes + enforce max length
    if "host_notes" in updates:
        updates["host_notes"] = _normalize_notes(updates.get("host_notes"))
        if updates["host_notes"] is not None and len(updates["host_notes"]) > HOST_NOTES_MAX:
            raise HTTPException(
                status_code=422,
                detail={"code": "HOST_NOTES_TOO_LONG", "max_length": HOST_NOTES_MAX},
            )

    # ✅ normalize proxies_policy (DB expects 'Yes'|'No'|'Ask' or NULL)
    if "proxies_policy" in updates:
        v = updates.get("proxies_policy")
        if v is not None:
            s = str(v).strip()
            updates["proxies_policy"] = s if s else None

    if not updates:
        r = supa.rpc("get_event", {"p_event_id": str(event_id)}).execute()
        if not r.data:
            raise HTTPException(status_code=404, detail={"code": "EVENT_NOT_FOUND"})
        row = r.data[0] if isinstance(r.data, list) else r.data
        return _event_out_from_row(row, using_user_feed=True)

    try:
        supa.table("events").update(updates).eq("id", str(event_id)).execute()

        r = supa.rpc("get_event", {"p_event_id": str(event_id)}).execute()
        if not r.data:
            raise HTTPException(status_code=404, detail={"code": "EVENT_NOT_FOUND"})
        row = r.data[0] if isinstance(r.data, list) else r.data
        return _event_out_from_row(row, using_user_feed=True)

    except APIError as e:
        raise_http_for_api_error(e)
    except Exception as e:
        raise HTTPException(status_code=400, detail=_parse_supabase_rpc_error(e))


# ----------------------------
# Host actions
# ----------------------------

@router.post("/{event_id}/accept")
def accept_attendee(event_id: UUID, body: AcceptIn, user=Depends(get_current_user)):
    token = _require_token(user)
    supa = get_supabase_for_user(token)
    try:
        r = supa.rpc(
            "accept_attendee",
            {"p_event_id": str(event_id), "p_user_id": str(body.user_id)},
        ).execute()

        # NOTIFICATIONS (ADD): Request Accepted
        try:
            ev = _get_event_row_for_notifs(supa, event_id) or {}
            _notif_create(
                user_id=body.user_id,
                event_id=event_id,
                type_="request_accepted",
                title="Request accepted",
                body=f'You were accepted into "{ev.get("title", "an event")}".',
            )
        except Exception:
            pass

        return r.data
    except APIError as e:
        raise_http_for_api_error(e)
    except Exception as e:
        raise HTTPException(status_code=400, detail=_parse_supabase_rpc_error(e))


@router.post("/{event_id}/reject")
def reject_attendee(event_id: UUID, body: RejectIn, user=Depends(get_current_user)):
    token = _require_token(user)
    supa = get_supabase_for_user(token)
    try:
        r = supa.rpc(
            "reject_attendee",
            {
                "p_event_id": str(event_id),
                "p_user_id": str(body.user_id),
                "p_cooldown_minutes": int(body.cooldown_minutes),
            },
        ).execute()

        # NOTIFICATIONS (ADD): Request Declined
        try:
            ev = _get_event_row_for_notifs(supa, event_id) or {}
            _notif_create(
                user_id=body.user_id,
                event_id=event_id,
                type_="request_declined",
                title="Request declined",
                body=f'Your request was declined for "{ev.get("title", "an event")}".',
                meta={"cooldown_minutes": int(body.cooldown_minutes)},
            )
        except Exception:
            pass

        return r.data
    except APIError as e:
        raise_http_for_api_error(e)
    except Exception as e:
        raise HTTPException(status_code=400, detail=_parse_supabase_rpc_error(e))


@router.post("/{event_id}/join")
def join_event(event_id: UUID, user=Depends(get_current_user)):
    print("JOIN ENDPOINT RUNNING - NEW VERSION")

    user_id = user.get("sub") or user.get("id")
    token = user.get("access_token")

    print("USER ID =", user_id)
    print("TOKEN PRESENT =", token is not None)

    supa = get_supabase_for_user(token)
    try:
        r = supa.rpc("join_event", {"p_event_id": str(event_id)}).execute()
        return r.data
    except APIError as e:
        raise_http_for_api_error(e)
    except Exception as e:
        raise HTTPException(status_code=400, detail=_parse_supabase_rpc_error(e))


@router.post("/{event_id}/leave")
def leave_event(event_id: UUID, user=Depends(get_current_user)):
    token = _require_token(user)
    supa = get_supabase_for_user(token)
    try:
        r = supa.rpc("leave_event", {"p_event_id": str(event_id)}).execute()
        return r.data
    except APIError as e:
        raise_http_for_api_error(e)
    except Exception as e:
        raise HTTPException(status_code=400, detail=_parse_supabase_rpc_error(e))


@router.post("/{event_id}/cancel")
def cancel_event(event_id: UUID, user=Depends(get_current_user)):
    token = _require_token(user)
    supa = get_supabase_for_user(token)
    try:
        r = supa.rpc("cancel_event", {"p_event_id": str(event_id)}).execute()

        # NOTIFICATIONS (ADD): Event Cancelled -> notify all attendees
        try:
            ev = _get_event_row_for_notifs(supa, event_id) or {}
            title = "Event cancelled"
            body_txt = f'"{ev.get("title", "An event")}" was cancelled.'

            a = supa.rpc("get_event_attendees", {"p_event_id": str(event_id)}).execute()
            attendees = a.data or []

            for row in attendees:
                uid = row.get("user_id") or row.get("id")
                if not uid:
                    continue
                try:
                    _notif_create(
                        user_id=UUID(str(uid)),
                        event_id=event_id,
                        type_="event_cancelled",
                        title=title,
                        body=body_txt,
                    )
                except Exception:
                    continue
        except Exception:
            pass

        return r.data
    except APIError as e:
        raise_http_for_api_error(e)
    except Exception as e:
        raise HTTPException(status_code=400, detail=_parse_supabase_rpc_error(e))


@router.post("/{event_id}/kick")
def kick_attendee(event_id: UUID, body: KickIn, user=Depends(get_current_user)):
    token = _require_token(user)
    supa = get_supabase_for_user(token)
    try:
        r = supa.rpc(
            "kick_attendee",
            {
                "p_event_id": str(event_id),
                "p_user_id": str(body.user_id),
            },
        ).execute()

        # NOTIFICATIONS (ADD): Kicked
        try:
            ev = _get_event_row_for_notifs(supa, event_id) or {}
            _notif_create(
                user_id=body.user_id,
                event_id=event_id,
                type_="kicked",
                title="Removed from event",
                body=f'You were removed from "{ev.get("title", "an event")}".',
                meta={"cooldown_minutes": int(body.cooldown_minutes)},
            )
        except Exception:
            pass

        return r.data
    except APIError as e:
        raise_http_for_api_error(e)
    except Exception as e:
        raise HTTPException(status_code=400, detail=_parse_supabase_rpc_error(e))


@router.patch("/{event_id}/notes")
def update_notes(event_id: UUID, body: NotesIn, user=Depends(get_current_user)):
    token = _require_token(user)
    supa = get_supabase_for_user(token)
    try:
        host_notes = _normalize_notes(body.host_notes)

        if host_notes is not None and len(host_notes) > HOST_NOTES_MAX:
            raise HTTPException(
                status_code=422,
                detail={"code": "HOST_NOTES_TOO_LONG", "max_length": HOST_NOTES_MAX},
            )

        r = supa.rpc(
            "update_event_notes",
            {"p_event_id": str(event_id), "p_host_notes": host_notes},
        ).execute()
        return r.data

    except APIError as e:
        raise_http_for_api_error(e)
    except Exception as e:
        raise HTTPException(status_code=400, detail=_parse_supabase_rpc_error(e))


@router.post("")
def create_event(payload: Dict[str, Any], user=Depends(get_current_user)):
    supa = _get_supa(user)

    host_notes = _normalize_notes(payload.get("host_notes"))
    if host_notes is not None and len(host_notes) > HOST_NOTES_MAX:
        raise HTTPException(
            status_code=422,
            detail={"code": "HOST_NOTES_TOO_LONG", "max_length": HOST_NOTES_MAX},
        )

    format_slug = payload.get("format_slug")
    print("CREATE_EVENT payload.format_slug =", format_slug)
    print("CREATE_EVENT payload keys =", list(payload.keys()))

    if not format_slug or not str(format_slug).strip():
        raise HTTPException(
            status_code=422,
            detail={"code": "FORMAT_SLUG_REQUIRED"},
        )

    params = {
        "p_title": payload["title"],
        "p_description": payload.get("description") or "",
        "p_starts_at": payload["starts_at"],
        "p_duration_minutes": int(payload["duration_minutes"]),
        "p_max_players": int(payload["max_players"]),
        "p_power_level": payload.get("power_level"),
        "p_proxies_policy": payload.get("proxies_policy"),
        "p_format_slug": str(format_slug).strip().lower(),
        "p_address_text": payload.get("address_text"),
        "p_place_id": payload.get("place_id") or "",
        "p_lat": payload.get("lat"),
        "p_lng": payload.get("lng"),
        "p_host_notes": host_notes,
        "p_city_id": None,
    }

    try:
        r = supa.rpc("create_event", params).execute()
        return r.data
    except APIError as e:
        raise_http_for_api_error(e)
    except Exception as e:
        raise HTTPException(status_code=400, detail=_parse_supabase_rpc_error(e))


