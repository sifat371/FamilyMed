from app.families.models import Family, FamilyMembership
from app.users.models import User
from sqlalchemy import select


async def test_user_family_membership_models_persist(db_session):
    user = User(name="Sifat", email="sifat@example.com", password_hash="argon2-hash")
    db_session.add(user)
    await db_session.flush()
    family = Family(name="Sifat's family", created_by_user_id=user.id)
    db_session.add(family)
    await db_session.flush()
    membership = FamilyMembership(
        family_id=family.id,
        user_id=user.id,
        role="owner",
        status="active",
    )
    db_session.add(membership)
    await db_session.flush()
    saved = await db_session.scalar(select(User).where(User.id == user.id))
    assert saved is not None
    assert saved.email == "sifat@example.com"
    assert membership.role == "owner"
    assert membership.status == "active"
