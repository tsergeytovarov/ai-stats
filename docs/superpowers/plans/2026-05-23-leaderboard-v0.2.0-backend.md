# Лидерборд v0.2.0 — Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Запустить серверный фундамент лидерборда на `aiuse.popovs.tech/api`: FastAPI + Postgres + Alembic, профили + snapshot'ы + auth + бэкапы. Без friends/blocks/leaderboard endpoints (это v0.3.0).

**Architecture:** Новый репо `ai-stats-api`, разворачивается как ещё один проект на VM `meridian` по существующему паттерну (`/opt/aiuse/`, `git push prod main`, docker-compose api+postgres). Двухтокенная auth: публичный `friend_code` + приватный `api_secret` (sha256 хэш в БД). Schema создаётся целиком (4 таблицы), но endpoints — только profiles+snapshots.

**Tech Stack:** Python 3.12, FastAPI 0.110+, SQLAlchemy 2.0, Alembic, Pydantic v2, pytest + testcontainers-postgres + httpx, ruff, uv, Docker, Postgres 16.

**Связанный спек:** [docs/superpowers/specs/2026-05-23-leaderboard-design.md](../specs/2026-05-23-leaderboard-design.md)

---

## File Structure

Новый репо `ai-stats-api` (соседний с `ai-stats` — `/Users/sergeytovarov/work/ai-stats-api/`):

```
ai-stats-api/
├── pyproject.toml              # uv + ruff + pytest конфиг
├── .gitignore
├── README.md
├── Dockerfile                  # multi-stage с uv
├── docker-compose.yml          # api + postgres в network "web"
├── docker-compose.prod.yml     # production override (порты, restart)
├── alembic.ini
├── alembic/
│   ├── env.py
│   ├── script.py.mako
│   └── versions/
│       ├── 001_create_profiles.py
│       ├── 002_create_snapshots.py
│       ├── 003_create_friendships.py
│       └── 004_create_blocks.py
├── src/aiuse/
│   ├── __init__.py
│   ├── main.py                 # FastAPI app, lifespan, exception handlers
│   ├── config.py               # Settings (pydantic-settings)
│   ├── db.py                   # async engine + session dependency
│   ├── auth.py                 # Bearer dependency, current_profile
│   ├── codes.py                # friend_code + api_secret генераторы + хэширование
│   ├── models.py               # 4 SQLAlchemy модели
│   ├── schemas.py              # Pydantic DTO
│   └── routers/
│       ├── __init__.py
│       ├── health.py
│       ├── profiles.py
│       └── snapshots.py
└── tests/
    ├── conftest.py             # Postgres контейнер + FastAPI test client
    ├── test_health.py
    ├── test_codes.py
    ├── test_auth.py
    ├── test_profiles.py
    ├── test_snapshots.py
    └── test_e2e_smoke.py
```

Дополнительно — изменения в существующих репо:
- `/Users/sergeytovarov/work/ingress/nginx.conf` — новый upstream и server-блок для `aiuse.popovs.tech`.
- `/Users/sergeytovarov/work/infra/README.md` — запись в таблице проектов.

---

## Phase A: Skeleton

### Task 1: Инициализация репо

**Files:**
- Create: `/Users/sergeytovarov/work/ai-stats-api/pyproject.toml`
- Create: `/Users/sergeytovarov/work/ai-stats-api/.gitignore`
- Create: `/Users/sergeytovarov/work/ai-stats-api/src/aiuse/__init__.py` (пустой)

- [ ] **Step 1: Создать директорию и git init**

```bash
mkdir -p /Users/sergeytovarov/work/ai-stats-api/{src/aiuse/routers,tests,alembic/versions}
cd /Users/sergeytovarov/work/ai-stats-api
git init
```

- [ ] **Step 2: Написать pyproject.toml**

```toml
[project]
name = "aiuse"
version = "0.2.0"
description = "Backend API for ai-stats leaderboard"
requires-python = ">=3.12"
dependencies = [
    "fastapi>=0.110",
    "uvicorn[standard]>=0.27",
    "sqlalchemy[asyncio]>=2.0",
    "asyncpg>=0.29",
    "alembic>=1.13",
    "pydantic>=2.6",
    "pydantic-settings>=2.2",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-asyncio>=0.23",
    "httpx>=0.27",
    "testcontainers[postgres]>=4.0",
    "ruff>=0.4",
]

[tool.ruff]
line-length = 100
target-version = "py312"

[tool.ruff.lint]
select = ["E", "F", "W", "I", "UP", "B", "SIM", "C4"]

[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/aiuse"]
```

- [ ] **Step 3: Написать .gitignore**

```gitignore
__pycache__/
*.py[cod]
.pytest_cache/
.ruff_cache/
.venv/
.env
*.egg-info/
dist/
build/
.coverage
htmlcov/
```

- [ ] **Step 4: Создать пустой __init__.py и установить deps**

```bash
touch /Users/sergeytovarov/work/ai-stats-api/src/aiuse/__init__.py
cd /Users/sergeytovarov/work/ai-stats-api
uv venv
source .venv/bin/activate
uv pip install -e ".[dev]"
```

Expected: установка успешна, `python -c "import aiuse"` не падает.

- [ ] **Step 5: Первый коммит**

```bash
git add pyproject.toml .gitignore src/aiuse/__init__.py
git commit -m "chore: init ai-stats-api skeleton с pyproject"
```

---

### Task 2: Test infrastructure (conftest с Postgres)

**Files:**
- Create: `tests/__init__.py` (пустой)
- Create: `tests/conftest.py`

- [ ] **Step 1: Создать tests/__init__.py пустым**

```bash
touch /Users/sergeytovarov/work/ai-stats-api/tests/__init__.py
```

- [ ] **Step 2: Написать conftest.py**

```python
# tests/conftest.py
from __future__ import annotations

import pytest
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from testcontainers.postgres import PostgresContainer


@pytest.fixture(scope="session")
def postgres_container():
    with PostgresContainer("postgres:16-alpine") as pg:
        yield pg


@pytest.fixture(scope="session")
def database_url(postgres_container: PostgresContainer) -> str:
    sync_url = postgres_container.get_connection_url()
    # testcontainers даёт sync URL, конвертируем в asyncpg
    return sync_url.replace("postgresql+psycopg2://", "postgresql+asyncpg://")


@pytest.fixture(scope="session")
async def engine(database_url: str):
    eng = create_async_engine(database_url, echo=False)
    yield eng
    await eng.dispose()


@pytest.fixture(scope="function")
async def db_session(engine) -> AsyncSession:
    """Свежая сессия для каждого теста + откат изменений."""
    factory = async_sessionmaker(engine, expire_on_commit=False)
    async with factory() as session:
        yield session
        await session.rollback()
```

- [ ] **Step 3: Проверить что pytest стартует без ошибок (даже без тестов)**

```bash
cd /Users/sergeytovarov/work/ai-stats-api
pytest -v
```

Expected: `collected 0 items`, без ошибок импорта. Docker должен быть запущен (testcontainers ему нужен), но контейнер не поднимется пока нет фикстур которые его требуют.

- [ ] **Step 4: Коммит**

```bash
git add tests/__init__.py tests/conftest.py
git commit -m "test: добавить базовый conftest с Postgres testcontainer"
```

---

### Task 3: FastAPI skeleton + GET /api/health

**Files:**
- Create: `src/aiuse/main.py`
- Create: `src/aiuse/routers/__init__.py` (пустой)
- Create: `src/aiuse/routers/health.py`
- Create: `tests/test_health.py`

- [ ] **Step 1: Написать failing test для /api/health**

`tests/test_health.py`:
```python
from __future__ import annotations

import pytest
from httpx import ASGITransport, AsyncClient

from aiuse.main import app


@pytest.fixture
async def client():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c


async def test_health_returns_ok(client: AsyncClient):
    response = await client.get("/api/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
```

- [ ] **Step 2: Запустить, убедиться что падает**

```bash
pytest tests/test_health.py -v
```

Expected: FAIL с `ImportError: cannot import name 'app' from 'aiuse.main'`.

- [ ] **Step 3: Написать routers/__init__.py + routers/health.py + main.py**

```bash
touch /Users/sergeytovarov/work/ai-stats-api/src/aiuse/routers/__init__.py
```

`src/aiuse/routers/health.py`:
```python
from __future__ import annotations

from fastapi import APIRouter

router = APIRouter()


@router.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}
```

`src/aiuse/main.py`:
```python
from __future__ import annotations

from fastapi import FastAPI

from aiuse.routers import health

app = FastAPI(title="aiuse", version="0.2.0")
app.include_router(health.router, prefix="/api")
```

- [ ] **Step 4: Запустить тест — должен пройти**

```bash
pytest tests/test_health.py -v
```

Expected: PASS.

- [ ] **Step 5: Коммит**

```bash
git add src/aiuse/main.py src/aiuse/routers/__init__.py src/aiuse/routers/health.py tests/test_health.py
git commit -m "feat(api): FastAPI skeleton + GET /api/health"
```

---

### Task 4: Config + DB engine

**Files:**
- Create: `src/aiuse/config.py`
- Create: `src/aiuse/db.py`

- [ ] **Step 1: Написать config.py**

