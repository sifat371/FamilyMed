from datetime import date, datetime, time
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.doses.models import ScheduledDose


def local_occurrence_to_utc(
    local_date: date,
    local_time: time,
    timezone_name: str,
) -> datetime:
    raise NotImplementedError


async def generate_schedule_window(
    session: AsyncSession,
    schedule_id: UUID,
    now_utc: datetime,
) -> list[ScheduledDose]:
    raise NotImplementedError
