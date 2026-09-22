from datetime import date
from typing import Annotated
from uuid import UUID

from pydantic import BaseModel, ConfigDict, StringConstraints, field_validator, model_validator

DisplayName = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=180),
]
OptionalText = Annotated[
    str | None,
    StringConstraints(strip_whitespace=True, max_length=80),
]


class ManualMedicationCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    display_name: DisplayName
    strength: OptionalText = None
    dosage_form: OptionalText = None
    start_date: date
    end_date: date | None = None

    @field_validator("strength", "dosage_form")
    @classmethod
    def normalize_optional_text(cls, value: str | None) -> str | None:
        return None if value == "" else value

    @model_validator(mode="after")
    def validate_dates(self) -> "ManualMedicationCreate":
        if self.end_date is not None and self.end_date < self.start_date:
            raise ValueError("end date cannot be before start date")
        return self


class ManualMedicationUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    display_name: DisplayName | None = None
    strength: OptionalText = None
    dosage_form: OptionalText = None
    start_date: date | None = None
    end_date: date | None = None

    @field_validator("strength", "dosage_form")
    @classmethod
    def normalize_optional_text(cls, value: str | None) -> str | None:
        return None if value == "" else value

    @model_validator(mode="after")
    def reject_null_required_fields(self) -> "ManualMedicationUpdate":
        for field_name in ("display_name", "start_date"):
            if field_name in self.model_fields_set and getattr(self, field_name) is None:
                raise ValueError(f"{field_name} cannot be null")
        if (
            self.start_date is not None
            and self.end_date is not None
            and self.end_date < self.start_date
        ):
            raise ValueError("end date cannot be before start date")
        return self


class MemberMedicationResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    family_member_id: UUID
    medicine_master_id: UUID | None
    display_name: str
    strength: str | None
    dosage_form: str | None
    status: str
    start_date: date
    end_date: date | None
