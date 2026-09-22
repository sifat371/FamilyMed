from datetime import datetime
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession


async def reconcile_schedule(
    session: AsyncSession,
    schedule_id: UUID,
    now_utc: datetime,
) -> None:
    raise NotImplementedError
