## GET /events
Devuelve: [{EventListItem}]

EventListItem:
- id: uuid
- name: string
- starts_at: ISO datetime
- status: "Open" | "Full" | "Cancelled"
- capacity: int
- attendees_count: int
- is_joined: bool

## GET /events/{id}
Devuelve: EventDetail

EventDetail = EventListItem +
- created_by: uuid
- can_cancel: bool
- attendees: [{Attendee}]
Attendee:
- user_id: uuid
- display_name: string | null
- joined_at: ISO datetime

