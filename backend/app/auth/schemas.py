from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, StringConstraints, field_validator, model_validator

Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=120)]
Password = Annotated[str, StringConstraints(min_length=8, max_length=128)]


class RegisterRequest(BaseModel):
    name: Name
    email: EmailStr
    password: Password

    @field_validator("email", mode="before")
    @classmethod
    def normalize_email(cls, value: object) -> str:
        return str(value).strip().lower()


class LoginRequest(BaseModel):
    email: EmailStr
    password: Password

    @field_validator("email", mode="before")
    @classmethod
    def normalize_email(cls, value: object) -> str:
        return str(value).strip().lower()


class GoogleSignInRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id_token: Annotated[str, StringConstraints(min_length=40, max_length=8192)]


class RefreshRequest(BaseModel):
    refresh_token: str


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    email: str
    preferred_language: str
    timezone: str
    has_password: bool


class UpdateAccountRequest(BaseModel):
    """Editable account details, excluding identity and medication settings."""

    model_config = ConfigDict(extra="forbid")

    name: Name
    preferred_language: Literal["en", "bn"]


class DeleteAccountRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    password: Password | None = None
    google_id_token: Annotated[str, StringConstraints(min_length=40, max_length=8192)] | None = None

    @model_validator(mode="after")
    def exactly_one_confirmation(self) -> "DeleteAccountRequest":
        if (self.password is None) == (self.google_id_token is None):
            raise ValueError("Confirm with either a password or a Google ID token.")
        return self


class AuthResponse(BaseModel):
    user: UserResponse
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class RefreshResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
