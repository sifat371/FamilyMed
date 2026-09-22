from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class NotificationPreferenceUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    enabled: bool | None = None
    default_snooze_minutes: int | None = Field(default=None, ge=1, le=120)


class NotificationPreferenceResponse(BaseModel):
    member_id: UUID
    user_id: UUID
    enabled: bool
    default_snooze_minutes: int
    caregiver_escalation_enabled: bool = False
