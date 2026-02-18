from fastapi import APIRouter
from app.supabase_client import supabase_admin

router = APIRouter(prefix="/cities", tags=["cities"])

@router.get("")
def list_cities():
    res = (
        supabase_admin
        .table("cities")
        .select("id,name,center_lat,center_lng,radius_m")
        .eq("is_active", True)
        .order("name")
        .execute()
    )
    return {"cities": res.data or []}

