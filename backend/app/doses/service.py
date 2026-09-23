from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.common.errors import ApiError
from app.doses.models import DoseLog, ScheduledDose
from app.doses.reconciliation import reconcile_schedule
from app.doses.repository import get_log_by_client_action_id, require_accessible_dose
from app.doses.schemas import CorrectionRequest, DoseActionRequest, DoseProjection, SnoozeRequest

_FINAL_STATUSES = {"taken", "skipped", "missed"}


async def mark_taken(
    session: AsyncSession,
    user_id: UUID,
    dose_id: UUID,
    payload: DoseActionRequest,
    *,
    now_utc: datetime | None = None,
) -> ScheduledDose:
    return await _apply_ordinary_action(
        session,
        user_id,
        dose_id,
        payload,
        operation="taken",
        log_action="marked_taken",
        now_utc=now_utc,
    )


async def skip_dose(
    session: AsyncSession,
    user_id: UUID,
    dose_id: UUID,
    payload: DoseActionRequest,
    *,
    now_utc: datetime | None = None,
) -> ScheduledDose:
    return await _apply_ordinary_action(
        session,
        user_id,
        dose_id,
        payload,
        operation="skipped",
        log_action="skipped",
        now_utc=now_utc,
    )


async def snooze_dose(
    session: AsyncSession,
    user_id: UUID,
    dose_id: UUID,
    payload: SnoozeRequest,
    *,
    now_utc: datetime | None = None,
) -> ScheduledDose:
    now = _server_now(now_utc)
    dose = await require_accessible_dose(session, user_id, dose_id, for_write=True)
    await reconcile_schedule(session, dose.schedule_id, now)
    await session.refresh(dose)

    duplicate = await _check_idempotency(
        session,
        payload.client_action_id,
        dose.id,
        "snoozed",
    )
    if duplicate:
        return dose

    occurred_at = _validate_action_time(payload.occurred_at, now)
    snoozed_until = _require_aware_utc(payload.snoozed_until, "snoozed_until")
    if snoozed_until <= occurred_at:
        raise ApiError(
            422,
            "VALIDATION_ERROR",
            "Request validation failed.",
            {"fields": [{"msg": "snoozed_until must be later than occurred_at"}]},
        )
    if dose.status != "pending":
        raise ApiError(409, "DOSE_NOT_PENDING", "Only a pending dose can be snoozed.")

    dose.snoozed_until = snoozed_until
    session.add(
        _user_log(
            dose,
            "snoozed",
            user_id,
            payload.client_action_id,
            occurred_at,
            now,
            {"snoozed_until": snoozed_until.isoformat()},
        )
    )
    await session.commit()
    await session.refresh(dose)
    return dose


async def correct_dose(
    session: AsyncSession,
    user_id: UUID,
    dose_id: UUID,
    payload: CorrectionRequest,
    *,
    now_utc: datetime | None = None,
) -> ScheduledDose:
    now = _server_now(now_utc)
    dose = await require_accessible_dose(session, user_id, dose_id, for_write=True)
    await reconcile_schedule(session, dose.schedule_id, now)
    await session.refresh(dose)

    duplicate = await _check_idempotency(
        session,
        payload.client_action_id,
        dose.id,
        "corrected",
    )
    if duplicate:
        return dose

    occurred_at = _validate_action_time(payload.occurred_at, now)
    effective_at = _require_aware_utc(payload.effective_at, "effective_at")
    if effective_at > occurred_at:
        raise ApiError(
            422,
            "VALIDATION_ERROR",
            "Request validation failed.",
            {"fields": [{"msg": "effective_at cannot be later than occurred_at"}]},
        )
    if dose.status not in _FINAL_STATUSES:
        raise ApiError(409, "DOSE_NOT_FINALIZED", "Only a finalized dose can be corrected.")

    previous_status = dose.status
    dose.status = payload.new_status
    dose.snoozed_until = None
    if payload.new_status == "taken":
        dose.taken_at = effective_at
    elif payload.new_status == "skipped":
        dose.skipped_at = effective_at
    else:
        dose.missed_at = effective_at

    session.add(
        _user_log(
            dose,
            "corrected",
            user_id,
            payload.client_action_id,
            occurred_at,
            now,
            {
                "previous_status": previous_status,
                "new_status": payload.new_status,
                "effective_at": effective_at.isoformat(),
                "reason": payload.reason,
            },
        )
    )
    await session.commit()
    await session.refresh(dose)
    return dose


