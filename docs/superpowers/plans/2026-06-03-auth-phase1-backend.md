# Авторизация — Фаза 1, Backend (ai-stats-api) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Дать серверу `ai-stats-api` настоящую идентичность через OAuth-брокер (GitHub-first), привязку устройств (multi-device) и публичный глобальный лидерборд — не сломав существующих клиентов.

**Architecture:** Профиль расщепляется на `profiles` + `auth_identities` (внешние логины) + `device_tokens` (по токену на устройство). Сервер брокерит OAuth: client secret провайдера только на сервере, клиент получает свой `device_token` и (для GitHub) data-токен через one-time `auth_code`. Снапшоты получают `device_id` и суммируются по устройствам. Глобальный лидерборд — публичный read-эндпоинт по профилям с `global_opt_in`.

**Tech Stack:** Python 3.12, FastAPI 0.110+, SQLAlchemy 2.0 async, asyncpg, Alembic, Pydantic v2, httpx (новая runtime-зависимость), pytest + testcontainers.

**Репозиторий реализации:** `../ai-stats-api/` (отдельный от Swift-клиента). Все пути ниже — относительно корня `ai-stats-api`.

**Конвенции репо (соблюдать):**
- Модели — `src/aiuse/models.py`, `Mapped`/`mapped_column`, наследник `Base`.
- Миграции — `alembic/versions/NNN_name.py`, строковый `revision`, последовательная нумерация (текущая последняя — `004`).
- Тесты — `tests/test_*.py`, фикстуры `client` (httpx ASGI) и `db_session` из `tests/conftest.py`. `asyncio_mode = auto`.
- Запуск тестов: `cd ../ai-stats-api && uv run pytest -v` (или `pytest -v` в активном venv).
- Линт: `ruff check . && ruff format .`.

---

## File Structure

| Файл | Создаём/меняем | Ответственность |
|---|---|---|
| `pyproject.toml` | Modify | Добавить `httpx` в runtime-зависимости |
| `src/aiuse/config.py` | Modify | Настройки OAuth (GitHub client id/secret, base url, callback scheme, TTL сессии) |
| `src/aiuse/models.py` | Modify | `+global_opt_in`, новые модели `DeviceToken`, `AuthIdentity`, `AuthSession`, `+device_id` в `Snapshot` |
| `src/aiuse/codes.py` | Modify | Генерация/хэш device-токена и auth-кода (переиспользуем sha256) |
| `src/aiuse/auth.py` | Modify | Резолв `device_token` → `DeviceToken`(+`profile`); зависимости `bearer_device`, `bearer_required` |
| `src/aiuse/oauth.py` | Create | Абстракция провайдера + `GitHubProvider` (httpx) + реестр `get_provider` |
| `src/aiuse/schemas.py` | Modify | Схемы auth-флоу, `+global_opt_in`, схемы global-leaderboard |
| `src/aiuse/routers/auth.py` | Create | `GET /auth/start`, `GET /auth/cb/{provider}`, `POST /auth/exchange` |
| `src/aiuse/routers/profiles.py` | Modify | `create_profile` пишет `device_tokens`; `PATCH /me` принимает `global_opt_in` |
| `src/aiuse/routers/snapshots.py` | Modify | `device_id` из токена; upsert по `(user_id, device_id, hour_bucket)`; гейтинг `sharing OR global_opt_in` |
| `src/aiuse/routers/leaderboard.py` | Modify | Без логических изменений; добавить тест на суммирование по устройствам |
| `src/aiuse/routers/global_leaderboard.py` | Create | Публичный `GET /global-leaderboard?period=` |
| `src/aiuse/main.py` | Modify | Подключить роутеры `auth`, `global_leaderboard` |
| `alembic/versions/005_*.py` … `009_*.py` | Create | Миграции схемы + backfill существующих данных |
| `tests/test_auth_oauth.py` | Create | Тесты OAuth-флоу (провайдер замокан) |
| `tests/test_devices.py` | Create | Тесты multi-device sync (суммирование) |
| `tests/test_global_leaderboard.py` | Create | Тесты публичного лидерборда |
| `README.md` | Modify | Раздел про OAuth env-переменные и регистрацию GitHub OAuth App |

**Порядок миграций (важно для backfill):** `005 global_opt_in` → `006 device_tokens (+backfill из api_secret_hash)` → `007 auth_identities` → `008 auth_sessions` → `009 snapshots.device_id (+backfill из legacy device_token)`.

---

## Task 1: Флаг `global_opt_in` на профиле

**Files:**
- Modify: `src/aiuse/models.py` (класс `Profile`)
- Create: `alembic/versions/005_add_global_opt_in.py`
- Modify: `src/aiuse/schemas.py` (`ProfileUpdateRequest`, `ProfileResponse`)
- Modify: `src/aiuse/routers/profiles.py` (`update_profile`)
- Modify: `tests/test_profiles.py`

- [ ] **Step 1: Написать падающий тест**

В `tests/test_profiles.py` добавить (использует существующий хелпер создания профиля; если его нет — создаём через `POST /api/profiles`):

```python
async def test_patch_me_sets_global_opt_in(client):
    created = (await client.post("/api/profiles", json={"display_name": "Glob"})).json()
    secret = created["api_secret"]
    headers = {"Authorization": f"Bearer {secret}"}

    resp = await client.patch("/api/profiles/me", json={"global_opt_in": True}, headers=headers)

    assert resp.status_code == 200
    assert resp.json()["global_opt_in"] is True
```

- [ ] **Step 2: Запустить тест — убедиться, что падает**

Run: `cd ../ai-stats-api && uv run pytest tests/test_profiles.py::test_patch_me_sets_global_opt_in -v`
Expected: FAIL — `global_opt_in` нет ни в ответе, ни в запросе (KeyError / 422 / поле игнорируется).

- [ ] **Step 3: Добавить колонку в модель**

В `src/aiuse/models.py`, класс `Profile`, после `sharing_enabled`:

```python
    global_opt_in: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default="false"
    )
```

- [ ] **Step 4: Миграция 005**

Создать `alembic/versions/005_add_global_opt_in.py`:

```python
"""add_global_opt_in

Revision ID: 005
Revises: 004
"""

from __future__ import annotations

import sqlalchemy as sa

from alembic import op

revision = "005"
down_revision = "004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "profiles",
        sa.Column("global_opt_in", sa.Boolean(), nullable=False, server_default="false"),
    )


def downgrade() -> None:
    op.drop_column("profiles", "global_opt_in")
```

- [ ] **Step 5: Обновить схемы**

В `src/aiuse/schemas.py`:

```python
class ProfileUpdateRequest(BaseModel):
    display_name: str | None = Field(None, min_length=1, max_length=64)
    avatar_b64: str | None = None
    avatar_mime: str | None = None
    sharing_enabled: bool | None = None
    global_opt_in: bool | None = None


class ProfileResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    friend_code: str
    display_name: str
    sharing_enabled: bool
    global_opt_in: bool
    created_at: datetime
```

- [ ] **Step 6: Обработать поле в роутере**

В `src/aiuse/routers/profiles.py`, функция `update_profile`, после блока `sharing_enabled`:

```python
    if payload.global_opt_in is not None:
        me.global_opt_in = payload.global_opt_in
```

- [ ] **Step 7: Запустить тест — убедиться, что проходит**

Run: `cd ../ai-stats-api && uv run pytest tests/test_profiles.py -v`
Expected: PASS (включая новый тест; старые тесты профиля тоже зелёные — `ProfileResponse` теперь содержит `global_opt_in`, проверить, что существующие ассерты не сломались).

- [ ] **Step 8: Commit**

```bash
cd ../ai-stats-api
git add src/aiuse/models.py src/aiuse/schemas.py src/aiuse/routers/profiles.py alembic/versions/005_add_global_opt_in.py tests/test_profiles.py
git commit -m "feat(profiles): добавить флаг global_opt_in для публичного лидерборда"
```