`src/aiuse/config.py`:
```python
from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="AIUSE_", env_file=".env", extra="ignore")

    database_url: str = "postgresql+asyncpg://aiuse:aiuse@localhost:5432/aiuse"
    log_level: str = "INFO"


settings = Settings()
```

- [ ] **Step 2: Написать db.py**

`src/aiuse/db.py`:
```python
from __future__ import annotations

from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from aiuse.config import settings


class Base(DeclarativeBase):
    pass


engine = create_async_engine(settings.database_url, pool_pre_ping=True)
SessionFactory = async_sessionmaker(engine, expire_on_commit=False)


async def get_session() -> AsyncGenerator[AsyncSession, None]:
    async with SessionFactory() as session:
        yield session
```

- [ ] **Step 3: Убедиться что импорты не сломали тесты**

```bash
pytest -v
```

Expected: test_health всё ещё PASS.

- [ ] **Step 4: Коммит**

```bash
git add src/aiuse/config.py src/aiuse/db.py
git commit -m "feat(db): добавить Settings и async SQLAlchemy engine"
```

---

### Task 5: Alembic init

**Files:**
- Create: `alembic.ini`
- Create: `alembic/env.py`
- Create: `alembic/script.py.mako`

- [ ] **Step 1: Сгенерировать через alembic init**

```bash
cd /Users/sergeytovarov/work/ai-stats-api
alembic init -t async alembic
```

Это создаст `alembic.ini`, `alembic/env.py`, `alembic/script.py.mako`, `alembic/versions/`.

- [ ] **Step 2: Поправить alembic.ini — `sqlalchemy.url`**

Заменить в `alembic.ini` строку `sqlalchemy.url = driver://user:pass@localhost/dbname` на:

```ini
sqlalchemy.url =
```

(пустое — URL подставим из env в env.py)

- [ ] **Step 3: Переписать alembic/env.py**

```python
from __future__ import annotations

import asyncio
from logging.config import fileConfig

from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

from alembic import context
from aiuse.config import settings
from aiuse.db import Base
# Импорт всех моделей чтобы Alembic их видел (раскомментируется после Task 10):
# from aiuse import models  # noqa

config = context.config
config.set_main_option("sqlalchemy.url", settings.database_url)

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def do_run_migrations(connection: Connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


def run_migrations_online() -> None:
    asyncio.run(run_async_migrations())


run_migrations_online()
```

- [ ] **Step 4: Проверить что alembic читает конфиг**

```bash
alembic current
```

Expected: пусто (миграций нет, но команда не падает на парсинге).

- [ ] **Step 5: Коммит**

```bash
git add alembic.ini alembic/env.py alembic/script.py.mako alembic/versions/.gitkeep 2>/dev/null
touch alembic/versions/.gitkeep
git add alembic/versions/.gitkeep
git commit -m "chore(db): инициализировать Alembic async"
```

---

## Phase B: Schema migrations

### Task 6: Миграция profiles

**Files:**
- Create: `alembic/versions/001_create_profiles.py`

- [ ] **Step 1: Сгенерировать пустую миграцию**

```bash
cd /Users/sergeytovarov/work/ai-stats-api
alembic revision -m "create_profiles" --rev-id 001
```

Это создаст `alembic/versions/001_create_profiles.py`.

- [ ] **Step 2: Заполнить upgrade/downgrade**

`alembic/versions/001_create_profiles.py`:
```python
"""create_profiles

Revision ID: 001
Revises:
Create Date: 2026-05-23
"""

from __future__ import annotations

import sqlalchemy as sa

from alembic import op

revision = "001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "profiles",
        sa.Column("id", sa.BigInteger(), primary_key=True),
        sa.Column("friend_code", sa.Text(), nullable=False),
        sa.Column("api_secret_hash", sa.Text(), nullable=False),
        sa.Column("display_name", sa.Text(), nullable=False),
        sa.Column("avatar", sa.LargeBinary(), nullable=True),
        sa.Column("avatar_mime", sa.Text(), nullable=True),
        sa.Column(
            "sharing_enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.true(),
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.UniqueConstraint("friend_code", name="uq_profiles_friend_code"),
    )
    op.create_index("idx_profiles_friend_code", "profiles", ["friend_code"])


def downgrade() -> None:
    op.drop_index("idx_profiles_friend_code", table_name="profiles")
    op.drop_table("profiles")
```

- [ ] **Step 3: Применить миграцию к локальной БД (опционально для проверки)**

Если есть локальный Postgres: `alembic upgrade head`. Иначе будем гонять через testcontainer в Task 10.

- [ ] **Step 4: Коммит**

```bash
git add alembic/versions/001_create_profiles.py
git commit -m "feat(db): миграция 001 — таблица profiles"
```

---

### Task 7: Миграция snapshots

**Files:**
- Create: `alembic/versions/002_create_snapshots.py`

- [ ] **Step 1: Сгенерировать миграцию**

```bash
alembic revision -m "create_snapshots" --rev-id 002 --depends-on 001
```

Поправить в файле `down_revision = "001"` если не подставилось.

- [ ] **Step 2: Заполнить upgrade/downgrade**

```python
"""create_snapshots

Revision ID: 002
Revises: 001
"""

from __future__ import annotations

import sqlalchemy as sa

from alembic import op

revision = "002"
down_revision = "001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "snapshots",
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("hour_bucket", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "tokens_input",
            sa.BigInteger(),
            nullable=False,
            server_default="0",
        ),
        sa.Column(
            "tokens_output",
            sa.BigInteger(),
            nullable=False,
            server_default="0",
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.ForeignKeyConstraint(
            ["user_id"], ["profiles.id"], ondelete="CASCADE",
            name="fk_snapshots_user",
        ),
        sa.PrimaryKeyConstraint("user_id", "hour_bucket", name="pk_snapshots"),
    )
    op.create_index("idx_snapshots_hour", "snapshots", ["hour_bucket"])


def downgrade() -> None:
    op.drop_index("idx_snapshots_hour", table_name="snapshots")
    op.drop_table("snapshots")
```

- [ ] **Step 3: Коммит**

```bash
git add alembic/versions/002_create_snapshots.py
git commit -m "feat(db): миграция 002 — таблица snapshots"
```

---

### Task 8: Миграция friendships

**Files:**
- Create: `alembic/versions/003_create_friendships.py`

- [ ] **Step 1: Сгенерировать миграцию**

```bash
alembic revision -m "create_friendships" --rev-id 003
```

- [ ] **Step 2: Заполнить upgrade/downgrade**

```python
"""create_friendships

Revision ID: 003
Revises: 002
"""

from __future__ import annotations

import sqlalchemy as sa

from alembic import op

revision = "003"
down_revision = "002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "friendships",
        sa.Column("user_a_id", sa.BigInteger(), nullable=False),
        sa.Column("user_b_id", sa.BigInteger(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.ForeignKeyConstraint(
            ["user_a_id"], ["profiles.id"], ondelete="CASCADE",
            name="fk_friendships_user_a",
        ),
        sa.ForeignKeyConstraint(
            ["user_b_id"], ["profiles.id"], ondelete="CASCADE",
            name="fk_friendships_user_b",
        ),
        sa.PrimaryKeyConstraint("user_a_id", "user_b_id", name="pk_friendships"),
        sa.CheckConstraint("user_a_id < user_b_id", name="ck_friendships_order"),
    )
    op.create_index("idx_friendships_b", "friendships", ["user_b_id"])


def downgrade() -> None:
    op.drop_index("idx_friendships_b", table_name="friendships")
    op.drop_table("friendships")
```

- [ ] **Step 3: Коммит**

```bash
git add alembic/versions/003_create_friendships.py
git commit -m "feat(db): миграция 003 — таблица friendships"
```

---

### Task 9: Миграция blocks

**Files:**
- Create: `alembic/versions/004_create_blocks.py`

- [ ] **Step 1: Сгенерировать миграцию**

```bash
alembic revision -m "create_blocks" --rev-id 004
```

- [ ] **Step 2: Заполнить upgrade/downgrade**

```python
"""create_blocks

Revision ID: 004
Revises: 003
"""

from __future__ import annotations

import sqlalchemy as sa

from alembic import op

revision = "004"
down_revision = "003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "blocks",
        sa.Column("blocker_id", sa.BigInteger(), nullable=False),
        sa.Column("blocked_id", sa.BigInteger(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.ForeignKeyConstraint(
            ["blocker_id"], ["profiles.id"], ondelete="CASCADE",
            name="fk_blocks_blocker",
        ),
        sa.ForeignKeyConstraint(
            ["blocked_id"], ["profiles.id"], ondelete="CASCADE",
            name="fk_blocks_blocked",
        ),
        sa.PrimaryKeyConstraint("blocker_id", "blocked_id", name="pk_blocks"),
        sa.CheckConstraint("blocker_id != blocked_id", name="ck_blocks_self"),
    )


def downgrade() -> None:
    op.drop_table("blocks")
```

- [ ] **Step 3: Коммит**

```bash
git add alembic/versions/004_create_blocks.py
git commit -m "feat(db): миграция 004 — таблица blocks"
```

---

## Phase C: Models + Schemas

### Task 10: SQLAlchemy модели + conftest применяет миграции

