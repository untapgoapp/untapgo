from fastapi import APIRouter, Depends, HTTPException
from app.core.supabase import supabase
from app.auth.dependencies import get_current_user

router = APIRouter(prefix="/events", tags=["events"])


@router.get("")
def list_events(current_user=Depends(get_current_user)):
    res = supabase.rpc("get_events").execute()

    if res.error:
        raise HTTPException(status_code=500, detail=res.error.message)

    return res.data


@router.get("/{event_id}")
def get_event(event_id: str, current_user=Depends(get_current_user)):
    res = supabase.rpc("get_event", {"p_event_id": event_id}).execute()

    if res.error:
        raise HTTPException(status_code=500, detail=res.error.message)

    if res.data is None:
        raise HTTPException(status_code=404, detail="Event not found")

    return res.data