---

## Task 2: Таблица `device_tokens` + backfill + резолв auth по устройству

Это сердце multi-device. Существующий `api_secret` становится одной из строк `device_tokens`. Auth перестаёт смотреть в `profiles.api_secret_hash` и смотрит в `device_tokens`.

**Files:**
- Modify: `src/aiuse/models.py`
- Create: `alembic/versions/006_create_device_tokens.py`
- Modify: `src/aiuse/auth.py`
- Modify: `src/aiuse/routers/profiles.py` (`create_profile`)
- Modify: `tests/test_auth.py`

- [ ] **Step 1: Написать падающий тест — токен из device_tokens аутентифицирует**

В `tests/test_auth.py`:

```python
from sqlalchemy import select

from aiuse.models import DeviceToken


async def test_create_profile_creates_device_token(client, db_session):
    created = (await client.post("/api/profiles", json={"display_name": "Dev"})).json()
    uid = created["server_user_id"]

    rows = (
        await db_session.execute(select(DeviceToken).where(DeviceToken.profile_id == uid))
    ).scalars().all()

    assert len(rows) == 1
    assert rows[0].device_label is not None


async def test_bearer_resolves_via_device_tokens(client):
    created = (await client.post("/api/profiles", json={"display_name": "Dev2"})).json()
    headers = {"Authorization": f"Bearer {created['api_secret']}"}

    # любой защищённый эндпоинт; используем PATCH /me как индикатор успешной auth
    resp = await client.patch("/api/profiles/me", json={"display_name": "Renamed"}, headers=headers)
    assert resp.status_code == 200
```

- [ ] **Step 2: Запустить — убедиться, что падает**

Run: `cd ../ai-stats-api && uv run pytest tests/test_auth.py::test_create_profile_creates_device_token -v`
Expected: FAIL — `ImportError: cannot import name 'DeviceToken'`.

- [ ] **Step 3: Добавить модель `DeviceToken`**

В `src/aiuse/models.py` (импорты `relationship` добавить из `sqlalchemy.orm`):

```python
from sqlalchemy.orm import Mapped, mapped_column, relationship
```

```python
class DeviceToken(Base):
    __tablename__ = "device_tokens"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    profile_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False
    )
    token_hash: Mapped[str] = mapped_column(Text, nullable=False)
    device_label: Mapped[str | None] = mapped_column(Text, nullable=True)
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    profile: Mapped[Profile] = relationship()

    __table_args__ = (
        UniqueConstraint("token_hash", name="uq_device_tokens_hash"),
        Index("idx_device_tokens_profile", "profile_id"),
    )
```

Также сделать `profiles.api_secret_hash` nullable (для OAuth-профилей секрета нет):

```python
    api_secret_hash: Mapped[str | None] = mapped_column(Text, nullable=True)
```

- [ ] **Step 4: Миграция 006 (создать таблицу + backfill + nullable)**

Создать `alembic/versions/006_create_device_tokens.py`:

```python
"""create_device_tokens + backfill from api_secret_hash

Revision ID: 006
Revises: 005
"""

from __future__ import annotations

import sqlalchemy as sa

from alembic import op

revision = "006"
down_revision = "005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "device_tokens",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("profile_id", sa.BigInteger(), nullable=False),
        sa.Column("token_hash", sa.Text(), nullable=False),
        sa.Column("device_label", sa.Text(), nullable=True),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.ForeignKeyConstraint(
            ["profile_id"], ["profiles.id"], ondelete="CASCADE", name="fk_device_tokens_profile"
        ),
        sa.PrimaryKeyConstraint("id", name="pk_device_tokens"),
        sa.UniqueConstraint("token_hash", name="uq_device_tokens_hash"),
    )
    op.create_index("idx_device_tokens_profile", "device_tokens", ["profile_id"])

    # backfill: каждый существующий профиль → одна legacy-строка device_tokens
    op.execute(
        """
        INSERT INTO device_tokens (profile_id, token_hash, device_label, created_at)
        SELECT id, api_secret_hash, 'legacy', now()
        FROM profiles
        WHERE api_secret_hash IS NOT NULL
        """
    )

    op.alter_column("profiles", "api_secret_hash", existing_type=sa.Text(), nullable=True)


def downgrade() -> None:
    op.alter_column("profiles", "api_secret_hash", existing_type=sa.Text(), nullable=False)
    op.drop_index("idx_device_tokens_profile", table_name="device_tokens")
    op.drop_table("device_tokens")
```

- [ ] **Step 5: Переписать `auth.py` на резолв через device_tokens**

Заменить содержимое `src/aiuse/auth.py`:

```python
from __future__ import annotations

from fastapi import Depends, Header, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from aiuse.codes import hash_api_secret
from aiuse.db import get_session
from aiuse.models import DeviceToken, Profile


async def find_device_by_token(session: AsyncSession, token: str) -> DeviceToken | None:
    """Ищем device_token по sha256(token). None если не нашли.

    `selectinload(profile)` — чтобы `device.profile` был безопасен при
    синхронном доступе в async (иначе ленивая загрузка кидает MissingGreenlet).
    """
    h = hash_api_secret(token)
    stmt = (
        select(DeviceToken)
        .where(DeviceToken.token_hash == h)
        .options(selectinload(DeviceToken.profile))
    )
    return (await session.execute(stmt)).scalar_one_or_none()


def _extract_bearer(authorization: str | None) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="missing or malformed Authorization header",
        )
    return authorization.removeprefix("Bearer ").strip()


async def bearer_device(
    authorization: str | None = Header(None),
    session: AsyncSession = Depends(get_session),
) -> DeviceToken:
    """FastAPI dependency: текущий DeviceToken (с подгруженным .profile) или 401."""
    token = _extract_bearer(authorization)
    device = await find_device_by_token(session, token)
    if device is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid token")
    return device


async def bearer_required(
    device: DeviceToken = Depends(bearer_device),
) -> Profile:
    """Обратная совместимость: возвращает Profile текущего устройства."""
    return device.profile
```

> Примечание: `device.profile` безопасен, потому что `find_device_by_token` грузит его через `selectinload`. Без этого async-SQLAlchemy кинул бы `MissingGreenlet` на синхронном доступе к relationship.

- [ ] **Step 6: `create_profile` пишет device_token**

В `src/aiuse/routers/profiles.py`: импортировать модель и после успешного `commit` профиля создать device-токен. Заменить тело цикла создания так, чтобы legacy-`api_secret` дублировался в `device_tokens`:

```python
from aiuse.models import DeviceToken, Friendship, Profile
```

В `create_profile`, после `await session.refresh(profile)` (профиль уже создан) и перед формированием ответа:

```python
    session.add(
        DeviceToken(
            profile_id=profile.id,
            token_hash=hash_api_secret(secret),
            device_label="legacy",
        )
    )
    await session.commit()
```

Добавить импорт `hash_api_secret` в этот файл (он уже импортируется из `aiuse.codes`).

- [ ] **Step 7: Запустить тесты**

Run: `cd ../ai-stats-api && uv run pytest tests/test_auth.py tests/test_profiles.py tests/test_snapshots.py -v`
Expected: PASS. Особое внимание — старые тесты, использующие Bearer: они должны проходить, так как `create_profile` теперь кладёт токен в `device_tokens`, а `bearer_*` резолвит оттуда.

- [ ] **Step 8: Commit**

```bash
cd ../ai-stats-api
git add src/aiuse/models.py src/aiuse/auth.py src/aiuse/routers/profiles.py alembic/versions/006_create_device_tokens.py tests/test_auth.py
git commit -m "feat(auth): ввести device_tokens и резолвить bearer по устройству"
```

---

## Task 3: Таблица `auth_identities`