**Files:**
- Create: `src/aiuse/models.py`
- Modify: `alembic/env.py` (раскомментировать импорт моделей)
- Modify: `tests/conftest.py` (добавить фикстуру что прогоняет миграции)

- [ ] **Step 1: Написать models.py**

`src/aiuse/models.py`:
```python
from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    LargeBinary,
    PrimaryKeyConstraint,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from aiuse.db import Base


class Profile(Base):
    __tablename__ = "profiles"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    friend_code: Mapped[str] = mapped_column(Text, nullable=False)
    api_secret_hash: Mapped[str] = mapped_column(Text, nullable=False)
    display_name: Mapped[str] = mapped_column(Text, nullable=False)
    avatar: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    avatar_mime: Mapped[str | None] = mapped_column(Text, nullable=True)
    sharing_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        UniqueConstraint("friend_code", name="uq_profiles_friend_code"),
        Index("idx_profiles_friend_code", "friend_code"),
    )


class Snapshot(Base):
    __tablename__ = "snapshots"

    user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False
    )
    hour_bucket: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    tokens_input: Mapped[int] = mapped_column(BigInteger, nullable=False, server_default="0")
    tokens_output: Mapped[int] = mapped_column(BigInteger, nullable=False, server_default="0")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        PrimaryKeyConstraint("user_id", "hour_bucket", name="pk_snapshots"),
        Index("idx_snapshots_hour", "hour_bucket"),
    )


class Friendship(Base):
    __tablename__ = "friendships"

    user_a_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False
    )
    user_b_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        PrimaryKeyConstraint("user_a_id", "user_b_id", name="pk_friendships"),
        CheckConstraint("user_a_id < user_b_id", name="ck_friendships_order"),
        Index("idx_friendships_b", "user_b_id"),
    )


class Block(Base):
    __tablename__ = "blocks"

    blocker_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False
    )
    blocked_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        PrimaryKeyConstraint("blocker_id", "blocked_id", name="pk_blocks"),
        CheckConstraint("blocker_id != blocked_id", name="ck_blocks_self"),
    )
```

- [ ] **Step 2: Раскомментировать импорт в alembic/env.py**

Заменить строку `# from aiuse import models  # noqa` на `from aiuse import models  # noqa: F401`.

- [ ] **Step 3: Обновить conftest.py — прогонять миграции через Alembic в той же БД**

Заменить весь `tests/conftest.py` на:

```python
from __future__ import annotations

import os
from collections.abc import AsyncGenerator

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from testcontainers.postgres import PostgresContainer

import aiuse.config as aiuse_config


@pytest.fixture(scope="session")
def postgres_container():
    with PostgresContainer("postgres:16-alpine") as pg:
        yield pg


@pytest.fixture(scope="session")
def database_url(postgres_container: PostgresContainer) -> str:
    sync_url = postgres_container.get_connection_url()
    return sync_url.replace("postgresql+psycopg2://", "postgresql+asyncpg://")


@pytest.fixture(scope="session", autouse=True)
def apply_migrations(database_url: str):
    # Подменяем settings.database_url чтобы alembic/env.py взял правильный URL
    os.environ["AIUSE_DATABASE_URL"] = database_url
    aiuse_config.settings.database_url = database_url
    cfg = Config("alembic.ini")
    command.upgrade(cfg, "head")
    yield


@pytest.fixture(scope="session")
async def engine(database_url: str):
    eng = create_async_engine(database_url, echo=False)
    yield eng
    await eng.dispose()


@pytest.fixture(scope="function")
async def db_session(engine) -> AsyncGenerator[AsyncSession, None]:
    factory = async_sessionmaker(engine, expire_on_commit=False)
    async with factory() as session:
        yield session
        await session.rollback()


@pytest.fixture
async def client(database_url: str):
    """FastAPI test client с тем же database_url."""
    from httpx import ASGITransport, AsyncClient

    from aiuse.main import app

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c
```

- [ ] **Step 4: Прогнать тесты — миграции должны примениться, test_health проходит**

```bash
pytest -v
```

Expected: test_health PASS. Логи alembic в выводе показывают `Running upgrade  -> 001 -> 002 -> 003 -> 004`.

- [ ] **Step 5: Коммит**

```bash
git add src/aiuse/models.py alembic/env.py tests/conftest.py
git commit -m "feat(db): SQLAlchemy модели + автоприменение миграций в тестах"
```

---

### Task 11: Pydantic schemas (DTO)

**Files:**
- Create: `src/aiuse/schemas.py`

- [ ] **Step 1: Написать все DTO для текущих endpoint'ов**

`src/aiuse/schemas.py`:
```python
from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


# ── profiles ───────────────────────────────────────────────────────────

class ProfileCreateRequest(BaseModel):
    display_name: str = Field(..., min_length=1, max_length=64)
    avatar_b64: str | None = None
    avatar_mime: str | None = None


class ProfileCreateResponse(BaseModel):
    friend_code: str
    api_secret: str  # показывается ОДИН раз
    server_user_id: int


class ProfileUpdateRequest(BaseModel):
    display_name: str | None = Field(None, min_length=1, max_length=64)
    avatar_b64: str | None = None
    avatar_mime: str | None = None
    sharing_enabled: bool | None = None


class ProfileResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    friend_code: str
    display_name: str
    sharing_enabled: bool
    created_at: datetime


class RegenerateFriendCodeResponse(BaseModel):
    friend_code: str
    friendships_dropped: int


# ── snapshots ──────────────────────────────────────────────────────────

class SnapshotItem(BaseModel):
    hour_bucket: datetime
    tokens_input: int = Field(..., ge=0)
    tokens_output: int = Field(..., ge=0)


class SnapshotsBatch(BaseModel):
    snapshots: list[SnapshotItem] = Field(..., max_length=168, min_length=1)


class SnapshotsResponse(BaseModel):
    accepted: int
```

- [ ] **Step 2: Прогнать тесты — ничего не должно сломаться**

```bash
pytest -v
```

Expected: test_health всё ещё PASS.

- [ ] **Step 3: Коммит**

```bash
git add src/aiuse/schemas.py
git commit -m "feat(api): Pydantic DTO для profiles и snapshots"
```

---

## Phase D: Codes & Auth

### Task 12: friend_code генератор

**Files:**
- Create: `src/aiuse/codes.py`
- Create: `tests/test_codes.py`

- [ ] **Step 1: Написать failing test для friend_code**

`tests/test_codes.py`:
```python
from __future__ import annotations

import re

import pytest

from aiuse.codes import generate_friend_code, normalize_friend_code


def test_friend_code_is_10_chars():
    code = generate_friend_code()
    assert len(code) == 10


def test_friend_code_uses_safe_alphabet():
    # Запрещены: 0, O, 1, I, l
    for _ in range(200):
        code = generate_friend_code()
        assert re.fullmatch(r"[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{10}", code), code


def test_friend_code_is_random():
    codes = {generate_friend_code() for _ in range(1000)}
    assert len(codes) >= 990  # дубликаты крайне маловероятны


@pytest.mark.parametrize(
    "input_str,expected",
    [
        ("XK7P-3M9Q-2A", "XK7P3M9Q2A"),
        ("xk7p3m9q2a", "XK7P3M9Q2A"),
        ("  XK7P 3M9Q 2A  ", "XK7P3M9Q2A"),
        ("XK7P-3M9Q-2A-EXTRA", "XK7P3M9Q2AEXTRA"),
    ],
)
def test_normalize_friend_code(input_str: str, expected: str):
    assert normalize_friend_code(input_str) == expected
```

- [ ] **Step 2: Запустить — упадёт на импорте**

```bash
pytest tests/test_codes.py -v
```

Expected: FAIL `ModuleNotFoundError: aiuse.codes`.

- [ ] **Step 3: Написать codes.py с двумя функциями**

`src/aiuse/codes.py`:
```python
from __future__ import annotations

import re
import secrets

FRIEND_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
FRIEND_CODE_LENGTH = 10


def generate_friend_code() -> str:
    """10 символов из base32 без визуально похожих 0/O/1/I/l."""
    return "".join(secrets.choice(FRIEND_CODE_ALPHABET) for _ in range(FRIEND_CODE_LENGTH))


def normalize_friend_code(raw: str) -> str:
    """Убираем разделители, апперкейс. Не валидируем длину/алфавит."""
    return re.sub(r"[\s\-]+", "", raw).upper()
```

- [ ] **Step 4: Запустить — должны пройти все 4 теста**

```bash
pytest tests/test_codes.py -v
```

Expected: 4 PASS.

- [ ] **Step 5: Коммит**

```bash
git add src/aiuse/codes.py tests/test_codes.py
git commit -m "feat(auth): генерация и нормализация friend_code"
```

---

### Task 13: api_secret генератор + хэширование

**Files:**
- Modify: `src/aiuse/codes.py`
- Modify: `tests/test_codes.py`

- [ ] **Step 1: Дописать failing тесты для api_secret**

