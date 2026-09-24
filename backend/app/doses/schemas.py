from datetime import date, datetime, time
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
    scheduled_local_date: date
    scheduled_local_time: time
    timezone: str
    quantity: Decimal
    unit: str
    meal_relation: str | None
    status: str
    snoozed_until: datetime | None
    taken_at: datetime | None
    skipped_at: datetime | None
    missed_at: datetime | None


class TodayDoseResponse(DoseProjection):
    family_member_name: str
    medication_name: str
    strength: str | None
    effective_reminder_at: datetime


class TodayMemberResponse(BaseModel):
    member_id: UUID
    member_name: str
    relationship: str
    local_date: date
    timezone: str
    taken_count: int
    total_count: int
    doses: list[TodayDoseResponse]


class DoseEventResponse(BaseModel):
    action: str
    occurred_at: datetime
    recorded_at: datetime
    metadata: dict[str, object]


class HistoryDoseResponse(TodayDoseResponse):
    events: list[DoseEventResponse]


class HistoryDayResponse(BaseModel):
    local_date: date
    doses: list[HistoryDoseResponse]


class MemberHistoryResponse(BaseModel):
    member_id: UUID
    member_name: str
    timezone: str
    from_date: date
    to_date: date
    marked_adherence_percentage: Decimal | None
    days: list[HistoryDayResponse]