**Files:**
- Modify: `src/aiuse/models.py`
- Create: `alembic/versions/007_create_auth_identities.py`
- Modify: `tests/test_auth.py`

- [ ] **Step 1: Падающий тест — модель существует и уникальна по (provider, sub)**

В `tests/test_auth.py`:

```python
import pytest
from sqlalchemy.exc import IntegrityError

from aiuse.models import AuthIdentity, Profile


async def test_auth_identity_unique_per_provider_sub(db_session):
    p = Profile(friend_code="AAAAAAAAAA", display_name="X")
    db_session.add(p)
    await db_session.flush()

    db_session.add(AuthIdentity(profile_id=p.id, provider="github", provider_sub="42", handle="x"))
    await db_session.flush()

    db_session.add(AuthIdentity(profile_id=p.id, provider="github", provider_sub="42", handle="y"))
    with pytest.raises(IntegrityError):
        await db_session.flush()
    await db_session.rollback()
```

- [ ] **Step 2: Запустить — падает**

Run: `cd ../ai-stats-api && uv run pytest tests/test_auth.py::test_auth_identity_unique_per_provider_sub -v`
Expected: FAIL — `ImportError: cannot import name 'AuthIdentity'`.

> Примечание: тест создаёт `Profile` без `api_secret_hash` — после Task 2 колонка nullable, поэтому это легально.

- [ ] **Step 3: Модель `AuthIdentity`**

В `src/aiuse/models.py`:

```python
class AuthIdentity(Base):
    __tablename__ = "auth_identities"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    profile_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False
    )
    provider: Mapped[str] = mapped_column(Text, nullable=False)
    provider_sub: Mapped[str] = mapped_column(Text, nullable=False)
    handle: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        UniqueConstraint("provider", "provider_sub", name="uq_auth_identities_provider_sub"),
        Index("idx_auth_identities_profile", "profile_id"),
    )
```

- [ ] **Step 4: Миграция 007**

`alembic/versions/007_create_auth_identities.py`:

```python
"""create_auth_identities

Revision ID: 007
Revises: 006
"""

from __future__ import annotations

import sqlalchemy as sa

from alembic import op

revision = "007"
down_revision = "006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "auth_identities",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("profile_id", sa.BigInteger(), nullable=False),
        sa.Column("provider", sa.Text(), nullable=False),
        sa.Column("provider_sub", sa.Text(), nullable=False),
        sa.Column("handle", sa.Text(), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.ForeignKeyConstraint(
            ["profile_id"], ["profiles.id"], ondelete="CASCADE", name="fk_auth_identities_profile"
        ),
        sa.PrimaryKeyConstraint("id", name="pk_auth_identities"),
        sa.UniqueConstraint("provider", "provider_sub", name="uq_auth_identities_provider_sub"),
    )
    op.create_index("idx_auth_identities_profile", "auth_identities", ["profile_id"])


def downgrade() -> None:
    op.drop_index("idx_auth_identities_profile", table_name="auth_identities")
    op.drop_table("auth_identities")
```

- [ ] **Step 5: Запустить — проходит**

Run: `cd ../ai-stats-api && uv run pytest tests/test_auth.py::test_auth_identity_unique_per_provider_sub -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd ../ai-stats-api
git add src/aiuse/models.py alembic/versions/007_create_auth_identities.py tests/test_auth.py
git commit -m "feat(auth): добавить таблицу auth_identities"
```

---

## Task 4: Таблица `auth_sessions` (pending OAuth-сессии)

Транзиентное состояние между `/auth/start`, `/auth/cb` и `/auth/exchange`. Тут же временно лежит GitHub data-токен (удаляется на exchange).

**Files:**
- Modify: `src/aiuse/models.py`
- Create: `alembic/versions/008_create_auth_sessions.py`

- [ ] **Step 1: Модель `AuthSession`**

В `src/aiuse/models.py`:

```python
class AuthSession(Base):
    __tablename__ = "auth_sessions"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    state: Mapped[str] = mapped_column(Text, nullable=False)          # echo через провайдера
    provider: Mapped[str] = mapped_column(Text, nullable=False)
    challenge: Mapped[str] = mapped_column(Text, nullable=False)      # sha256(verifier) от клиента
    include_private: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    link_profile_id: Mapped[int | None] = mapped_column(BigInteger, nullable=True)   # если стартовали залогиненным
    resolved_profile_id: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    provider_token: Mapped[str | None] = mapped_column(Text, nullable=True)          # GitHub data-токен, транзиент
    auth_code_hash: Mapped[str | None] = mapped_column(Text, nullable=True)          # выдаётся на callback
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    __table_args__ = (
        UniqueConstraint("state", name="uq_auth_sessions_state"),
        Index("idx_auth_sessions_auth_code", "auth_code_hash"),
    )
```

- [ ] **Step 2: Миграция 008**

`alembic/versions/008_create_auth_sessions.py`:

```python
"""create_auth_sessions

Revision ID: 008
Revises: 007
"""

from __future__ import annotations

import sqlalchemy as sa

from alembic import op

revision = "008"
down_revision = "007"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "auth_sessions",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("state", sa.Text(), nullable=False),
        sa.Column("provider", sa.Text(), nullable=False),
        sa.Column("challenge", sa.Text(), nullable=False),
        sa.Column("include_private", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("link_profile_id", sa.BigInteger(), nullable=True),
        sa.Column("resolved_profile_id", sa.BigInteger(), nullable=True),
        sa.Column("provider_token", sa.Text(), nullable=True),
        sa.Column("auth_code_hash", sa.Text(), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id", name="pk_auth_sessions"),
        sa.UniqueConstraint("state", name="uq_auth_sessions_state"),
    )
    op.create_index("idx_auth_sessions_auth_code", "auth_sessions", ["auth_code_hash"])


def downgrade() -> None:
    op.drop_index("idx_auth_sessions_auth_code", table_name="auth_sessions")
    op.drop_table("auth_sessions")
```

- [ ] **Step 3: Smoke-проверка миграций до головы**

Run: `cd ../ai-stats-api && uv run pytest tests/test_health.py -v`
Expected: PASS (схема создаётся через `Base.metadata.create_all` в conftest, новые таблицы появляются — падений импорта нет).

- [ ] **Step 4: Commit**

```bash
cd ../ai-stats-api
git add src/aiuse/models.py alembic/versions/008_create_auth_sessions.py
git commit -m "feat(auth): добавить таблицу auth_sessions для OAuth-брокера"
```

---

## Task 5: Конфиг + httpx + абстракция OAuth-провайдера

**Files:**
- Modify: `pyproject.toml`
- Modify: `src/aiuse/config.py`
- Modify: `src/aiuse/codes.py`
- Create: `src/aiuse/oauth.py`
- Create: `tests/test_oauth_provider.py`

- [ ] **Step 1: Добавить httpx в runtime-зависимости**

В `pyproject.toml`, секция `[project].dependencies`, добавить строку:

```toml
    "httpx>=0.27",
```

Установить: `cd ../ai-stats-api && uv pip install -e ".[dev]"`

- [ ] **Step 2: Расширить конфиг**

В `src/aiuse/config.py`, класс `Settings`, добавить поля:

```python
    public_base_url: str = "https://aiuse.popovs.tech"
    app_callback_url: str = "burn://auth/callback"
    auth_session_ttl_seconds: int = 600

    github_client_id: str = ""
    github_client_secret: str = ""
    github_scope_public: str = "read:user"
    github_scope_private: str = "read:user repo"
```

- [ ] **Step 3: Хелперы генерации токена/кода в codes.py**

В `src/aiuse/codes.py` добавить (переиспользуя sha256):