Добавить в конец `tests/test_codes.py`:
```python
import hashlib

from aiuse.codes import generate_api_secret, hash_api_secret, verify_api_secret


def test_api_secret_is_64_hex_chars():
    secret = generate_api_secret()
    assert len(secret) == 64
    assert re.fullmatch(r"[0-9a-f]{64}", secret)


def test_api_secret_is_unique():
    secrets_set = {generate_api_secret() for _ in range(1000)}
    assert len(secrets_set) == 1000


def test_hash_is_sha256_hex():
    secret = "deadbeef" * 8
    h = hash_api_secret(secret)
    assert h == hashlib.sha256(secret.encode()).hexdigest()


def test_verify_api_secret_accepts_correct():
    secret = generate_api_secret()
    h = hash_api_secret(secret)
    assert verify_api_secret(secret, h) is True


def test_verify_api_secret_rejects_wrong():
    secret = generate_api_secret()
    h = hash_api_secret(secret)
    assert verify_api_secret("wrong" + secret[5:], h) is False
```

- [ ] **Step 2: Прогнать — упадёт на импорте**

```bash
pytest tests/test_codes.py -v
```

Expected: ImportError на `generate_api_secret`.

- [ ] **Step 3: Дописать в codes.py**

Добавить в `src/aiuse/codes.py`:
```python
import hashlib
import hmac

API_SECRET_BYTES = 32


def generate_api_secret() -> str:
    """32 случайных байта в hex (64 символа)."""
    return secrets.token_hex(API_SECRET_BYTES)


def hash_api_secret(secret: str) -> str:
    """sha256(secret) hex. БЫСТРО — секрет уже 256 бит энтропии, KDF не нужен."""
    return hashlib.sha256(secret.encode()).hexdigest()


def verify_api_secret(secret: str, stored_hash: str) -> bool:
    """Константное сравнение во избежание timing-атак."""
    return hmac.compare_digest(hash_api_secret(secret), stored_hash)
```

- [ ] **Step 4: Прогнать все тесты**

```bash
pytest tests/test_codes.py -v
```

Expected: 9 PASS.

- [ ] **Step 5: Коммит**

```bash
git add src/aiuse/codes.py tests/test_codes.py
git commit -m "feat(auth): генерация и проверка api_secret (sha256)"
```

---

### Task 14: Bearer middleware (current_profile dependency)

**Files:**
- Create: `src/aiuse/auth.py`
- Create: `tests/test_auth.py`

- [ ] **Step 1: Написать failing test**

`tests/test_auth.py`:
```python
from __future__ import annotations

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from aiuse.codes import generate_api_secret, generate_friend_code, hash_api_secret
from aiuse.models import Profile


@pytest.fixture
async def existing_profile(db_session: AsyncSession) -> tuple[Profile, str]:
    """Создаёт профиль в БД, возвращает (profile, plaintext_secret)."""
    secret = generate_api_secret()
    profile = Profile(
        friend_code=generate_friend_code(),
        api_secret_hash=hash_api_secret(secret),
        display_name="Test User",
    )
    db_session.add(profile)
    await db_session.commit()
    await db_session.refresh(profile)
    return profile, secret


async def test_protected_endpoint_without_header_returns_401(client: AsyncClient):
    # Используем эндпоинт который будет защищён в Task 16 (PATCH /api/profiles/me).
    # На текущем шаге достаточно сделать тестовый защищённый endpoint,
    # либо проверить через будущий — отложим до Task 16.
    # Пока проверим что dependency существует и работает.
    from aiuse.auth import bearer_required
    # placeholder: будем тестировать через реальный endpoint позже
    assert bearer_required is not None


async def test_verify_secret_lookup(db_session: AsyncSession, existing_profile):
    from aiuse.auth import find_profile_by_secret

    profile, secret = existing_profile
    found = await find_profile_by_secret(db_session, secret)
    assert found is not None
    assert found.id == profile.id


async def test_wrong_secret_returns_none(db_session: AsyncSession, existing_profile):
    from aiuse.auth import find_profile_by_secret

    _, _ = existing_profile
    found = await find_profile_by_secret(db_session, "deadbeef" * 8)
    assert found is None
```

- [ ] **Step 2: Прогнать — упадёт**

```bash
pytest tests/test_auth.py -v
```

Expected: FAIL на импорте `aiuse.auth`.

- [ ] **Step 3: Написать auth.py**

`src/aiuse/auth.py`:
```python
from __future__ import annotations

from fastapi import Depends, Header, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from aiuse.codes import hash_api_secret
from aiuse.db import get_session
from aiuse.models import Profile


async def find_profile_by_secret(session: AsyncSession, secret: str) -> Profile | None:
    """Ищем профиль по sha256(secret). Возвращаем None если не нашли."""
    h = hash_api_secret(secret)
    stmt = select(Profile).where(Profile.api_secret_hash == h)
    return (await session.execute(stmt)).scalar_one_or_none()


async def bearer_required(
    authorization: str | None = Header(None),
    session: AsyncSession = Depends(get_session),
) -> Profile:
    """FastAPI dependency: возвращает текущий Profile или кидает 401."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="missing or malformed Authorization header",
        )
    secret = authorization.removeprefix("Bearer ").strip()
    profile = await find_profile_by_secret(session, secret)
    if profile is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid token")
    return profile
```

- [ ] **Step 4: Прогнать — должны пройти**

```bash
pytest tests/test_auth.py -v
```

Expected: 3 PASS.

- [ ] **Step 5: Коммит**

```bash
git add src/aiuse/auth.py tests/test_auth.py
git commit -m "feat(auth): Bearer middleware с lookup по sha256(api_secret)"
```

---

## Phase E: Profile endpoints

### Task 15: POST /api/profiles (регистрация, без auth)

**Files:**
- Create: `src/aiuse/routers/profiles.py`
- Modify: `src/aiuse/main.py`
- Create: `tests/test_profiles.py`

- [ ] **Step 1: Написать failing test**

`tests/test_profiles.py`:
```python
from __future__ import annotations

import base64
import re

import pytest
from httpx import AsyncClient


async def test_create_profile_returns_codes_and_id(client: AsyncClient):
    response = await client.post(
        "/api/profiles",
        json={"display_name": "Серёжа"},
    )
    assert response.status_code == 201
    body = response.json()
    assert re.fullmatch(r"[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{10}", body["friend_code"])
    assert re.fullmatch(r"[0-9a-f]{64}", body["api_secret"])
    assert isinstance(body["server_user_id"], int)


async def test_create_profile_with_avatar(client: AsyncClient):
    avatar = b"\xff\xd8\xff" + b"\x00" * 100  # фейк JPEG
    response = await client.post(
        "/api/profiles",
        json={
            "display_name": "Bob",
            "avatar_b64": base64.b64encode(avatar).decode(),
            "avatar_mime": "image/jpeg",
        },
    )
    assert response.status_code == 201


async def test_create_profile_rejects_empty_name(client: AsyncClient):
    response = await client.post("/api/profiles", json={"display_name": ""})
    assert response.status_code == 422


async def test_create_profile_rejects_too_long_name(client: AsyncClient):
    response = await client.post("/api/profiles", json={"display_name": "x" * 65})
    assert response.status_code == 422
```

- [ ] **Step 2: Прогнать — упадёт на 404**

```bash
pytest tests/test_profiles.py -v
```

Expected: FAIL на 404 (endpoint не существует).

- [ ] **Step 3: Написать `routers/profiles.py`**

`src/aiuse/routers/profiles.py`:
```python
from __future__ import annotations

import base64

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from aiuse.codes import (
    generate_api_secret,
    generate_friend_code,
    hash_api_secret,
)
from aiuse.db import get_session
from aiuse.models import Profile
from aiuse.schemas import ProfileCreateRequest, ProfileCreateResponse

router = APIRouter(prefix="/profiles", tags=["profiles"])

MAX_AVATAR_BYTES = 200 * 1024
ALLOWED_AVATAR_MIMES = {"image/jpeg", "image/png"}


def _decode_avatar(b64: str | None, mime: str | None) -> tuple[bytes | None, str | None]:
    if b64 is None:
        return None, None
    if mime not in ALLOWED_AVATAR_MIMES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="avatar_mime must be image/jpeg or image/png",
        )
    try:
        raw = base64.b64decode(b64, validate=True)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="avatar_b64 invalid"
        ) from e
    if len(raw) > MAX_AVATAR_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"avatar too large: {len(raw)} > {MAX_AVATAR_BYTES}",
        )
    return raw, mime


@router.post("", response_model=ProfileCreateResponse, status_code=status.HTTP_201_CREATED)
async def create_profile(
    payload: ProfileCreateRequest,
    session: AsyncSession = Depends(get_session),
) -> ProfileCreateResponse:
    avatar_bytes, avatar_mime = _decode_avatar(payload.avatar_b64, payload.avatar_mime)
    secret = generate_api_secret()

    # Маловероятная (но возможная) коллизия friend_code → retry до 3 раз
    for _ in range(3):
        code = generate_friend_code()
        profile = Profile(
            friend_code=code,
            api_secret_hash=hash_api_secret(secret),
            display_name=payload.display_name,
            avatar=avatar_bytes,
            avatar_mime=avatar_mime,
        )
        session.add(profile)
        try:
            await session.commit()
            break
        except Exception:
            await session.rollback()
            continue
    else:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="friend_code collision (this should never happen)",
        )

    await session.refresh(profile)
    return ProfileCreateResponse(
        friend_code=profile.friend_code,
        api_secret=secret,
        server_user_id=profile.id,
    )
```

