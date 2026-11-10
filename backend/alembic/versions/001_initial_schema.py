"""001 Initial Schema BC System

Revision ID: 001_initial_schema
Revises: 
Create Date: 2026-11-10 12:00:00.000000

"""
from typing import Sequence, Union
from pathlib import Path
from alembic import op
import sqlalchemy as sa

revision: str = '001_initial_schema'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Cargar y ejecutar el DDL oficial de PostgreSQL 15+ de docs/modelo_datos/
    ddl_path = Path(__file__).resolve().parents[4] / "docs" / "modelo_datos" / "02_Script_SQL_DDL.sql"
    if ddl_path.exists():
        sql_content = ddl_path.read_text(encoding="utf-8")
        op.execute(sa.text(sql_content))
    else:
        # Fallback local container
        op.execute(sa.text("""
            CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
            CREATE EXTENSION IF NOT EXISTS "pgcrypto";
        """))


def downgrade() -> None:
    op.execute(sa.text("""
        DROP TABLE IF EXISTS user_sessions CASCADE;
        DROP TABLE IF EXISTS wallets CASCADE;
        DROP TABLE IF EXISTS users CASCADE;
    """))

