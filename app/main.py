from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
import logging

from app.routes.health import router as health_router
from app.routes.me import router as me_router
from app.routes.cities import router as cities_router
from app.routes.events import router as events_router
from app.routes.decks import router as decks_router
from app.routes.notifications import router as notifications_router  # ✅ ADD
from app.routes import profiles

logger = logging.getLogger("untapgo")

app = FastAPI(title="Tap In API")

# ─────────────────────────────────────────────────────────────
# Global error handler (prevents "silent" 500s)
# ─────────────────────────────────────────────────────────────
@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
  logger.exception("Unhandled error on %s %s", request.method, request.url.path)

  return JSONResponse(
      status_code=500,
      content={
          "error": {
              "code": "INTERNAL_SERVER_ERROR",
              "message": "Unexpected server error",
          }
      },
  )

app.include_router(health_router)
app.include_router(me_router)
app.include_router(cities_router)
app.include_router(events_router)
app.include_router(decks_router)
app.include_router(notifications_router)  # ✅ ADD
app.include_router(profiles.router)