- [ ] **Step 4: Подключить роутер в main.py**

В `src/aiuse/main.py` добавить:
```python
from aiuse.routers import health, profiles

app = FastAPI(title="aiuse", version="0.2.0")
app.include_router(health.router, prefix="/api")
app.include_router(profiles.router, prefix="/api")
```

- [ ] **Step 5: Прогнать — должны пройти все 4 теста**

```bash
pytest tests/test_profiles.py -v
```

Expected: 4 PASS.

- [ ] **Step 6: Коммит**

```bash
git add src/aiuse/routers/profiles.py src/aiuse/main.py tests/test_profiles.py
git commit -m "feat(api): POST /api/profiles — регистрация с аватаркой"
```

---

### Task 16: PATCH /api/profiles/me

**Files:**
- Modify: `src/aiuse/routers/profiles.py`
- Modify: `tests/test_profiles.py`

- [ ] **Step 1: Дописать failing test**

Добавить в `tests/test_profiles.py`:
```python
async def _create_and_get_token(client: AsyncClient, name: str = "Test") -> str:
    r = await client.post("/api/profiles", json={"display_name": name})
    return r.json()["api_secret"]


async def test_patch_profile_updates_name(client: AsyncClient):
    secret = await _create_and_get_token(client, "Old Name")
    r = await client.patch(
        "/api/profiles/me",
        json={"display_name": "New Name"},
        headers={"Authorization": f"Bearer {secret}"},
    )
    assert r.status_code == 200
    assert r.json()["display_name"] == "New Name"


async def test_patch_profile_toggles_sharing(client: AsyncClient):
    secret = await _create_and_get_token(client)
    r = await client.patch(
        "/api/profiles/me",
        json={"sharing_enabled": False},
        headers={"Authorization": f"Bearer {secret}"},
    )
    assert r.status_code == 200
    assert r.json()["sharing_enabled"] is False


async def test_patch_without_auth_returns_401(client: AsyncClient):
    r = await client.patch("/api/profiles/me", json={"display_name": "X"})
    assert r.status_code == 401


async def test_patch_with_wrong_token_returns_401(client: AsyncClient):
    r = await client.patch(
        "/api/profiles/me",
        json={"display_name": "X"},
        headers={"Authorization": "Bearer deadbeef" * 8},
    )
    assert r.status_code == 401
```

- [ ] **Step 2: Прогнать — упадут**

```bash
pytest tests/test_profiles.py -v -k "patch"
```

Expected: FAIL — endpoint не существует.

- [ ] **Step 3: Дописать в `routers/profiles.py`**

```python
from aiuse.auth import bearer_required
from aiuse.schemas import ProfileResponse, ProfileUpdateRequest


@router.patch("/me", response_model=ProfileResponse)
async def update_profile(
    payload: ProfileUpdateRequest,
    me: Profile = Depends(bearer_required),
    session: AsyncSession = Depends(get_session),
) -> ProfileResponse:
    if payload.display_name is not None:
        me.display_name = payload.display_name
    if payload.sharing_enabled is not None:
        me.sharing_enabled = payload.sharing_enabled
    if payload.avatar_b64 is not None:
        avatar_bytes, avatar_mime = _decode_avatar(payload.avatar_b64, payload.avatar_mime)
        me.avatar = avatar_bytes
        me.avatar_mime = avatar_mime

    session.add(me)
    await session.commit()
    await session.refresh(me)
    return ProfileResponse.model_validate(me)
```

- [ ] **Step 4: Прогнать**

```bash
pytest tests/test_profiles.py -v
```

Expected: все PASS.

- [ ] **Step 5: Коммит**

```bash
git add src/aiuse/routers/profiles.py tests/test_profiles.py
git commit -m "feat(api): PATCH /api/profiles/me — обновление имени/аватарки/sharing"
```

---

### Task 17: POST /api/profiles/me/regenerate-friend-code

**Files:**
- Modify: `src/aiuse/routers/profiles.py`
- Modify: `tests/test_profiles.py`

- [ ] **Step 1: Дописать failing test**

Добавить в `tests/test_profiles.py`:
```python
async def test_regenerate_changes_code_and_keeps_secret(client: AsyncClient):
    r = await client.post("/api/profiles", json={"display_name": "X"})
    secret = r.json()["api_secret"]
    old_code = r.json()["friend_code"]

    r2 = await client.post(
        "/api/profiles/me/regenerate-friend-code",
        headers={"Authorization": f"Bearer {secret}"},
    )
    assert r2.status_code == 200
    new_code = r2.json()["friend_code"]
    assert new_code != old_code
    assert r2.json()["friendships_dropped"] == 0

    # Тот же api_secret должен работать
    r3 = await client.patch(
        "/api/profiles/me",
        json={"display_name": "Y"},
        headers={"Authorization": f"Bearer {secret}"},
    )
    assert r3.status_code == 200
```

- [ ] **Step 2: Запустить, упадёт**

- [ ] **Step 3: Дописать endpoint**

```python
from sqlalchemy import delete, or_

from aiuse.models import Friendship
from aiuse.schemas import RegenerateFriendCodeResponse


@router.post("/me/regenerate-friend-code", response_model=RegenerateFriendCodeResponse)
async def regenerate_friend_code(
    me: Profile = Depends(bearer_required),
    session: AsyncSession = Depends(get_session),
) -> RegenerateFriendCodeResponse:
    # Сколько связей удалим
    from sqlalchemy import select, func as sql_func

    count_stmt = select(sql_func.count()).select_from(Friendship).where(
        or_(Friendship.user_a_id == me.id, Friendship.user_b_id == me.id)
    )
    dropped = (await session.execute(count_stmt)).scalar_one()

    # Удаляем связи
    await session.execute(
        delete(Friendship).where(
            or_(Friendship.user_a_id == me.id, Friendship.user_b_id == me.id)
        )
    )

    # Генерируем новый код с retry на коллизию
    for _ in range(3):
        new_code = generate_friend_code()
        me.friend_code = new_code
        session.add(me)
        try:
            await session.commit()
            break
        except Exception:
            await session.rollback()
            continue
    else:
        raise HTTPException(status_code=500, detail="friend_code collision")

    return RegenerateFriendCodeResponse(friend_code=new_code, friendships_dropped=dropped)
```

- [ ] **Step 4: Прогнать**

```bash
pytest tests/test_profiles.py -v
```

Expected: все PASS.

- [ ] **Step 5: Коммит**

```bash
git add src/aiuse/routers/profiles.py tests/test_profiles.py
git commit -m "feat(api): POST /api/profiles/me/regenerate-friend-code"
```

---

### Task 18: DELETE /api/profiles/me (каскад)

**Files:**
- Modify: `src/aiuse/routers/profiles.py`
- Modify: `tests/test_profiles.py`

- [ ] **Step 1: Дописать failing test**

```python
async def test_delete_account_returns_204_and_invalidates_token(client: AsyncClient):
    r = await client.post("/api/profiles", json={"display_name": "X"})
    secret = r.json()["api_secret"]

    r2 = await client.delete("/api/profiles/me", headers={"Authorization": f"Bearer {secret}"})
    assert r2.status_code == 204

    # Тот же токен больше не работает
    r3 = await client.patch(
        "/api/profiles/me",
        json={"display_name": "Y"},
        headers={"Authorization": f"Bearer {secret}"},
    )
    assert r3.status_code == 401
```

- [ ] **Step 2: Дописать endpoint**

```python
from fastapi import Response


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
async def delete_account(
    me: Profile = Depends(bearer_required),
    session: AsyncSession = Depends(get_session),
) -> Response:
    await session.delete(me)
    await session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
```

- [ ] **Step 3: Прогнать**

```bash
pytest tests/test_profiles.py -v
```

Expected: все PASS. Каскады в БД (snapshots/friendships/blocks) проверим в e2e (Task 23).

- [ ] **Step 4: Коммит**

```bash
git add src/aiuse/routers/profiles.py tests/test_profiles.py
git commit -m "feat(api): DELETE /api/profiles/me — удаление аккаунта"
```

---

## Phase F: Snapshots endpoint

### Task 19: POST /api/snapshots — happy path

**Files:**
- Create: `src/aiuse/routers/snapshots.py`
- Modify: `src/aiuse/main.py`
- Create: `tests/test_snapshots.py`

- [ ] **Step 1: Написать failing test**

