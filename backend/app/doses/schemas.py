from datetime import datetime
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


class DoseActionRequest(BaseModel):
    client_action_id: UUID
    occurred_at: datetime


class SnoozeRequest(DoseActionRequest):
    snoozed_until: datetime

    @model_validator(mode="after")
    def validate_snooze_time(self) -> "SnoozeRequest":
        if self.snoozed_until <= self.occurred_at:
            raise ValueError("snoozed_until must be later than occurred_at")
        return self


class CorrectionRequest(DoseActionRequest):
    new_status: Literal["taken", "skipped", "missed"]
    effective_at: datetime
    reason: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def validate_effective_time(self) -> "CorrectionRequest":
        if self.effective_at > self.occurred_at:
            raise ValueError("effective_at cannot be later than occurred_at")
        return self


class DoseProjection(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    schedule_id: UUID
    family_member_id: UUID
    member_medication_id: UUID
    scheduled_at: datetime
    scheduled_local_date: object
    scheduled_local_time: object
    timezone: str
    quantity: Decimal
    unit: str
    meal_relation: str | None
    status: str
    snoozed_until: datetime | None
    taken_at: datetime | None
    skipped_at: datetime | None
    missed_at: datetime | None