```python
def generate_device_token() -> str:
    """Per-device bearer-токен. 32 байта в hex."""
    return secrets.token_hex(API_SECRET_BYTES)


def generate_auth_code() -> str:
    """One-time код для обмена на device_token. 32 байта в hex."""
    return secrets.token_hex(API_SECRET_BYTES)


def hash_token(token: str) -> str:
    """sha256(token) hex. Алиас hash_api_secret для читаемости в auth-флоу."""
    return hash_api_secret(token)


def sha256_hex(value: str) -> str:
    """sha256(value) hex — для проверки challenge == sha256(verifier)."""
    return hashlib.sha256(value.encode()).hexdigest()
```

- [ ] **Step 4: Падающий тест провайдера**

Создать `tests/test_oauth_provider.py`:

```python
from aiuse.config import settings
from aiuse.oauth import ProviderIdentity, get_provider


def test_github_authorize_url_contains_required_params():
    settings.github_client_id = "cid123"
    p = get_provider("github")

    url = p.authorize_url(state="st", include_private=False)

    assert url.startswith("https://github.com/login/oauth/authorize")
    assert "client_id=cid123" in url
    assert "state=st" in url
    assert "scope=read%3Auser" in url or "scope=read:user" in url


def test_get_provider_unknown_raises():
    import pytest

    with pytest.raises(KeyError):
        get_provider("myspace")
```

- [ ] **Step 5: Запустить — падает**

Run: `cd ../ai-stats-api && uv run pytest tests/test_oauth_provider.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'aiuse.oauth'`.

- [ ] **Step 6: Реализовать `oauth.py`**

Создать `src/aiuse/oauth.py`:

```python
from __future__ import annotations

import urllib.parse
from dataclasses import dataclass
from typing import Protocol

import httpx

from aiuse.config import settings


@dataclass(frozen=True)
class ProviderIdentity:
    """Нормализованная идентичность от провайдера."""

    sub: str
    handle: str | None


class OAuthProvider(Protocol):
    name: str

    def authorize_url(self, state: str, include_private: bool) -> str: ...

    async def exchange_code(self, code: str) -> str:
        """Меняет authorization code на access-токен провайдера."""
        ...

    async def fetch_identity(self, access_token: str) -> ProviderIdentity:
        """Тащит стабильный sub + handle по access-токену."""
        ...


class GitHubProvider:
    name = "github"

    def _redirect_uri(self) -> str:
        return f"{settings.public_base_url}/api/auth/cb/github"

    def authorize_url(self, state: str, include_private: bool) -> str:
        scope = settings.github_scope_private if include_private else settings.github_scope_public
        params = {
            "client_id": settings.github_client_id,
            "redirect_uri": self._redirect_uri(),
            "scope": scope,
            "state": state,
        }
        return "https://github.com/login/oauth/authorize?" + urllib.parse.urlencode(params)

    async def exchange_code(self, code: str) -> str:
        async with httpx.AsyncClient(timeout=15) as http:
            resp = await http.post(
                "https://github.com/login/oauth/access_token",
                headers={"Accept": "application/json"},
                data={
                    "client_id": settings.github_client_id,
                    "client_secret": settings.github_client_secret,
                    "code": code,
                    "redirect_uri": self._redirect_uri(),
                },
            )
        resp.raise_for_status()
        token = resp.json().get("access_token")
        if not token:
            raise ValueError("github token exchange returned no access_token")
        return token

    async def fetch_identity(self, access_token: str) -> ProviderIdentity:
        async with httpx.AsyncClient(timeout=15) as http:
            resp = await http.get(
                "https://api.github.com/user",
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "Accept": "application/vnd.github+json",
                },
            )
        resp.raise_for_status()
        data = resp.json()
        return ProviderIdentity(sub=str(data["id"]), handle=data.get("login"))


_PROVIDERS: dict[str, OAuthProvider] = {"github": GitHubProvider()}


def get_provider(name: str) -> OAuthProvider:
    """Возвращает провайдера по имени. KeyError если неизвестен."""
    return _PROVIDERS[name]
```

- [ ] **Step 7: Запустить — проходит**

Run: `cd ../ai-stats-api && uv run pytest tests/test_oauth_provider.py -v`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
cd ../ai-stats-api
git add pyproject.toml src/aiuse/config.py src/aiuse/codes.py src/aiuse/oauth.py tests/test_oauth_provider.py
git commit -m "feat(auth): абстракция OAuth-провайдера и GitHubProvider"
```

---

## Task 6: Auth-роутер — `/auth/start`

**Files:**
- Modify: `src/aiuse/schemas.py`
- Create: `src/aiuse/routers/auth.py`
- Modify: `src/aiuse/main.py`
- Create: `tests/test_auth_oauth.py`

- [ ] **Step 1: Схемы auth-флоу**

В `src/aiuse/schemas.py` добавить секцию:

```python
# ── auth (OAuth broker) ────────────────────────────────────────────────

class AuthExchangeRequest(BaseModel):
    code: str = Field(..., min_length=1)
    verifier: str = Field(..., min_length=1)


class AuthExchangeResponse(BaseModel):
    device_token: str
    github_token: str | None = None
    friend_code: str
    server_user_id: int
```

- [ ] **Step 2: Падающий тест `/auth/start`**

Создать `tests/test_auth_oauth.py`:

```python
from sqlalchemy import select

from aiuse.config import settings
from aiuse.models import AuthSession


async def test_auth_start_redirects_to_provider_and_stores_session(client, db_session):
    settings.github_client_id = "cid"
    resp = await client.get(
        "/api/auth/start",
        params={"provider": "github", "challenge": "CH", "include_private": "false"},
        follow_redirects=False,
    )

    assert resp.status_code == 307
    loc = resp.headers["location"]
    assert loc.startswith("https://github.com/login/oauth/authorize")

    sessions = (await db_session.execute(select(AuthSession))).scalars().all()
    assert any(s.challenge == "CH" and s.provider == "github" for s in sessions)


async def test_auth_start_unknown_provider_400(client):
    resp = await client.get(
        "/api/auth/start",
        params={"provider": "myspace", "challenge": "CH"},
        follow_redirects=False,
    )
    assert resp.status_code == 400
```

- [ ] **Step 3: Запустить — падает**

Run: `cd ../ai-stats-api && uv run pytest tests/test_auth_oauth.py::test_auth_start_redirects_to_provider_and_stores_session -v`
Expected: FAIL — 404 (роутера нет).

- [ ] **Step 4: Создать роутер с `/start`**

Создать `src/aiuse/routers/auth.py`:

```python
from __future__ import annotations

import secrets
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from fastapi.responses import RedirectResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from aiuse.auth import find_device_by_token
from aiuse.config import settings
from aiuse.db import get_session
from aiuse.oauth import get_provider

router = APIRouter(prefix="/auth", tags=["auth"])


@router.get("/start")
async def auth_start(
    provider: str = Query(...),
    challenge: str = Query(..., min_length=1),
    include_private: bool = Query(False),
    authorization: str | None = Header(None),
    session: AsyncSession = Depends(get_session),
) -> RedirectResponse:
    try:
        prov = get_provider(provider)
    except KeyError as e:
        raise HTTPException(status_code=400, detail=f"unknown provider: {provider}") from e

    # если стартуем залогиненными — привяжем identity к этому профилю
    link_profile_id = None
    if authorization and authorization.startswith("Bearer "):
        token = authorization.removeprefix("Bearer ").strip()
        device = await find_device_by_token(session, token)
        if device is not None:
            link_profile_id = device.profile_id

    from aiuse.models import AuthSession

    state = secrets.token_urlsafe(24)
    now = datetime.now(UTC)
    session.add(
        AuthSession(
            state=state,
            provider=provider,
            challenge=challenge,
            include_private=include_private,
            link_profile_id=link_profile_id,
            expires_at=now + timedelta(seconds=settings.auth_session_ttl_seconds),
        )
    )
    await session.commit()

    return RedirectResponse(
        url=prov.authorize_url(state=state, include_private=include_private),
        status_code=status.HTTP_307_TEMPORARY_REDIRECT,
    )