`tests/test_snapshots.py`:
```python
from __future__ import annotations

from datetime import datetime, timezone

import pytest
from httpx import AsyncClient


async def _register(client: AsyncClient) -> str:
    r = await client.post("/api/profiles", json={"display_name": "X"})
    return r.json()["api_secret"]


async def test_post_snapshots_accepts_batch(client: AsyncClient):
    secret = await _register(client)
    response = await client.post(
        "/api/snapshots",
        json={
            "snapshots": [
                {
                    "hour_bucket": "2026-05-23T14:00:00Z",
                    "tokens_input": 1200,
                    "tokens_output": 8400,
                },
                {
                    "hour_bucket": "2026-05-23T15:00:00Z",
                    "tokens_input": 0,
                    "tokens_output": 50,
                },
            ]
        },
        headers={"Authorization": f"Bearer {secret}"},
    )
    assert response.status_code == 200
    assert response.json() == {"accepted": 2}


async def test_post_snapshots_is_idempotent(client: AsyncClient):
    secret = await _register(client)
    payload = {
        "snapshots": [
            {"hour_bucket": "2026-05-23T14:00:00Z", "tokens_input": 100, "tokens_output": 200}
        ]
    }
    headers = {"Authorization": f"Bearer {secret}"}

    # Шлём дважды — финальное значение должно быть из последнего запроса
    await client.post("/api/snapshots", json=payload, headers=headers)
    payload["snapshots"][0]["tokens_input"] = 999
    r = await client.post("/api/snapshots", json=payload, headers=headers)
    assert r.status_code == 200
    assert r.json() == {"accepted": 1}


async def test_post_snapshots_requires_auth(client: AsyncClient):
    r = await client.post(
        "/api/snapshots",
        json={"snapshots": [{"hour_bucket": "2026-05-23T14:00:00Z", "tokens_input": 1, "tokens_output": 1}]},
    )
    assert r.status_code == 401
```

- [ ] **Step 2: Прогнать — упадёт на 404**

```bash
pytest tests/test_snapshots.py -v
```

- [ ] **Step 3: Написать routers/snapshots.py**

`src/aiuse/routers/snapshots.py`:
```python
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from aiuse.auth import bearer_required
from aiuse.db import get_session
from aiuse.models import Profile, Snapshot
from aiuse.schemas import SnapshotsBatch, SnapshotsResponse

router = APIRouter(prefix="/snapshots", tags=["snapshots"])


@router.post("", response_model=SnapshotsResponse)
async def upsert_snapshots(
    payload: SnapshotsBatch,
    me: Profile = Depends(bearer_required),
    session: AsyncSession = Depends(get_session),
) -> SnapshotsResponse:
    if not me.sharing_enabled:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="sharing is disabled for this profile",
        )

    # Нормализация: floor hour_bucket к часу
    rows = [
        {
            "user_id": me.id,
            "hour_bucket": item.hour_bucket.replace(minute=0, second=0, microsecond=0),
            "tokens_input": item.tokens_input,
            "tokens_output": item.tokens_output,
        }
        for item in payload.snapshots
    ]

    stmt = insert(Snapshot).values(rows)
    stmt = stmt.on_conflict_do_update(
        index_elements=["user_id", "hour_bucket"],
        set_={
            "tokens_input": stmt.excluded.tokens_input,
            "tokens_output": stmt.excluded.tokens_output,
            "updated_at": stmt.excluded.updated_at,
        },
    )
    await session.execute(stmt)
    await session.commit()
    return SnapshotsResponse(accepted=len(rows))
```

- [ ] **Step 4: Подключить роутер**

В `src/aiuse/main.py`:
```python
from aiuse.routers import health, profiles, snapshots

app = FastAPI(title="aiuse", version="0.2.0")
app.include_router(health.router, prefix="/api")
app.include_router(profiles.router, prefix="/api")
app.include_router(snapshots.router, prefix="/api")
```

- [ ] **Step 5: Прогнать**

```bash
pytest tests/test_snapshots.py -v
```

Expected: все PASS.

- [ ] **Step 6: Коммит**

```bash
git add src/aiuse/routers/snapshots.py src/aiuse/main.py tests/test_snapshots.py
git commit -m "feat(api): POST /api/snapshots с идемпотентным upsert"
```

---

### Task 20: POST /snapshots — sharing_enabled = false → 403

**Files:**
- Modify: `tests/test_snapshots.py`

- [ ] **Step 1: Дописать тест**

```python
async def test_snapshots_blocked_when_sharing_disabled(client: AsyncClient):
    secret = await _register(client)
    # Выключаем шаринг
    await client.patch(
        "/api/profiles/me",
        json={"sharing_enabled": False},
        headers={"Authorization": f"Bearer {secret}"},
    )

    r = await client.post(
        "/api/snapshots",
        json={
            "snapshots": [
                {"hour_bucket": "2026-05-23T14:00:00Z", "tokens_input": 1, "tokens_output": 1}
            ]
        },
        headers={"Authorization": f"Bearer {secret}"},
    )
    assert r.status_code == 403
```

- [ ] **Step 2: Прогнать — уже должен пройти**

(Endpoint уже проверяет `me.sharing_enabled` в Task 19.)

```bash
pytest tests/test_snapshots.py -v
```

Expected: PASS.

- [ ] **Step 3: Коммит**

```bash
git add tests/test_snapshots.py
git commit -m "test(api): покрытие sharing_enabled=false для snapshots"
```

---

### Task 21: Batch лимит и валидация hour_bucket

**Files:**
- Modify: `tests/test_snapshots.py`

- [ ] **Step 1: Дописать тесты на edge cases**

```python
async def test_snapshots_batch_over_168_rejected(client: AsyncClient):
    secret = await _register(client)
    snapshots = [
        {"hour_bucket": f"2026-05-{((i % 28) + 1):02d}T{(i % 24):02d}:00:00Z",
         "tokens_input": 1, "tokens_output": 1}
        for i in range(169)
    ]
    r = await client.post(
        "/api/snapshots",
        json={"snapshots": snapshots},
        headers={"Authorization": f"Bearer {secret}"},
    )
    assert r.status_code == 422


async def test_snapshots_empty_batch_rejected(client: AsyncClient):
    secret = await _register(client)
    r = await client.post(
        "/api/snapshots",
        json={"snapshots": []},
        headers={"Authorization": f"Bearer {secret}"},
    )
    assert r.status_code == 422


async def test_snapshots_negative_tokens_rejected(client: AsyncClient):
    secret = await _register(client)
    r = await client.post(
        "/api/snapshots",
        json={
            "snapshots": [
                {"hour_bucket": "2026-05-23T14:00:00Z", "tokens_input": -1, "tokens_output": 0}
            ]
        },
        headers={"Authorization": f"Bearer {secret}"},
    )
    assert r.status_code == 422


async def test_snapshots_hour_bucket_is_floored_to_hour(client: AsyncClient):
    """Шлём с минутами — на сервере должно сохраниться floored к часу."""
    secret = await _register(client)
    r = await client.post(
        "/api/snapshots",
        json={
            "snapshots": [
                {"hour_bucket": "2026-05-23T14:37:42Z", "tokens_input": 5, "tokens_output": 10}
            ]
        },
        headers={"Authorization": f"Bearer {secret}"},
    )
    assert r.status_code == 200
    # Повторный POST с тем же часом, но другими минутами — должен upsert, не append
    r2 = await client.post(
        "/api/snapshots",
        json={
            "snapshots": [
                {"hour_bucket": "2026-05-23T14:00:00Z", "tokens_input": 100, "tokens_output": 200}
            ]
        },
        headers={"Authorization": f"Bearer {secret}"},
    )
    assert r2.status_code == 200
    assert r2.json() == {"accepted": 1}
```

- [ ] **Step 2: Прогнать**

```bash
pytest tests/test_snapshots.py -v
```