async def _apply_ordinary_action(
    session: AsyncSession,
    user_id: UUID,
    dose_id: UUID,
    payload: DoseActionRequest,
    *,
    operation: str,
    log_action: str,
    now_utc: datetime | None,
) -> ScheduledDose:
    now = _server_now(now_utc)
    dose = await require_accessible_dose(session, user_id, dose_id, for_write=True)
    await reconcile_schedule(session, dose.schedule_id, now)
    await session.refresh(dose)

    duplicate = await _check_idempotency(
        session,
        payload.client_action_id,
        dose.id,
        log_action,
    )
    if duplicate:
        return dose

    occurred_at = _validate_action_time(payload.occurred_at, now)
    if dose.status in _FINAL_STATUSES:
        raise ApiError(
            409,
            "DOSE_ALREADY_FINALIZED",
            "Dose is already finalized.",
            {
                "current": DoseProjection.model_validate(dose).model_dump(mode="json"),
            },
        )
    if dose.status not in {"upcoming", "pending"}:
        raise ApiError(409, "INVALID_DOSE_STATE", "Dose cannot be updated from its current state.")

    dose.status = operation
    dose.snoozed_until = None
    if operation == "taken":
        dose.taken_at = occurred_at
    else:
        dose.skipped_at = occurred_at

    session.add(
        _user_log(
            dose,
            log_action,
            user_id,
            payload.client_action_id,
            occurred_at,
            now,
            {},
        )
    )
    await session.commit()
    await session.refresh(dose)
    return dose


async def _check_idempotency(
    session: AsyncSession,
    client_action_id: UUID,
    dose_id: UUID,
    expected_action: str,
) -> bool:
    existing = await get_log_by_client_action_id(session, client_action_id)
    if existing is None:
        return False
    if existing.scheduled_dose_id == dose_id and existing.action == expected_action:
        return True
    raise ApiError(
        409,
        "IDEMPOTENCY_KEY_REUSED",
        "This action identifier was already used for a different operation.",
    )


def _server_now(value: datetime | None) -> datetime:
    if value is None:
        return datetime.now(UTC)
    return _require_aware_utc(value, "now")


def _validate_action_time(value: datetime, now_utc: datetime) -> datetime:
    occurred_at = _require_aware_utc(value, "occurred_at")
    if occurred_at > now_utc + timedelta(minutes=5):
        raise ApiError(
            422,
            "VALIDATION_ERROR",
            "Request validation failed.",
            {"fields": [{"msg": "occurred_at cannot be more than 5 minutes in the future"}]},
        )
    return occurred_at


def _require_aware_utc(value: datetime, field_name: str) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ApiError(
            422,
            "VALIDATION_ERROR",
            "Request validation failed.",
            {"fields": [{"msg": f"{field_name} must include a timezone"}]},
        )
    return value.astimezone(UTC)


def _user_log(
    dose: ScheduledDose,
    action: str,
    user_id: UUID,
    client_action_id: UUID,
    occurred_at: datetime,
    recorded_at: datetime,
    metadata: dict[str, object],
) -> DoseLog:
    return DoseLog(
        scheduled_dose_id=dose.id,
        action=action,
        performed_by_user_id=user_id,
        client_action_id=client_action_id,
        occurred_at=occurred_at,
        recorded_at=recorded_at,
        event_metadata=metadata,
    )