```

- [ ] **Step 5: Подключить роутер в main.py**

В `src/aiuse/main.py`:

```python
from aiuse.routers import auth, avatars, blocks, friends, health, leaderboard, profiles, snapshots
```

```python
app.include_router(auth.router, prefix="/api")
```

- [ ] **Step 6: Запустить — проходит**

Run: `cd ../ai-stats-api && uv run pytest tests/test_auth_oauth.py -v`
Expected: PASS (оба теста start).

- [ ] **Step 7: Commit**

```bash
cd ../ai-stats-api
git add src/aiuse/schemas.py src/aiuse/routers/auth.py src/aiuse/main.py tests/test_auth_oauth.py
git commit -m "feat(auth): эндпоинт /auth/start с pending-сессией"
```

---

## Task 7: Auth-роутер — `/auth/cb/{provider}` (callback)

**Files:**
- Modify: `src/aiuse/routers/auth.py`
- Modify: `tests/test_auth_oauth.py`

- [ ] **Step 1: Падающий тест callback (провайдер замокан)**

В `tests/test_auth_oauth.py` добавить хелпер мока и тест:

```python
import pytest

import aiuse.routers.auth as auth_router
from aiuse.models import AuthIdentity, Profile
from aiuse.oauth import ProviderIdentity


class _FakeProvider:
    name = "github"

    def authorize_url(self, state, include_private):
        return f"https://github.com/login/oauth/authorize?state={state}"

    async def exchange_code(self, code):
        return "gh-access-token"

    async def fetch_identity(self, access_token):
        return ProviderIdentity(sub="999", handle="octocat")


@pytest.fixture
def fake_github(monkeypatch):
    fake = _FakeProvider()
    monkeypatch.setattr(auth_router, "get_provider", lambda name: fake)
    return fake


async def _start(client, challenge="CH", headers=None):
    resp = await client.get(
        "/api/auth/start",
        params={"provider": "github", "challenge": challenge},
        headers=headers or {},
        follow_redirects=False,
    )
    # вытащить state из Location
    from urllib.parse import parse_qs, urlparse

    return parse_qs(urlparse(resp.headers["location"]).query)["state"][0]


async def test_callback_creates_profile_and_redirects_to_app(client, db_session, fake_github):
    state = await _start(client)

    resp = await client.get(
        "/api/auth/cb/github",
        params={"code": "gh-code", "state": state},
        follow_redirects=False,
    )

    assert resp.status_code == 307
    assert resp.headers["location"].startswith("burn://auth/callback?code=")

    ident = (
        await db_session.execute(
            select(AuthIdentity).where(
                AuthIdentity.provider == "github", AuthIdentity.provider_sub == "999"
            )
        )
    ).scalar_one()
    assert ident.handle == "octocat"


async def test_callback_unknown_state_400(client, fake_github):
    resp = await client.get(
        "/api/auth/cb/github",
        params={"code": "x", "state": "nope"},
        follow_redirects=False,
    )
    assert resp.status_code == 400
```

- [ ] **Step 2: Запустить — падает**

Run: `cd ../ai-stats-api && uv run pytest tests/test_auth_oauth.py::test_callback_creates_profile_and_redirects_to_app -v`
Expected: FAIL — 404 (нет `/auth/cb`).

- [ ] **Step 3: Реализовать callback**

В `src/aiuse/routers/auth.py` добавить импорты и эндпоинт:

```python
from sqlalchemy.exc import IntegrityError

from aiuse.codes import generate_auth_code, generate_friend_code, hash_token
from aiuse.models import AuthIdentity, AuthSession, Profile
```

```python
@router.get("/cb/{provider}")
async def auth_callback(
    provider: str,
    code: str = Query(...),
    state: str = Query(...),
    session: AsyncSession = Depends(get_session),
) -> RedirectResponse:
    now = datetime.now(UTC)
    auth_session = (
        await session.execute(select(AuthSession).where(AuthSession.state == state))
    ).scalar_one_or_none()
    if auth_session is None or auth_session.expires_at < now:
        raise HTTPException(status_code=400, detail="invalid or expired state")

    prov = get_provider(provider)
    access_token = await prov.exchange_code(code)
    identity = await prov.fetch_identity(access_token)

    # ищем существующую identity
    existing = (
        await session.execute(
            select(AuthIdentity).where(
                AuthIdentity.provider == provider,
                AuthIdentity.provider_sub == identity.sub,
            )
        )
    ).scalar_one_or_none()

    if existing is not None:
        # identity уже привязана. если стартовали с привязкой к ДРУГОМУ профилю — конфликт
        if auth_session.link_profile_id and auth_session.link_profile_id != existing.profile_id:
            raise HTTPException(status_code=409, detail="identity already linked to another account")
        profile_id = existing.profile_id
    elif auth_session.link_profile_id is not None:
        # привязываем новую identity к текущему профилю
        session.add(
            AuthIdentity(
                profile_id=auth_session.link_profile_id,
                provider=provider,
                provider_sub=identity.sub,
                handle=identity.handle,
            )
        )
        profile_id = auth_session.link_profile_id
    else:
        # новый профиль с retry на коллизию friend_code через SAVEPOINT:
        # begin_nested откатывает только вставку профиля, не всю транзакцию
        # (auth_session мы ещё не трогали — её мутируем ниже).
        profile = None
        for _ in range(3):
            candidate = Profile(
                friend_code=generate_friend_code(),
                display_name=identity.handle or "anon",
            )
            try:
                async with session.begin_nested():
                    session.add(candidate)
                    await session.flush()
                profile = candidate
                break
            except IntegrityError:
                continue
        if profile is None:
            raise HTTPException(status_code=500, detail="friend_code collision")

        session.add(
            AuthIdentity(
                profile_id=profile.id,
                provider=provider,
                provider_sub=identity.sub,
                handle=identity.handle,
            )
        )
        profile_id = profile.id

    auth_code = generate_auth_code()
    auth_session.resolved_profile_id = profile_id
    auth_session.provider_token = access_token if provider == "github" else None
    auth_session.auth_code_hash = hash_token(auth_code)
    await session.commit()

    return RedirectResponse(
        url=f"{settings.app_callback_url}?code={auth_code}&state={state}",
        status_code=status.HTTP_307_TEMPORARY_REDIRECT,
    )
```

> `friend_code` генерируется с retry до 3 раз через SAVEPOINT (`begin_nested`) — как в существующем `create_profile`. Коллизия на 500 юзерах из 30^10 пренебрежима, но retry даёт согласованность с остальным кодом и не валит весь вход 500-кой.

- [ ] **Step 4: Запустить — проходит**

Run: `cd ../ai-stats-api && uv run pytest tests/test_auth_oauth.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd ../ai-stats-api
git add src/aiuse/routers/auth.py tests/test_auth_oauth.py
git commit -m "feat(auth): callback /auth/cb — upsert profile+identity, one-time code"
```

---

## Task 8: Auth-роутер — `/auth/exchange` + конфликт + линковка

**Files:**
- Modify: `src/aiuse/routers/auth.py`
- Modify: `tests/test_auth_oauth.py`

- [ ] **Step 1: Падающие тесты exchange + линковка + конфликт**

В `tests/test_auth_oauth.py` добавить:

```python
import hashlib


async def _full_login(client, fake_github, challenge, verifier, headers=None):
    state = await _start(client, challenge=challenge, headers=headers)
    cb = await client.get(
        "/api/auth/cb/github", params={"code": "c", "state": state}, follow_redirects=False
    )
    from urllib.parse import parse_qs, urlparse

    code = parse_qs(urlparse(cb.headers["location"]).query)["code"][0]
    return await client.post("/api/auth/exchange", json={"code": code, "verifier": verifier})


