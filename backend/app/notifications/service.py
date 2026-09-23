from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.families.repository import require_accessible_member
from app.notifications.models import NotificationPreference
from app.notifications.schemas import (
    NotificationPreferenceResponse,
    NotificationPreferenceUpdate,
)


async def get_notification_preference(
    session: AsyncSession,
    user_id: UUID,
    member_id: UUID,
) -> NotificationPreferenceResponse:
    await require_accessible_member(session, user_id, member_id)
    preference = await _find_preference(session, user_id, member_id)
    if preference is None:
        return NotificationPreferenceResponse(
            member_id=member_id,
            user_id=user_id,
            enabled=False,
            default_snooze_minutes=15,
            caregiver_escalation_enabled=False,
        )
    return _response(preference)


async def update_notification_preference(
    session: AsyncSession,
    user_id: UUID,
    member_id: UUID,
    payload: NotificationPreferenceUpdate,
) -> NotificationPreferenceResponse:
    await require_accessible_member(session, user_id, member_id, for_write=True)
    preference = await _find_preference(session, user_id, member_id)
    if preference is None:
        preference = NotificationPreference(
            family_member_id=member_id,
            user_id=user_id,
            enabled=False,
            default_snooze_minutes=15,
            caregiver_escalation_enabled=False,
        )
        session.add(preference)

    changes = payload.model_dump(exclude_unset=True, exclude_none=True)
    for field_name, value in changes.items():
        setattr(preference, field_name, value)

    await session.commit()
    await session.refresh(preference)
    return _response(preference)


async def _find_preference(
    session: AsyncSession,
    user_id: UUID,
    member_id: UUID,
) -> NotificationPreference | None:
    return await session.scalar(
        select(NotificationPreference).where(
            NotificationPreference.user_id == user_id,
            NotificationPreference.family_member_id == member_id,
        )
    )


def _response(preference: NotificationPreference) -> NotificationPreferenceResponse:
    return NotificationPreferenceResponse(
        member_id=preference.family_member_id,
        user_id=preference.user_id,
        enabled=preference.enabled,
        default_snooze_minutes=preference.default_snooze_minutes,
        caregiver_escalation_enabled=preference.caregiver_escalation_enabled,
    )
