from datetime import datetime
from typing import Literal, Optional, List
from uuid import UUID

from pydantic import BaseModel, ConfigDict


EventStatus = Literal["Open", "Full", "Cancelled"]


class Attendee(BaseModel):
    model_config = ConfigDict(extra="forbid")

    user_id: UUID
    nickname: Optional[str] = None
    avatar_url: Optional[str] = None
    joined_at: datetime


class EventListItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    title: str
    starts_at: datetime
    max_players: int
    attendees_count: int
    is_joined: bool
    status: EventStatus


class EventDetail(EventListItem):
    model_config = ConfigDict(extra="forbid")

    host_user_id: UUID
    can_cancel: bool
    attendees: List[Attendee]