async def test_exchange_returns_device_and_github_token(client, fake_github):
    verifier = "v-secret"
    challenge = hashlib.sha256(verifier.encode()).hexdigest()

    resp = await _full_login(client, fake_github, challenge, verifier)

    assert resp.status_code == 200
    body = resp.json()
    assert body["device_token"]
    assert body["github_token"] == "gh-access-token"
    assert body["friend_code"]

    # выданный device_token реально аутентифицирует
    me = await client.patch(
        "/api/profiles/me",
        json={"display_name": "Z"},
        headers={"Authorization": f"Bearer {body['device_token']}"},
    )
    assert me.status_code == 200


async def test_exchange_wrong_verifier_400(client, fake_github):
    challenge = hashlib.sha256(b"right").hexdigest()
    resp = await _full_login(client, fake_github, challenge, verifier="wrong")
    assert resp.status_code == 400


async def test_second_device_same_identity_same_profile(client, fake_github):
    v = "v"
    ch = hashlib.sha256(v.encode()).hexdigest()
    first = (await _full_login(client, fake_github, ch, v)).json()
    second = (await _full_login(client, fake_github, ch, v)).json()

    assert first["server_user_id"] == second["server_user_id"]
    assert first["device_token"] != second["device_token"]


async def test_link_conflict_409(client, fake_github, db_session):
    # профиль A логинится через google-identity заранее (вручную), затем линкует github,
    # который уже принадлежит профилю B
    from aiuse.models import AuthIdentity, DeviceToken, Profile
    from aiuse.codes import generate_device_token, hash_token

    # профиль B владеет github sub=999
    pb = Profile(friend_code="BBBBBBBBBB", display_name="B")
    db_session.add(pb)
    await db_session.flush()
    db_session.add(AuthIdentity(profile_id=pb.id, provider="github", provider_sub="999", handle="octocat"))

    # профиль A с собственным device_token
    pa = Profile(friend_code="CCCCCCCCCC", display_name="A")
    db_session.add(pa)
    await db_session.flush()
    tok = generate_device_token()
    db_session.add(DeviceToken(profile_id=pa.id, token_hash=hash_token(tok), device_label="a"))
    await db_session.commit()

    # A стартует залогиненным и пытается привязать github sub=999 (принадлежит B)
    state = await _start(client, headers={"Authorization": f"Bearer {tok}"})
    cb = await client.get(
        "/api/auth/cb/github", params={"code": "c", "state": state}, follow_redirects=False
    )
    assert cb.status_code == 409
```

- [ ] **Step 2: Запустить — падает**

Run: `cd ../ai-stats-api && uv run pytest tests/test_auth_oauth.py::test_exchange_returns_device_and_github_token -v`
Expected: FAIL — 404 (нет `/auth/exchange`).

- [ ] **Step 3: Реализовать exchange**

В `src/aiuse/routers/auth.py` добавить импорты и эндпоинт:

```python
from aiuse.codes import generate_device_token, sha256_hex
from aiuse.models import DeviceToken
from aiuse.schemas import AuthExchangeRequest, AuthExchangeResponse
```

```python
@router.post("/exchange", response_model=AuthExchangeResponse)
async def auth_exchange(
    payload: AuthExchangeRequest,
    session: AsyncSession = Depends(get_session),
) -> AuthExchangeResponse:
    now = datetime.now(UTC)
    code_hash = hash_token(payload.code)
    auth_session = (
        await session.execute(select(AuthSession).where(AuthSession.auth_code_hash == code_hash))
    ).scalar_one_or_none()
    if auth_session is None or auth_session.expires_at < now or auth_session.resolved_profile_id is None:
        raise HTTPException(status_code=400, detail="invalid or expired code")

    if sha256_hex(payload.verifier) != auth_session.challenge:
        raise HTTPException(status_code=400, detail="verifier does not match challenge")

    profile = (
        await session.execute(select(Profile).where(Profile.id == auth_session.resolved_profile_id))
    ).scalar_one()

    device_token = generate_device_token()
    session.add(
        DeviceToken(
            profile_id=profile.id,
            token_hash=hash_token(device_token),
            device_label=auth_session.provider,
        )
    )

    github_token = auth_session.provider_token if auth_session.provider == "github" else None

    # сессия одноразовая — удаляем (и data-токен вместе с ней)
    await session.delete(auth_session)
    await session.commit()

    return AuthExchangeResponse(
        device_token=device_token,
        github_token=github_token,
        friend_code=profile.friend_code,
        server_user_id=profile.id,
    )
```

- [ ] **Step 4: Запустить весь auth-флоу**

Run: `cd ../ai-stats-api && uv run pytest tests/test_auth_oauth.py -v`
Expected: PASS (exchange, wrong verifier, second device, conflict).

- [ ] **Step 5: Commit**

```bash
cd ../ai-stats-api
git add src/aiuse/routers/auth.py tests/test_auth_oauth.py
git commit -m "feat(auth): /auth/exchange — выдача device_token и github-токена, защита verifier"
```

---

## Task 9: `device_id` в снапшотах + гейтинг по sharing OR global

**Files:**
- Modify: `src/aiuse/models.py` (класс `Snapshot`)
- Create: `alembic/versions/009_snapshots_device_id.py`
- Modify: `src/aiuse/routers/snapshots.py`
- Create: `tests/test_devices.py`

- [ ] **Step 1: Падающий тест — два устройства суммируются на friends-лидерборде**

Создать `tests/test_devices.py`:

```python
from datetime import UTC, datetime

from aiuse.codes import generate_device_token, hash_token
from aiuse.models import DeviceToken, Profile


async def _profile_with_two_devices(client, db_session, name="MD"):
    created = (await client.post("/api/profiles", json={"display_name": name})).json()
    uid = created["server_user_id"]
    # включаем шаринг
    await client.patch(
        "/api/profiles/me",
        json={"sharing_enabled": True},
        headers={"Authorization": f"Bearer {created['api_secret']}"},
    )
    # второй device_token
    tok2 = generate_device_token()
    db_session.add(DeviceToken(profile_id=uid, token_hash=hash_token(tok2), device_label="d2"))
    await db_session.commit()
    return created["api_secret"], tok2, created["friend_code"]


async def test_two_devices_tokens_sum_in_leaderboard(client, db_session):
    tok1, tok2, _ = await _profile_with_two_devices(client, db_session)
    hour = datetime(2026, 6, 3, 10, 0, 0, tzinfo=UTC).isoformat()

    for tok, ti in ((tok1, 1000), (tok2, 500)):
        r = await client.post(
            "/api/snapshots",
            json={"snapshots": [{"hour_bucket": hour, "tokens_input": ti, "tokens_output": 0}]},
            headers={"Authorization": f"Bearer {tok}"},
        )
        assert r.status_code == 200

    lb = await client.get(
        "/api/leaderboard",
        params={"period": "month"},
        headers={"Authorization": f"Bearer {tok1}"},
    )
    me_entry = next(e for e in lb.json()["entries"] if e["is_me"])
    assert me_entry["tokens_total"] == 1500
```

- [ ] **Step 2: Запустить — падает**

Run: `cd ../ai-stats-api && uv run pytest tests/test_devices.py -v`
Expected: FAIL — без `device_id` в PK второй апсёрт перезатрёт первый по `(user_id, hour_bucket)`, итог будет 500, не 1500.

- [ ] **Step 3: Обновить модель `Snapshot`**

В `src/aiuse/models.py`, класс `Snapshot`: добавить `device_id` и поменять PK:

```python
class Snapshot(Base):
    __tablename__ = "snapshots"

    user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False
    )
    device_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("device_tokens.id", ondelete="CASCADE"), nullable=False
    )
    hour_bucket: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    tokens_input: Mapped[int] = mapped_column(BigInteger, nullable=False, server_default="0")
    tokens_output: Mapped[int] = mapped_column(BigInteger, nullable=False, server_default="0")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (
        PrimaryKeyConstraint("user_id", "device_id", "hour_bucket", name="pk_snapshots"),
        Index("idx_snapshots_hour", "hour_bucket"),
    )
