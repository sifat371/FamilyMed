"""Authenticated, password-confirmed account erasure for V1 single-owner families.

Do not cascade across shared families. A support-assisted path is needed for
future collaborative accounts and external deletion requests.
"""

from sqlalchemy import delete, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.security import verify_password
from app.common.errors import ApiError
from app.doses.models import DoseLog, ScheduledDose
from app.families.models import Family, FamilyMember, FamilyMembership
from app.medications.models import MemberMedication
from app.notifications.models import NotificationPreference
from app.schedules.models import MedicationSchedule, ScheduleTime
from app.users.models import User


async def delete_account(session: AsyncSession, user: User, password: str) -> None:
    """Erase account-owned care records in a single transaction.

    Shared families are deliberately rejected rather than destroying another
    person's medication history; support must handle those cases individually.
    """

    if not verify_password(password, user.password_hash):
        raise ApiError(401, "INVALID_CREDENTIALS", "Email or password is incorrect.")

    family_ids = select(Family.id).where(Family.created_by_user_id == user.id)
    member_ids = select(FamilyMember.id).where(FamilyMember.family_id.in_(family_ids))
    medication_ids = select(MemberMedication.id).where(
        MemberMedication.family_member_id.in_(member_ids)
    )
    schedule_ids = select(MedicationSchedule.id).where(
        MedicationSchedule.member_medication_id.in_(medication_ids)
    )
    dose_ids = select(ScheduledDose.id).where(ScheduledDose.family_member_id.in_(member_ids))

    # Never wipe a family another account belongs to.
    shared_family = await session.scalar(
        select(FamilyMembership.id).where(
            FamilyMembership.family_id.in_(family_ids),
            FamilyMembership.user_id != user.id,
        ).limit(1)
    )
    external_medication = await session.scalar(
        select(MemberMedication.id).where(
            MemberMedication.created_by_user_id == user.id,
            MemberMedication.family_member_id.not_in(member_ids),
        ).limit(1)
    )
    external_schedule = await session.scalar(
        select(MedicationSchedule.id).where(
            MedicationSchedule.created_by_user_id == user.id,
            MedicationSchedule.member_medication_id.not_in(medication_ids),
        ).limit(1)
    )
    if shared_family or external_medication or external_schedule:
        raise ApiError(
            409,
            "ACCOUNT_DELETION_SUPPORT_REQUIRED",
            "This account has shared records. Contact support for a safe deletion.",
        )

    # Remove references to the user from records belonging to other owners.
    await session.execute(
        update(FamilyMember).where(FamilyMember.linked_user_id == user.id).values(
            linked_user_id=None
        )
    )
    await session.execute(
        update(DoseLog).where(DoseLog.performed_by_user_id == user.id).values(
            performed_by_user_id=None
        )
    )

    await session.execute(delete(DoseLog).where(DoseLog.scheduled_dose_id.in_(dose_ids)))
    await session.execute(
        delete(ScheduledDose).where(ScheduledDose.family_member_id.in_(member_ids))
    )
    await session.execute(
        delete(ScheduleTime).where(ScheduleTime.schedule_id.in_(schedule_ids))
    )
    await session.execute(
        delete(NotificationPreference).where(
            or_(
                NotificationPreference.family_member_id.in_(member_ids),
                NotificationPreference.user_id == user.id,
            )
        )
    )
    await session.execute(
        delete(MedicationSchedule).where(MedicationSchedule.id.in_(schedule_ids))
    )
    await session.execute(
        delete(MemberMedication).where(MemberMedication.id.in_(medication_ids))
    )
    await session.execute(delete(FamilyMember).where(FamilyMember.id.in_(member_ids)))
    await session.execute(
        delete(FamilyMembership).where(
            or_(
                FamilyMembership.family_id.in_(family_ids),
                FamilyMembership.user_id == user.id,
            )
        )
    )
    await session.execute(delete(Family).where(Family.id.in_(family_ids)))
    await session.execute(delete(User).where(User.id == user.id))
    await session.commit()
