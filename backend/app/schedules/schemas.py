from datetime import date, time
from decimal import Decimal
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator, model_validator

SchedulePeriod = Literal["morning", "afternoon", "evening", "night", "custom"]
MealRelation = Literal["before_food", "after_food", "with_food", "none", "unspecified"]
UnitText = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=40),
]


class ScheduleTimeInput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    period: SchedulePeriod
    local_time: time
    quantity: Decimal = Field(gt=0, max_digits=10, decimal_places=3)
    unit: UnitText

    @field_validator("local_time")
    @classmethod
    def require_minute_precision(cls, value: time) -> time:
        if value.second != 0 or value.microsecond != 0:
            raise ValueError("reminder time must use minute precision")
        return value


class ScheduleCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    raw_instruction: Annotated[
        str | None,
        StringConstraints(strip_whitespace=True, max_length=500),
    ] = None
    meal_relation: MealRelation | None = None
    timezone: Annotated[
        str,
        StringConstraints(strip_whitespace=True, min_length=1, max_length=64),
    ]
    start_date: date
    end_date: date | None = None
    times: Annotated[list[ScheduleTimeInput], Field(min_length=1, max_length=8)]

    @field_validator("raw_instruction")
    @classmethod
    def normalize_instruction(cls, value: str | None) -> str | None:
        return None if value == "" else value

    @model_validator(mode="after")
    def validate_schedule(self) -> "ScheduleCreate":
        if self.end_date is not None and self.end_date < self.start_date:
            raise ValueError("end date cannot be before start date")
        clocks = [item.local_time for item in self.times]
        if len(clocks) != len(set(clocks)):
            raise ValueError("reminder times must be unique")
        return self


class ScheduleUpdate(ScheduleCreate):
    pass


class ScheduleTimeResponse(BaseModel):
    id: UUID
    period: str
    local_time: time
    quantity: Decimal
    unit: str
    sort_order: int


class ScheduleResponse(BaseModel):
    id: UUID
    member_medication_id: UUID
    raw_instruction: str | None
    meal_relation: str | None
    timezone: str
    start_date: date
    end_date: date | None
    status: str
    times: list[ScheduleTimeResponse]