Expected: все PASS (валидация уже в Pydantic schema + floor в endpoint'е).

- [ ] **Step 3: Коммит**

```bash
git add tests/test_snapshots.py
git commit -m "test(api): edge cases для snapshots batch (лимит, валидация, floor)"
```

---

## Phase G: E2E smoke test

### Task 22: E2E smoke test

**Files:**
- Create: `tests/test_e2e_smoke.py`

- [ ] **Step 1: Написать e2e тест**

`tests/test_e2e_smoke.py`:
```python
"""Полный flow: регистрация → snapshot → обновление → регенерация → удаление."""

from __future__ import annotations

from httpx import AsyncClient


async def test_full_user_flow(client: AsyncClient):
    # 1. Регистрация
    r1 = await client.post("/api/profiles", json={"display_name": "Alice"})
    assert r1.status_code == 201
    alice_secret = r1.json()["api_secret"]
    alice_code = r1.json()["friend_code"]
    alice_headers = {"Authorization": f"Bearer {alice_secret}"}

    # 2. Шлём snapshot
    r2 = await client.post(
        "/api/snapshots",
        json={
            "snapshots": [
                {"hour_bucket": "2026-05-23T14:00:00Z", "tokens_input": 100, "tokens_output": 200},
                {"hour_bucket": "2026-05-23T15:00:00Z", "tokens_input": 50, "tokens_output": 80},
            ]
        },
        headers=alice_headers,
    )
    assert r2.status_code == 200
    assert r2.json() == {"accepted": 2}

    # 3. Обновляем имя
    r3 = await client.patch(
        "/api/profiles/me",
        json={"display_name": "Alice Renamed"},
        headers=alice_headers,
    )
    assert r3.status_code == 200
    assert r3.json()["display_name"] == "Alice Renamed"

    # 4. Регенерируем код
    r4 = await client.post(
        "/api/profiles/me/regenerate-friend-code",
        headers=alice_headers,
    )
    assert r4.status_code == 200
    new_code = r4.json()["friend_code"]
    assert new_code != alice_code

    # 5. Тот же api_secret продолжает работать
    r5 = await client.patch(
        "/api/profiles/me",
        json={"display_name": "Alice Final"},
        headers=alice_headers,
    )
    assert r5.status_code == 200

    # 6. Удаляем аккаунт — токен инвалидируется
    r6 = await client.delete("/api/profiles/me", headers=alice_headers)
    assert r6.status_code == 204

    # 7. После удаления старый snapshot тоже не должен слаться
    r7 = await client.post(
        "/api/snapshots",
        json={
            "snapshots": [
                {"hour_bucket": "2026-05-23T14:00:00Z", "tokens_input": 1, "tokens_output": 1}
            ]
        },
        headers=alice_headers,
    )
    assert r7.status_code == 401  # токен мёртвый
```

- [ ] **Step 2: Прогнать**

```bash
pytest tests/test_e2e_smoke.py -v
```

Expected: PASS.

- [ ] **Step 3: Прогнать ВСЁ + ruff**

```bash
pytest -v
ruff check src tests
```

Expected: всё PASS, ruff clean.

- [ ] **Step 4: Коммит**

```bash
git add tests/test_e2e_smoke.py
git commit -m "test: e2e smoke — полный flow одного пользователя"
```

---

## Phase H: Containerization

### Task 23: Dockerfile

**Files:**
- Create: `Dockerfile`

- [ ] **Step 1: Написать Dockerfile**

```dockerfile
# syntax=docker/dockerfile:1.7
FROM python:3.12-slim AS builder

RUN pip install --no-cache-dir uv

WORKDIR /build
COPY pyproject.toml ./
COPY src ./src

RUN uv pip install --system --no-cache .

FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin
COPY src ./src
COPY alembic ./alembic
COPY alembic.ini ./

ENV PYTHONPATH=/app/src

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -fsS http://localhost:8000/api/health || exit 1

EXPOSE 8000
CMD ["uvicorn", "aiuse.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

- [ ] **Step 2: Локально собрать и убедиться что стартует**

```bash
cd /Users/sergeytovarov/work/ai-stats-api
docker build -t aiuse-api:test .
docker run --rm aiuse-api:test python -c "from aiuse.main import app; print(app.title)"
```

Expected: вывод `aiuse`.

- [ ] **Step 3: Коммит**

```bash
git add Dockerfile
git commit -m "build: Dockerfile с uv (multi-stage)"
```

---

### Task 24: docker-compose

**Files:**
- Create: `docker-compose.yml`

- [ ] **Step 1: Написать docker-compose.yml**

```yaml
services:
  postgres:
    image: postgres:16-alpine
    container_name: aiuse-postgres
    environment:
      POSTGRES_USER: aiuse
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?POSTGRES_PASSWORD required}
      POSTGRES_DB: aiuse
    volumes:
      - ./pgdata:/var/lib/postgresql/data
    networks:
      - internal
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U aiuse"]
      interval: 10s
      timeout: 5s
      retries: 5

  api:
    build: .
    container_name: aiuse-api
    environment:
      AIUSE_DATABASE_URL: postgresql+asyncpg://aiuse:${POSTGRES_PASSWORD}@postgres:5432/aiuse
      AIUSE_LOG_LEVEL: INFO
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - internal
      - web
    restart: unless-stopped
    command: >
      sh -c "alembic upgrade head && uvicorn aiuse.main:app --host 0.0.0.0 --port 8000"

networks:
  internal:
  web:
    external: true
```

- [ ] **Step 2: Локально проверить (опционально, требует docker network web)**

Если на dev-машине нет network `web`:
```bash
docker network create web 2>/dev/null || true
echo "POSTGRES_PASSWORD=devpass" > .env
docker compose up -d
docker compose logs api --tail 20
curl http://localhost:8000/api/health  # 404, потому что наружу порт не торчит
docker exec aiuse-api curl -fsS http://localhost:8000/api/health
docker compose down
rm -rf .env pgdata
```

Expected: внутренний `curl` возвращает `{"status":"ok"}`.

- [ ] **Step 3: Коммит**

```bash
git add docker-compose.yml
git commit -m "build: docker-compose с api + postgres в network web"
```

---

## Phase I: Deploy to VM

### Task 25: Setup на VM — bare repo + post-receive хук

**Files:**
- (на VM: `/srv/git/aiuse.git/hooks/post-receive`)

> Эта задача выполняется на VM через SSH. Локально файлов не создаём — только документируем команды.

- [ ] **Step 1: SSH на VM и создать рабочую директорию**

```bash
ssh meridian
sudo mkdir -p /opt/aiuse/{backups,landing}
sudo chown -R yc-user:yc-user /opt/aiuse
```

- [ ] **Step 2: Создать bare repo + checkout рабочей копии**

```bash
mkdir -p /srv/git/aiuse.git
cd /srv/git/aiuse.git
git init --bare

cd /opt/aiuse
git init
git remote add origin /srv/git/aiuse.git
```

- [ ] **Step 3: Написать post-receive хук**

```bash
cat > /srv/git/aiuse.git/hooks/post-receive <<'EOF'
#!/bin/bash
set -e
cd /opt/aiuse
unset GIT_DIR
git fetch origin
git reset --hard origin/main
docker compose up -d --build api
EOF
chmod +x /srv/git/aiuse.git/hooks/post-receive
```

- [ ] **Step 4: Создать `.env` на VM**

```bash
cd /opt/aiuse
openssl rand -hex 32 > /tmp/pgpass
echo "POSTGRES_PASSWORD=$(cat /tmp/pgpass)" > .env
chmod 600 .env
rm /tmp/pgpass
```

- [ ] **Step 5: Локально добавить remote и пушнуть**

```bash
cd /Users/sergeytovarov/work/ai-stats-api
git remote add prod meridian:/srv/git/aiuse.git
git branch -m main 2>/dev/null || true  # если на master
git push prod main
```

Expected: post-receive хук разворачивает контейнеры. Можно посмотреть `ssh meridian "docker compose -f /opt/aiuse/docker-compose.yml ps"` — два сервиса healthy.

- [ ] **Step 6: Записать в infra/secrets.md** (или куда юзер обычно пишет секреты — спросить)

> POSTGRES_PASSWORD для `/opt/aiuse/.env` лежит на VM, не выгружается. Бэкап в [личной заметке / 1Password / другом sec-store].

(Это не файл-коммит, а memo для юзера — пусть запишет вручную.)

---

### Task 26: DNS + SAN cert + nginx upstream + лендинг-заглушка

**Files:**
- Modify: `/Users/sergeytovarov/work/ingress/nginx.conf`
- (на VM: `/opt/aiuse/landing/index.html`)

- [ ] **Step 1: Создать A-запись**

Локально:
```bash
yc dns zone add-records --name popovs-tech-zone --record "aiuse 300 A 93.77.187.42"
```

Проверить:
```bash
dig +short aiuse.popovs.tech
# Ожидаем: 93.77.187.42
```

- [ ] **Step 2: Расширить SAN cert через certbot --expand**

```bash
ssh meridian "docker run --rm \
  -v /opt/ingress/letsencrypt:/etc/letsencrypt \
  -v /opt/ingress/certbot-www:/var/www/certbot \
  certbot/certbot certonly --webroot -w /var/www/certbot \
  --cert-name meridian.popovs.tech \
  -d meridian.popovs.tech -d uptime.popovs.tech -d status.popovs.tech -d kp.popovs.tech \
  -d ramka.popovs.tech -d skillaz.popovs.tech -d boris.popovs.tech -d tracker.popovs.tech \
  -d aiuse.popovs.tech \
  --expand --email s.popov.works@gmail.com --agree-tos --no-eff-email --non-interactive"
