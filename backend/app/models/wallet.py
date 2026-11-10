import uuid
from datetime import datetime
from typing import Optional
from sqlalchemy import Integer, DateTime, ForeignKey, text, CheckConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class Wallet(Base):
    __tablename__ = "wallets"
    __table_args__ = (
        CheckConstraint("points_balance >= 0", name="chk_wallets_non_negative_points"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=text("gen_random_uuid()")
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
        index=True
    )
    points_balance: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    last_transaction_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=datetime.utcnow,
        server_default=text("NOW()")
    )

    # Relación inversa
    user: Mapped["User"] = relationship("User", back_populates="wallet")

