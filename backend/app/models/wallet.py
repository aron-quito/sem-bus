import uuid
import enum
from datetime import datetime, timezone
from decimal import Decimal
from typing import Optional, List, TYPE_CHECKING
from sqlalchemy import Integer, String, Numeric, DateTime, ForeignKey, Uuid, text, CheckConstraint, Enum as SQLEnum
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base

if TYPE_CHECKING:
    from app.models.user import User


class TransactionType(str, enum.Enum):
    RECHARGE_CREDIT = "RECHARGE_CREDIT"
    TRIP_DEBIT = "TRIP_DEBIT"
    REFUND_CREDIT = "REFUND_CREDIT"
    ADJUSTMENT = "ADJUSTMENT"


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Wallet(Base):
    __tablename__ = "wallets"
    __table_args__ = (
        CheckConstraint("points_balance >= 0", name="chk_wallets_non_negative_points"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=text("gen_random_uuid()")
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
        index=True
    )
    points_balance: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    last_transaction_id: Mapped[Optional[uuid.UUID]] = mapped_column(Uuid(as_uuid=True), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=utcnow,
        onupdate=utcnow,
        server_default=text("NOW()")
    )

    # Relaciones
    user: Mapped["User"] = relationship("User", back_populates="wallet")
    transactions: Mapped[List["LedgerTransaction"]] = relationship(
        "LedgerTransaction",
        back_populates="wallet",
        cascade="all, delete-orphan",
        order_by="desc(LedgerTransaction.created_at)"
    )


class LedgerTransaction(Base):
    __tablename__ = "ledger_transactions"

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=text("gen_random_uuid()")
    )
    wallet_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("wallets.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    type: Mapped[str] = mapped_column(
        SQLEnum(
            TransactionType,
            name="tx_type",
            native_enum=True,
            values_callable=lambda obj: [e.value for e in obj]
        ),
        nullable=False
    )
    amount_points: Mapped[int] = mapped_column(Integer, nullable=False)
    amount_pen: Mapped[Optional[Decimal]] = mapped_column(Numeric(10, 2), nullable=True)
    reference_id: Mapped[Optional[uuid.UUID]] = mapped_column(Uuid(as_uuid=True), nullable=True)
    reference_type: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    balance_before: Mapped[int] = mapped_column(Integer, nullable=False)
    balance_after: Mapped[int] = mapped_column(Integer, nullable=False)
    description: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=utcnow,
        server_default=text("NOW()"),
        index=True
    )

    wallet: Mapped["Wallet"] = relationship("Wallet", back_populates="transactions")
