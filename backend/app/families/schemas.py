from datetime import date
from typing import Annotated, Literal
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import BaseModel, ConfigDict, StringConstraints, field_validator, model_validator

Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=120)]
Relationship = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=40),
]


def _validate_timezone(value: str) -> str:
    try:
        ZoneInfo(value)
    except ZoneInfoNotFoundError as exc:
        raise ValueError("invalid IANA timezone") from exc
    return value


def _validate_dob(value: date | None) -> date | None:
    if value is not None and value > date.today():
        raise ValueError("date of birth cannot be in the future")
    return value


class FamilyMemberCreate(BaseModel):
    name: Name
    relationship: Relationship
    date_of_birth: date | None = None
    preferred_language: Literal["en", "bn"]
    timezone: str

    _dob = field_validator("date_of_birth")(_validate_dob)
    _timezone = field_validator("timezone")(_validate_timezone)


class FamilyMemberUpdate(BaseModel):
    name: Name | None = None
    relationship: Relationship | None = None
    date_of_birth: date | None = None
    preferred_language: Literal["en", "bn"] | None = None
    timezone: str | None = None

    @field_validator("date_of_birth")
    @classmethod
    def validate_dob(cls, value: date | None) -> date | None:
        return _validate_dob(value)

    @field_validator("timezone")
    @classmethod
    def validate_timezone(cls, value: str | None) -> str | None:
        return None if value is None else _validate_timezone(value)

    @model_validator(mode="after")
    def reject_null_required_fields(self) -> "FamilyMemberUpdate":
        for field_name in ("name", "relationship", "preferred_language", "timezone"):
            if field_name in self.model_fields_set and getattr(self, field_name) is None:
                raise ValueError(f"{field_name} cannot be null")
        return self


class FamilyMemberResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    relationship: str
    date_of_birth: date | None
    preferred_language: str
    timezone: str
