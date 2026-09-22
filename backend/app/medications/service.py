from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.common.errors import ApiError
from app.medications.models import MemberMedication
from app.medications.repository import (
    list_member_medications,
    require_accessible_medication,
    require_writable_member,
)
from app.medications.schemas import ManualMedicationCreate, ManualMedicationUpdate


async def list_for_member(
    session: AsyncSession,
    user_id: UUID,
    member_id: UUID,
) -> list[MemberMedication]:
    return await list_member_medications(session, user_id, member_id)


async def create_manual_medication(
    session: AsyncSession,
    user_id: UUID,
    member_id: UUID,
    payload: ManualMedicationCreate,
) -> MemberMedication:
    await require_writable_member(session, user_id, member_id)
    medication = MemberMedication(
        family_member_id=member_id,
        medicine_master_id=None,
        prescription_id=None,
        extraction_id=None,
        display_name=payload.display_name,
        strength=payload.strength,
        dosage_form=payload.dosage_form,
        status="draft",
        start_date=payload.start_date,
        end_date=payload.end_date,
        created_by_user_id=user_id,
    )
    session.add(medication)
    await session.commit()
    await session.refresh(medication)
    return medication


async def get_medication(
    session: AsyncSession,
    user_id: UUID,
    medication_id: UUID,
) -> MemberMedication:
    return await require_accessible_medication(session, user_id, medication_id)


async def update_medication(
    session: AsyncSession,
    user_id: UUID,
    medication_id: UUID,
    payload: ManualMedicationUpdate,
) -> MemberMedication:
    medication = await require_accessible_medication(
        session,
        user_id,
        medication_id,
        for_write=True,
    )
    changes = payload.model_dump(exclude_unset=True)
    next_start = changes.get("start_date", medication.start_date)
    next_end = changes.get("end_date", medication.end_date)
    if next_end is not None and next_end < next_start:
        raise ApiError(
            422,
            "VALIDATION_ERROR",
            "Request validation failed.",
            {"fields": [{"msg": "end date cannot be before start date"}]},
        )
    for field_name, value in changes.items():
        setattr(medication, field_name, value)
    await session.commit()
    await session.refresh(medication)
    return medication