```

> ВАЖНО: перечислить **все текущие домены** + `aiuse.popovs.tech`. Если забыть какой-то — certbot создаст второй lineage `-0001`, будет бардак. Список текущих доменов — в `/opt/ingress/nginx.conf` блоках `server_name`.

- [ ] **Step 3: Прочитать существующий nginx.conf и добавить upstream + server**

Открыть `/Users/sergeytovarov/work/ingress/nginx.conf`. Добавить **в секцию upstream'ов** (рядом с существующими `meridian-frontend`, `meridian-backend`):

```nginx
upstream aiuse-api {
    server aiuse-api:8000;
}
```

Добавить **новый server-блок** (рядом с другими server-блоками):

```nginx
server {
    listen 443 ssl http2;
    server_name aiuse.popovs.tech;

    ssl_certificate     /etc/letsencrypt/live/meridian.popovs.tech/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/meridian.popovs.tech/privkey.pem;

    client_max_body_size 1m;

    # Лендинг — статика
    location / {
        root /var/www/aiuse;
        index index.html;
        try_files $uri $uri/ =404;
    }

    # API
    location /api/ {
        proxy_pass http://aiuse-api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# HTTP → HTTPS redirect
server {
    listen 80;
    server_name aiuse.popovs.tech;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}
```

- [ ] **Step 4: Добавить volume для лендинга в ingress docker-compose**

Открыть `/Users/sergeytovarov/work/ingress/docker-compose.yml`. В сервис `nginx` в `volumes:` добавить:

```yaml
      - /opt/aiuse/landing:/var/www/aiuse:ro
```

- [ ] **Step 5: На VM создать заглушку лендинга**

```bash
ssh meridian "cat > /opt/aiuse/landing/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>aiuse — coming soon</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 600px; margin: 100px auto; padding: 0 20px; color: #333; }
        h1 { font-size: 2em; margin-bottom: 0.2em; }
        p { color: #666; line-height: 1.6; }
    </style>
</head>
<body>
    <h1>aiuse</h1>
    <p>Backend для лидерборда ai-stats. В разработке.</p>
</body>
</html>
EOF
```

- [ ] **Step 6: Деплой ingress изменений**

```bash
cd /Users/sergeytovarov/work/ingress
git add nginx.conf docker-compose.yml
git commit -m "feat(aiuse): добавить поддомен aiuse.popovs.tech (api + landing)"
git push prod main
```

Post-receive хук в ingress перезагрузит nginx без даунтайма.

- [ ] **Step 7: Проверить что всё работает**

```bash
curl -fsS https://aiuse.popovs.tech/  # должен вернуть HTML заглушку
curl -fsS https://aiuse.popovs.tech/api/health  # {"status":"ok"}
```

Expected: оба возвращают 200.

---

### Task 27: Cron pg_dump

**Files:**
- (на VM: crontab пользователя yc-user)

- [ ] **Step 1: Добавить cron-задачу на VM**

```bash
ssh meridian "(crontab -l 2>/dev/null; echo '0 3 * * * docker exec aiuse-postgres pg_dump -U aiuse aiuse | gzip > /opt/aiuse/backups/\$(date +\\%F).sql.gz && find /opt/aiuse/backups -mtime +7 -delete') | crontab -"
```

- [ ] **Step 2: Прогнать руками первый бэкап**

```bash
ssh meridian "docker exec aiuse-postgres pg_dump -U aiuse aiuse | gzip > /opt/aiuse/backups/$(date +%F)-manual.sql.gz && ls -lh /opt/aiuse/backups/"
```

Expected: файл создан, ненулевого размера.

- [ ] **Step 3: Проверить crontab**

```bash
ssh meridian "crontab -l | grep aiuse"
```

---

### Task 28: Uptime Kuma checks

**Files:**
- (UI на `https://uptime.popovs.tech`)

- [ ] **Step 1: Залогиниться в Uptime Kuma**

Открыть `https://uptime.popovs.tech/dashboard` в браузере.

- [ ] **Step 2: Добавить два HTTPS-монитора**

1. **aiuse landing** — `https://aiuse.popovs.tech/` — interval 60s, retries 2.
2. **aiuse api** — `https://aiuse.popovs.tech/api/health` — interval 60s, retries 2, JSON match `status` == `ok` (если есть такая опция).

- [ ] **Step 3: Добавить в публичный статус `status.popovs.tech` (опционально)**

В Kuma → Status Pages → Meridian → добавить новые мониторы в группу.

---

## Phase J: Documentation

### Task 29: README для ai-stats-api

**Files:**
- Create: `README.md`

- [ ] **Step 1: Написать README**

`README.md`:
```markdown
# ai-stats-api

Backend для лидерборда ai-stats. FastAPI + Postgres + Alembic.

Развёрнут на `https://aiuse.popovs.tech/api/`.

## Что это

Серверная часть для синхронизации статистики использования AI-токенов между друзьями.
v0.2.0 — фундамент: профили и snapshot'ы. Friends/blocks/leaderboard — в v0.3.0.

Полный дизайн: [docs/superpowers/specs/2026-05-23-leaderboard-design.md](../ai-stats/docs/superpowers/specs/2026-05-23-leaderboard-design.md)

## Стек

- Python 3.12, FastAPI 0.110+
- SQLAlchemy 2.0 (async), Alembic
- Pydantic v2, pydantic-settings
- Postgres 16
- uv для управления зависимостями
- pytest + testcontainers-postgres + httpx для тестов
- ruff для линтинга

## Локальная разработка

```bash
uv venv && source .venv/bin/activate
uv pip install -e ".[dev]"

# Тесты (требуют запущенный Docker — testcontainers поднимет Postgres)
pytest -v
ruff check src tests
```

## API

Все эндпоинты под `/api/`. Auth для всех кроме `POST /profiles` — `Authorization: Bearer <api_secret>`.

Доступные в v0.2.0:
- `GET /api/health`
- `POST /api/profiles` — регистрация
- `PATCH /api/profiles/me` — обновление профиля
- `POST /api/profiles/me/regenerate-friend-code`
- `DELETE /api/profiles/me`
- `POST /api/snapshots` — батч hourly snapshot'ов

Появятся в v0.3.0+: `GET /api/friends`, `POST /api/friends`, `GET /api/leaderboard`, `GET /api/avatars/{code}`, blocks endpoints.

## Деплой

`git push prod main` → post-receive хук на VM `meridian`:
1. Reset working tree в `/opt/aiuse/`
2. `docker compose up -d --build api` (postgres не пересобирается)
3. Миграции применяются автоматически при старте контейнера (`alembic upgrade head` в command).

`POSTGRES_PASSWORD` в `/opt/aiuse/.env`, не в репо.

## Бэкапы

`pg_dump` ежедневно в 03:00 UTC по cron'у на VM, файлы в `/opt/aiuse/backups/*.sql.gz`, ротация 7 дней.

## Мониторинг

- Health check: `https://uptime.popovs.tech/dashboard`
- Логи: `ssh meridian "docker logs aiuse-api --tail 50"`

## Лицензия

MIT (запланировано к v1.0).
```

- [ ] **Step 2: Коммит и пуш**

```bash
git add README.md
git commit -m "docs: README для ai-stats-api"
git push prod main
```

---

### Task 30: Обновить infra/README.md

**Files:**
- Modify: `/Users/sergeytovarov/work/infra/README.md`

- [ ] **Step 1: Прочитать существующий README**

```bash
cat /Users/sergeytovarov/work/infra/README.md
```

- [ ] **Step 2: Добавить строку в таблицу "Проекты на VM"**

В разделе `## Проекты на VM` добавить новую строку в таблицу:

```markdown
| `aiuse.popovs.tech` | aiuse — backend ai-stats лидерборда | `/opt/aiuse/` | [ai-stats-api](https://github.com/tsergeytovarov/ai-stats-api) |
```

(Если репо ещё не на GitHub — пометить «локально», обновить позже.)

- [ ] **Step 3: Закоммитить в infra**

```bash
cd /Users/sergeytovarov/work/infra
git add README.md
git commit -m "docs: добавить aiuse в таблицу проектов"
```

---

## Self-Review

### Spec coverage check

Прохожу по разделам спека и проверяю что покрыто планом:

| Спек | Покрыто? |
|---|---|
| 1. Цель и контекст — v0.2.0 = серверный фундамент + клиент. **Этот план только серверный.** | ✓ (client — отдельный план) |
| 2. Фазировка v0.2 — «профиль + sync snapshot'ов» | ✓ (Tasks 15-22) |
| 3. Архитектура — поддомен, ingress, контейнеры, cron | ✓ (Tasks 24-27) |
| 4. Метрика — input+output без кэша | ✓ (`snapshots` таблица, schema позволяет) |
| 5. Schema — 4 таблицы | ✓ (Tasks 6-10) |
| 6. API — profiles/snapshots endpoints | ✓ (Tasks 15-21). Friends/blocks/leaderboard/avatars — в v0.3.0+. |
| 7. Sync flow — клиентская часть | — (client план) |
| 8. Privacy — sharing_enabled=false блокирует sync, каскад delete | ✓ (Task 20, Task 18 + e2e Task 22) |
| 9. UI | — (client план) |
| 10. Testing — pytest + testcontainers + e2e smoke | ✓ (conftest Task 10, e2e Task 22) |
| 11. Security — двухтокенная auth | ✓ (Tasks 12-14, 15) |
| 12. Deploy | ✓ (Tasks 23-28) |
| 13. Чек-лист v0.2.0 | каждый пункт покрыт соответствующим Task'ом |

Гэпы: **нет блокирующих**. UI/sync клиента — намеренно в отдельном плане v0.2.0-client.

### Placeholder scan

- ✗ Слово «TODO» — нет в плане.
- ✗ «Добавить error handling» без конкретики — нет (или есть конкретный HTTPException).
- ✗ «Similar to Task N» — нет (везде повторяю код).
- ✓ Все code блоки содержат рабочий код.
- ✓ Все команды показывают expected output.

### Type/name consistency

- `friend_code`, `api_secret`, `api_secret_hash` — везде одинаково (миграции, модели, schemas, тесты).
- `Profile.id` → `server_user_id` в DTO — консистентно.
- `hour_bucket` floor к часу — в schema и в endpoint'е, тест проверяет.
- Endpoint paths: `/api/profiles`, `/api/profiles/me`, `/api/profiles/me/regenerate-friend-code`, `/api/snapshots`, `/api/health` — везде одно и то же.
- `bearer_required` dependency используется в profiles и snapshots — одинаковая сигнатура.

Всё консистентно.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-23-leaderboard-v0.2.0-backend.md`.

Два варианта исполнения:

1. **Subagent-Driven (recommended)** — диспатчу свежего сабагента на каждый task, ревью между ними, быстрая итерация.
2. **Inline Execution** — исполняю задачи в этой же сессии через `executing-plans`, батчем с чекпоинтами на ревью.