```

- [ ] **Step 4: Миграция 009 (добавить device_id, backfill, сменить PK)**

`alembic/versions/009_snapshots_device_id.py`:

```python
"""snapshots.device_id + backfill + new PK

Revision ID: 009
Revises: 008
"""

from __future__ import annotations

import sqlalchemy as sa

from alembic import op

revision = "009"
down_revision = "008"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()

    # 1. добавить nullable device_id
    op.add_column("snapshots", sa.Column("device_id", sa.BigInteger(), nullable=True))

    # 2. backfill: device_id = самый ранний device_token профиля (по MIN(id)).
    #    Не завязываемся на device_label='legacy' — берём любой существующий токен
    #    профиля. На этой точке миграций у каждого профиля ровно один (из 006).
    op.execute(
        """
        UPDATE snapshots s
        SET device_id = dt.id
        FROM (
            SELECT profile_id, MIN(id) AS id
            FROM device_tokens
            GROUP BY profile_id
        ) dt
        WHERE dt.profile_id = s.user_id
        """
    )

    # 3. guard: если остались снапшоты-сироты без device_token профиля —
    #    падаем громко ДО смены NOT NULL, чтобы не ловить невнятную ошибку PK.
    orphans = bind.execute(
        sa.text("SELECT count(*) FROM snapshots WHERE device_id IS NULL")
    ).scalar_one()
    if orphans:
        raise RuntimeError(
            f"{orphans} snapshots без device_id: есть профили со снапшотами, "
            "но без device_token. Разберись вручную перед NOT NULL."
        )

    # 4. сделать NOT NULL
    op.alter_column("snapshots", "device_id", existing_type=sa.BigInteger(), nullable=False)

    # 5. FK + сменить PK
    op.create_foreign_key(
        "fk_snapshots_device", "snapshots", "device_tokens", ["device_id"], ["id"],
        ondelete="CASCADE",
    )
    op.drop_constraint("pk_snapshots", "snapshots", type_="primary")
    op.create_primary_key("pk_snapshots", "snapshots", ["user_id", "device_id", "hour_bucket"])


def downgrade() -> None:
    op.drop_constraint("pk_snapshots", "snapshots", type_="primary")
    op.create_primary_key("pk_snapshots", "snapshots", ["user_id", "hour_bucket"])
    op.drop_constraint("fk_snapshots_device", "snapshots", type_="foreignkey")
    op.drop_column("snapshots", "device_id")
```

- [ ] **Step 5: Обновить роутер снапшотов**

Заменить `src/aiuse/routers/snapshots.py`:

```python
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from aiuse.auth import bearer_device
from aiuse.db import get_session
from aiuse.models import DeviceToken, Snapshot
from aiuse.schemas import SnapshotsBatch, SnapshotsResponse

router = APIRouter(prefix="/snapshots", tags=["snapshots"])


