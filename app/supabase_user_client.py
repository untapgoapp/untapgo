from supabase import create_client
from app.config import SUPABASE_URL, SUPABASE_ANON_KEY

def get_supabase_for_user(access_token: str):
    client = create_client(SUPABASE_URL, SUPABASE_ANON_KEY)

    # Inyecta el JWT del usuario para que PostgREST/RPC vean auth.uid()
    client.postgrest.auth(access_token)

    return client

