from datetime import datetime, timezone
from decimal import Decimal
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db, get_current_user
from app.models.user import User, UserRole, StudentVerification, StudentVerificationStatus
from app.models.wallet import Wallet, LedgerTransaction, TransactionType
from app.schemas.auth import StudentVerificationSchema
from app.schemas.wallet import (
    WalletMeResponse,
    LedgerTransactionSchema,
    RechargeRequest,
    RechargeResponse,
    SuneduAccreditRequest,
    QrPayRequest,
    QrPayResponse,
)

router = APIRouter()


def _fare_for_role(role: str) -> tuple[int, float]:
    if role == UserRole.STUDENT.value:
        return 7, 0.70
    if role == UserRole.CONADIS.value:
        return 0, 0.00
    return 15, 1.50


@router.get(
    "/me",
    response_model=WalletMeResponse,
    status_code=status.HTTP_200_OK,
    summary="Consultar saldo actual, tarifa activa e historial de movimientos (CU-05 / CU-08)"
)
async def get_my_wallet(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    wallet_stmt = select(Wallet).where(Wallet.user_id == current_user.id)
    wallet_res = await db.execute(wallet_stmt)
    wallet = wallet_res.scalar_one_or_none()
    if not wallet:
        wallet = Wallet(user_id=current_user.id, points_balance=0)
        db.add(wallet)
        await db.commit()
        await db.refresh(wallet)

    tx_stmt = (
        select(LedgerTransaction)
        .where(LedgerTransaction.user_id == current_user.id)
        .order_by(LedgerTransaction.created_at.desc())
        .limit(50)
    )
    tx_res = await db.execute(tx_stmt)
    tx_rows = tx_res.scalars().all()

    sv_stmt = select(StudentVerification).where(StudentVerification.user_id == current_user.id)
    sv_res = await db.execute(sv_stmt)
    sv_row = sv_res.scalar_one_or_none()
    sv_schema = None
    if sv_row:
        sv_schema = StudentVerificationSchema(
            dni=sv_row.dni,
            university=sv_row.university or "UNJBG Tacna",
            career=sv_row.career,
            academic_cycle=sv_row.academic_cycle,
            status=sv_row.status,
            expires_at=sv_row.expires_at.strftime("%Y-%m-%d") if sv_row.expires_at else "2026-12-31",
        )

    fare_pts, fare_pen = _fare_for_role(current_user.role)

    return WalletMeResponse(
        user_id=str(current_user.id),
        phone=current_user.phone,
        name=current_user.name,
        role=current_user.role,
        points_balance=wallet.points_balance,
        balance_pen=round(wallet.points_balance / 10.0, 2),
        fare_points=fare_pts,
        fare_pen=fare_pen,
        student_verification=sv_schema,
        transactions=[
            LedgerTransactionSchema(
                id=str(t.id),
                type=t.type,
                amount_points=t.amount_points,
                amount_pen=float(t.amount_pen or Decimal("0.00")),
                reference_type=t.reference_type,
                balance_before=t.balance_before,
                balance_after=t.balance_after,
                description=t.description or "",
                created_at=t.created_at.isoformat(),
            )
            for t in tx_rows
        ],
    )


@router.post(
    "/recharge",
    response_model=RechargeResponse,
    status_code=status.HTTP_200_OK,
    summary="Recargar Puntos BC vía Yape o Plin (CU-05)"
)
async def recharge_wallet(
    payload: RechargeRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    wallet_stmt = select(Wallet).where(Wallet.user_id == current_user.id)
    wallet_res = await db.execute(wallet_stmt)
    wallet = wallet_res.scalar_one_or_none()
    if not wallet:
        wallet = Wallet(user_id=current_user.id, points_balance=0)
        db.add(wallet)
        await db.flush()

    balance_before = wallet.points_balance
    balance_after = balance_before + payload.amount_points
    amount_pen = round(payload.amount_points / 10.0, 2)

    tx = LedgerTransaction(
        wallet_id=wallet.id,
        user_id=current_user.id,
        type=TransactionType.RECHARGE_CREDIT.value,
        amount_points=payload.amount_points,
        amount_pen=Decimal(str(amount_pen)),
        reference_type="RECHARGE",
        balance_before=balance_before,
        balance_after=balance_after,
        description=f"Recarga {payload.gateway.upper()} (+{payload.amount_points} pts)",
    )
    db.add(tx)
    await db.flush()

    wallet.points_balance = balance_after
    wallet.last_transaction_id = tx.id
    wallet.updated_at = datetime.now(timezone.utc)

    await db.commit()
    await db.refresh(tx)

    return RechargeResponse(
        success=True,
        message=f"Recarga exitosa de +{payload.amount_points} Puntos BC",
        points_added=payload.amount_points,
        new_balance_points=balance_after,
        new_balance_pen=round(balance_after / 10.0, 2),
        transaction=LedgerTransactionSchema(
            id=str(tx.id),
            type=tx.type,
            amount_points=tx.amount_points,
            amount_pen=float(tx.amount_pen or Decimal("0.00")),
            reference_type=tx.reference_type,
            balance_before=tx.balance_before,
            balance_after=tx.balance_after,
            description=tx.description or "",
            created_at=tx.created_at.isoformat(),
        ),
    )


@router.post(
    "/accredit-sunedu",
    response_model=StudentVerificationSchema,
    status_code=status.HTTP_200_OK,
    summary="Acreditar Carné Universitario SUNEDU y activar tarifa de 7 pts (CU-03)"
)
async def accredit_sunedu(
    payload: SuneduAccreditRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    sv_stmt = select(StudentVerification).where(StudentVerification.user_id == current_user.id)
    sv_res = await db.execute(sv_stmt)
    sv = sv_res.scalar_one_or_none()

    if not sv:
        sv = StudentVerification(
            user_id=current_user.id,
            dni=payload.dni,
            university=payload.university,
            career=payload.career,
            academic_cycle="2026-II",
            status=StudentVerificationStatus.ACTIVE.value,
            expires_at=datetime(2026, 12, 31, 23, 59, 59, tzinfo=timezone.utc),
        )
        db.add(sv)
    else:
        sv.dni = payload.dni
        sv.university = payload.university
        sv.career = payload.career
        sv.status = StudentVerificationStatus.ACTIVE.value

    current_user.role = UserRole.STUDENT.value
    current_user.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(sv)

    return StudentVerificationSchema(
        dni=sv.dni,
        university=sv.university or payload.university,
        career=sv.career,
        academic_cycle=sv.academic_cycle,
        status=sv.status,
        expires_at="2026-12-31",
    )


@router.post(
    "/pay-qr",
    response_model=QrPayResponse,
    status_code=status.HTTP_200_OK,
    summary="Validar pago de pasaje con QR dinámico y acompañantes (CU-01 / RN-07)"
)
async def pay_qr_passage(
    payload: QrPayRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    wallet_stmt = select(Wallet).where(Wallet.user_id == current_user.id)
    wallet_res = await db.execute(wallet_stmt)
    wallet = wallet_res.scalar_one_or_none()
    if not wallet:
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail="Monedero sin saldo suficiente. Recarga Puntos BC para abordar."
        )

    holder_fare, _ = _fare_for_role(current_user.role)
    companions_fare = payload.companions_count * 15  # RN-07: acompañantes pagan tarifa Adulto (15 pts)
    total_points = holder_fare + companions_fare
    total_pen = round(total_points / 10.0, 2)

    if wallet.points_balance < total_points:
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail=f"Saldo insuficiente ({wallet.points_balance} pts). Necesitas {total_points} pts para este abordaje."
        )

    balance_before = wallet.points_balance
    balance_after = balance_before - total_points

    desc = "Pasaje QR Línea 10"
    if payload.companions_count > 0:
        desc += f" (+{payload.companions_count} acomp.)"

    tx = LedgerTransaction(
        wallet_id=wallet.id,
        user_id=current_user.id,
        type=TransactionType.TRIP_DEBIT.value,
        amount_points=-total_points,
        amount_pen=Decimal(str(-total_pen)),
        reference_type="TRIP",
        balance_before=balance_before,
        balance_after=balance_after,
        description=desc,
    )
    db.add(tx)
    await db.flush()

    wallet.points_balance = balance_after
    wallet.last_transaction_id = tx.id
    wallet.updated_at = datetime.now(timezone.utc)

    await db.commit()
    await db.refresh(tx)

    return QrPayResponse(
        success=True,
        message="Pasaje validado exitosamente",
        holder_fare_points=holder_fare,
        companions_count=payload.companions_count,
        companions_fare_points=companions_fare,
        total_points_debited=total_points,
        total_pen_debited=total_pen,
        remaining_points=balance_after,
        transaction=LedgerTransactionSchema(
            id=str(tx.id),
            type=tx.type,
            amount_points=tx.amount_points,
            amount_pen=float(tx.amount_pen or Decimal("0.00")),
            reference_type=tx.reference_type,
            balance_before=tx.balance_before,
            balance_after=tx.balance_after,
            description=tx.description or "",
            created_at=tx.created_at.isoformat(),
        ),
    )