@router.post("", response_model=SnapshotsResponse)
async def upsert_snapshots(
    payload: SnapshotsBatch,
    device: DeviceToken = Depends(bearer_device),
    session: AsyncSession = Depends(get_session),
) -> SnapshotsResponse:
    profile = device.profile
    if not (profile.sharing_enabled or profile.global_opt_in):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="sharing is disabled for this profile",
        )

    rows = [
        {
            "user_id": profile.id,
            "device_id": device.id,
            "hour_bucket": item.hour_bucket.replace(minute=0, second=0, microsecond=0),
            "tokens_input": item.tokens_input,
            "tokens_output": item.tokens_output,
        }
        for item in payload.snapshots
    ]

    stmt = insert(Snapshot).values(rows)
    stmt = stmt.on_conflict_do_update(
        index_elements=["user_id", "device_id", "hour_bucket"],
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

- [ ] **Step 6: Запустить multi-device тест + регрессию снапшотов/лидерборда**

Run: `cd ../ai-stats-api && uv run pytest tests/test_devices.py tests/test_snapshots.py tests/test_leaderboard.py -v`
Expected: PASS. Лидерборд уже группирует по `Profile.id` и суммирует все строки `Snapshot` — добавление `device_id` суммируется автоматически, логику не трогаем.

- [ ] **Step 7: Commit**

```bash
cd ../ai-stats-api
git add src/aiuse/models.py src/aiuse/routers/snapshots.py alembic/versions/009_snapshots_device_id.py tests/test_devices.py
git commit -m "feat(snapshots): device_id и суммирование по устройствам для multi-device"
```

---

## Task 10: Публичный глобальный лидерборд

**Files:**
- Modify: `src/aiuse/schemas.py`
- Create: `src/aiuse/routers/global_leaderboard.py`
- Modify: `src/aiuse/main.py`
- Create: `tests/test_global_leaderboard.py`

- [ ] **Step 1: Схема ответа**

В `src/aiuse/schemas.py` добавить:

```python
class GlobalLeaderboardEntry(BaseModel):
    friend_code: str
    display_name: str
    rank: int
    tokens_total: int


class GlobalLeaderboardResponse(BaseModel):
    period: str
    as_of: datetime
    entries: list[GlobalLeaderboardEntry]
```

- [ ] **Step 2: Падающий тест — публичный, только global_opt_in, суммирует устройства**

Создать `tests/test_global_leaderboard.py`:

```python
from datetime import UTC, datetime


async def _opted_in_profile(client, name, tokens):
    created = (await client.post("/api/profiles", json={"display_name": name})).json()
    headers = {"Authorization": f"Bearer {created['api_secret']}"}
    await client.patch("/api/profiles/me", json={"global_opt_in": True}, headers=headers)
    hour = datetime(2026, 6, 3, 9, 0, 0, tzinfo=UTC).isoformat()
    await client.post(
        "/api/snapshots",
        json={"snapshots": [{"hour_bucket": hour, "tokens_input": tokens, "tokens_output": 0}]},
        headers=headers,
    )
    return created


async def test_global_leaderboard_public_and_opt_in_only(client):
    await _opted_in_profile(client, "Top", 5000)
    await _opted_in_profile(client, "Mid", 1000)
    # профиль БЕЗ opt-in не должен попасть
    hidden = (await client.post("/api/profiles", json={"display_name": "Hidden"})).json()
    await client.patch(
        "/api/profiles/me",
        json={"sharing_enabled": True},
        headers={"Authorization": f"Bearer {hidden['api_secret']}"},
    )

    # БЕЗ Authorization — публичный доступ
    resp = await client.get("/api/global-leaderboard", params={"period": "month"})

    assert resp.status_code == 200
    entries = resp.json()["entries"]
    names = [e["display_name"] for e in entries]
    assert "Hidden" not in names
    assert names[0] == "Top"
    assert entries[0]["rank"] == 1
    assert entries[0]["tokens_total"] == 5000
```

- [ ] **Step 3: Запустить — падает**

Run: `cd ../ai-stats-api && uv run pytest tests/test_global_leaderboard.py -v`
Expected: FAIL — 404.

- [ ] **Step 4: Реализовать роутер**

Создать `src/aiuse/routers/global_leaderboard.py`:

```python
from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func as sql_func
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from aiuse.db import get_session
from aiuse.models import Profile, Snapshot
from aiuse.schemas import GlobalLeaderboardEntry, GlobalLeaderboardResponse

router = APIRouter(tags=["global-leaderboard"])

Period = Literal["day", "week", "month", "24h"]

GLOBAL_LIMIT = 100


def _period_cutoff(period: Period, now: datetime) -> datetime:
    if period == "day":
        return now.replace(hour=0, minute=0, second=0, microsecond=0)
    if period == "24h":
        return now - timedelta(hours=24)
    if period == "week":
        return now - timedelta(days=7)
    if period == "month":
        return now - timedelta(days=30)
    raise ValueError(f"unknown period: {period}")


@router.get("/global-leaderboard", response_model=GlobalLeaderboardResponse)
async def get_global_leaderboard(
    period: Period = Query(..., description="day | week | month | 24h"),
    session: AsyncSession = Depends(get_session),
) -> GlobalLeaderboardResponse:
    now = datetime.now(UTC)
    cutoff = _period_cutoff(period, now)

    total_expr = sql_func.coalesce(
        sql_func.sum(Snapshot.tokens_input + Snapshot.tokens_output), 0
    )
    stmt = (
        select(Profile.friend_code, Profile.display_name, total_expr.label("total"))
        .outerjoin(
            Snapshot,
            (Snapshot.user_id == Profile.id) & (Snapshot.hour_bucket >= cutoff),
        )
        .where(Profile.global_opt_in.is_(True))
        .group_by(Profile.id, Profile.friend_code, Profile.display_name)
        .order_by(total_expr.desc())
        .limit(GLOBAL_LIMIT)
    )
    rows = (await session.execute(stmt)).all()

    entries = [
        GlobalLeaderboardEntry(
            friend_code=fc, display_name=name, rank=idx + 1, tokens_total=int(total)
        )
        for idx, (fc, name, total) in enumerate(rows)
    ]
    return GlobalLeaderboardResponse(period=period, as_of=now, entries=entries)
```

- [ ] **Step 5: Подключить в main.py**

В `src/aiuse/main.py`:

```python
from aiuse.routers import (
    auth,
    avatars,
    blocks,
    friends,
    global_leaderboard,
    health,
    leaderboard,
    profiles,
    snapshots,
)
```

```python
app.include_router(global_leaderboard.router, prefix="/api")
```

- [ ] **Step 6: Запустить — проходит**

Run: `cd ../ai-stats-api && uv run pytest tests/test_global_leaderboard.py -v`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
cd ../ai-stats-api
git add src/aiuse/schemas.py src/aiuse/routers/global_leaderboard.py src/aiuse/main.py tests/test_global_leaderboard.py
git commit -m "feat(leaderboard): публичный глобальный лидерборд по global_opt_in"
```

---

## Task 11: Полный прогон, линт, README, деплой-заметки

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Полный прогон тестов**

Run: `cd ../ai-stats-api && uv run pytest -v`
Expected: PASS — все тесты, включая существующие (profiles, snapshots, friends, blocks, leaderboard, avatars, auth, codes, e2e_smoke).

- [ ] **Step 2: Линт и формат**

Run: `cd ../ai-stats-api && ruff check . && ruff format --check .`
Expected: чисто. Если `ruff format --check` ругается — выполнить `ruff format .` и закоммитить отдельно.

- [ ] **Step 3: Проверить миграции на чистой БД (вне testcontainers)**

Run (если поднят локальный Postgres из docker-compose):
```bash
cd ../ai-stats-api
docker compose up -d postgres
uv run alembic upgrade head
uv run alembic downgrade base
uv run alembic upgrade head
```
Expected: миграции 005→009 применяются и откатываются без ошибок. Если downgrade 009 падает на смене PK — это известный риск Postgres при наличии данных; для пустой БД должно пройти.

- [ ] **Step 4: README — env-переменные и регистрация GitHub OAuth App**

В `README.md` добавить раздел:

```markdown
## OAuth (Фаза 1)

Зарегистрировать GitHub OAuth App (Settings → Developer settings → OAuth Apps):
- Homepage URL: `https://aiuse.popovs.tech`
- Authorization callback URL: `https://aiuse.popovs.tech/api/auth/cb/github`

Env-переменные (на VM в `/opt/aiuse/.env`, не в репозитории):

| Переменная | Назначение |
|---|---|
| `AIUSE_GITHUB_CLIENT_ID` | Client ID OAuth App |
| `AIUSE_GITHUB_CLIENT_SECRET` | Client Secret OAuth App |
| `AIUSE_PUBLIC_BASE_URL` | `https://aiuse.popovs.tech` (для redirect_uri) |
| `AIUSE_APP_CALLBACK_URL` | `burn://auth/callback` (custom scheme клиента) |

Эндпоинты auth-флоу: `GET /api/auth/start`, `GET /api/auth/cb/github`, `POST /api/auth/exchange`.
Публичный глобальный лидерборд: `GET /api/global-leaderboard?period=day|week|month|24h`.
```

- [ ] **Step 5: Commit**

```bash
cd ../ai-stats-api
git add README.md
git commit -m "docs: env-переменные OAuth и эндпоинты фазы 1"
```

- [ ] **Step 6: Деплой (вне TDD-цикла, выполняет человек)**

Деплой по существующему паттерну репо: зарегистрировать OAuth App, прописать env на VM, затем `git push prod main` (post-receive хук разворачивает контейнеры), затем `docker exec aiuse-api alembic upgrade head`. DNS `aiuse.popovs.tech` уже есть с фазы лидерборда — новых DNS/cert изменений не требуется. Проверить: `curl https://aiuse.popovs.tech/api/global-leaderboard?period=day` отдаёт 200 с пустым списком.

---

## Self-Review

**1. Spec coverage** (против `2026-06-03-auth-and-sync-design.md`):

| Раздел спеки | Где реализовано |
|---|---|
| §4.1 `auth_identities`, `device_tokens` | Tasks 2, 3 |
| §4.1 `global_opt_in` | Task 1 |
| §4.2 сервер не хранит github-токен долговременно | Task 8 (удаляется на exchange вместе с `auth_sessions`) |
| §4.3 OAuth-брокер flow (start/cb/exchange, PKCE-challenge) | Tasks 6, 7, 8 |
| §4.4 два режима (новый / линковка) | Task 7 |
| §5.2 `device_id` в снапшотах + суммирование | Task 9 |
| §5.3 device-linking без парных кодов | Task 8 (`test_second_device_same_identity_same_profile`) |
| §6.x GitHub data-токен возвращается клиенту | Task 8 (`github_token` в ответе) |
| §7 публичный глобальный лидерборд | Task 10 |
| §9 identity-конфликт → ошибка | Task 8 (`test_link_conflict_409`) |
| §11 миграция: api_secret→device_tokens, backfill снапшотов | Tasks 2, 9 |

**Не входит в этот план (по дизайну — клиент/другие фазы):** §6.3 выбор scope (сервер уже умеет через `include_private`, но UI — клиентский план 1b), §8 стрики/бейджи (фаза 2+), Google/Yandex провайдеры (фаза 3 — `oauth.py` к этому готов через реестр).

**2. Placeholder scan:** плейсхолдеров нет — весь код приведён целиком, команды с ожидаемым результатом. `friend_code` в callback генерируется с SAVEPOINT-retry (Task 7), как в `create_profile`.

**3. Type consistency:** `hash_token`/`hash_api_secret` (алиас, Task 5) · `generate_device_token` (Task 5, исп. Tasks 8, 9 тесты) · `sha256_hex` (Task 5, исп. Task 8) · `bearer_device` возвращает `DeviceToken` (Task 2, исп. Tasks 9) · `bearer_required` возвращает `Profile` (Task 2, исп. существующими роутерами) · `ProviderIdentity(sub, handle)` (Task 5, исп. Tasks 7) · PK снапшотов `(user_id, device_id, hour_bucket)` согласован между моделью (Task 9 Step 3), миграцией (Step 4) и upsert (Step 5).

**Async-relationship:** `device.profile` грузится через `selectinload` в `find_device_by_token` (Task 2 Step 5) — поэтому синхронный доступ в `bearer_required` и в снапшотах (Task 9 Step 5) безопасен, `MissingGreenlet` не возникает. Тесты Task 2/Task 9 это подтверждают.
