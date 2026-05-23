# Лидерборд v0.3.0 — Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Расширить `ai-stats-api` четырьмя группами endpoints — friends, blocks, leaderboard, avatars — чтобы клиент мог реализовать UI друзей и лидерборда в v0.3.0-client. Schema уже создана (миграции 003 + 004 применены в v0.2.0), endpoint'ы не делались.

**Architecture:** Все endpoints под `/api/` с Bearer auth (как и в v0.2.0). Friendship — симметричная связь одной строкой (CHECK `user_a_id < user_b_id`). Блокировка зашитой реакцией на 404/403 одинаково, чтобы не палить факт блока. Лидерборд — SQL `SUM` snapshot'ов среди (мои друзья + я) с фильтрацией `sharing_enabled = true`. Avatar — `bytea` отдаётся через GET с ETag.

**Tech Stack:** Python 3.12, FastAPI 0.110+, SQLAlchemy 2.0 (async), Postgres 16. Тесты — pytest + httpx + Postgres testcontainer (уже сконфигурирован). Никаких новых dependency.

**Связанные документы:**
- Спек: [`docs/superpowers/specs/2026-05-23-leaderboard-design.md`](../specs/2026-05-23-leaderboard-design.md)
- Backend v0.2.0 (deployed): https://github.com/tsergeytovarov/ai-stats-api
- Backend v0.2.0 plan: [`2026-05-23-leaderboard-v0.2.0-backend.md`](2026-05-23-leaderboard-v0.2.0-backend.md)

---

## File Structure

Работа в `/Users/sergeytovarov/work/ai-stats-api/`. Никаких новых модулей — добавляем 4 router'а к существующим (health, profiles, snapshots).

```
ai-stats-api/
├── src/aiuse/
│   ├── schemas.py              # MODIFY: + DTO для friends/blocks/leaderboard
│   ├── codes.py                # MODIFY: + normalize_friend_code() для случая когда клиент шлёт с дефисами
│   ├── routers/
│   │   ├── friends.py          # NEW: POST/GET/DELETE /api/friends
│   │   ├── blocks.py           # NEW: GET/DELETE /api/blocks
│   │   ├── leaderboard.py      # NEW: GET /api/leaderboard
│   │   └── avatars.py          # NEW: GET /api/avatars/{friend_code}
│   └── main.py                 # MODIFY: include 4 new routers
└── tests/
    ├── test_friends.py         # NEW
    ├── test_blocks.py          # NEW
    ├── test_leaderboard.py     # NEW
    ├── test_avatars.py         # NEW
    └── test_e2e_smoke.py       # MODIFY: добавить Alice→Bob → leaderboard сценарий
```

**Design решения, зафиксированные в плане:**

1. **`GET /api/friends` — только метаданные** (friend_code, display_name, sharing_enabled, added_at). Статистику клиент берёт отдельно через `/api/leaderboard?period=day`. Endpoints orthogonal, два запроса от клиента — это норм.
2. **`GET /api/leaderboard` — без лимита**. Возвращаем все entries (max 101 — 100 друзей + я). Top-N (5/7) клиент режет сам под свой UI.
3. **Avatar доступен любому authenticated юзеру** по friend_code. Это не секрет — мой клиент уже знает friend_code'ы своих друзей.
4. **403 vs 404** на добавление: одинаковое сообщение `{"detail": "friend not found"}` для «нет такого friend_code» и «вы заблокировали друг друга». Не палим блокировки.
5. **Симметрия friendship**: при INSERT нормализуем `(a, b)` → `(min(a,b), max(a,b))`. JOIN'ы для лидерборда — UNION'ом обеих сторон.
6. **ETag для avatar** = sha256(avatar)[:16]. Меняется при PATCH аватарки.

---

## Phase A: Schemas + helpers

### Task 1: Расширить schemas.py для friends/blocks/leaderboard

**Files:**
- Modify: `src/aiuse/schemas.py`

- [ ] **Step 1: Добавить DTO**

В конец `src/aiuse/schemas.py` добавить:

```python
# ── friends ────────────────────────────────────────────────────────────

class AddFriendRequest(BaseModel):
    friend_code: str = Field(..., min_length=1, max_length=20)


class FriendDTO(BaseModel):
    friend_code: str
    display_name: str
    sharing_enabled: bool
    added_at: datetime


class FriendsListResponse(BaseModel):
    friends: list[FriendDTO]


class RemoveFriendRequest(BaseModel):
    block: bool = False


# ── blocks ─────────────────────────────────────────────────────────────

class BlockDTO(BaseModel):
    friend_code: str
    display_name: str
    blocked_at: datetime


class BlocksListResponse(BaseModel):
    blocked: list[BlockDTO]


# ── leaderboard ────────────────────────────────────────────────────────

class LeaderboardEntry(BaseModel):
    friend_code: str
    display_name: str
    rank: int
    tokens_total: int
    is_me: bool


class LeaderboardResponse(BaseModel):
    period: str
    as_of: datetime
    entries: list[LeaderboardEntry]
```

- [ ] **Step 2: Прогнать тесты — старые не сломаны**

```bash
cd /Users/sergeytovarov/work/ai-stats-api
source .venv/bin/activate
pytest -v 2>&1 | tail -5
```

Expected: 35 PASS (v0.2.0 baseline).

- [ ] **Step 3: Коммит**

```bash
git add src/aiuse/schemas.py
git commit -m "feat(api): DTO для friends/blocks/leaderboard endpoints"
```

---

### Task 2: codes.py — normalize_friend_code для входящих запросов

**Files:**
- Modify: `src/aiuse/codes.py`
- Modify: `tests/test_codes.py`

Клиент может прислать `XK7P-3M9Q-2A` (с дефисами, для удобства людей) или `XK7P3M9Q2A`. Сервер должен принимать обе формы.

- [ ] **Step 1: Дописать failing test**

В `tests/test_codes.py` добавить:

```python
@pytest.mark.parametrize(
    "input_str,expected",
    [
        ("XK7P-3M9Q-2A", "XK7P3M9Q2A"),
        ("xk7p-3m9q-2a", "XK7P3M9Q2A"),
        ("  XK7P-3M9Q-2A  ", "XK7P3M9Q2A"),
        ("XK7P3M9Q2A", "XK7P3M9Q2A"),
    ],
)
def test_normalize_friend_code(input_str: str, expected: str):
    from aiuse.codes import normalize_friend_code
    assert normalize_friend_code(input_str) == expected
```

- [ ] **Step 2: Прогнать — упадёт**

```bash
pytest tests/test_codes.py::test_normalize_friend_code -v 2>&1 | tail -5
```

Expected: ImportError на `normalize_friend_code`.

- [ ] **Step 3: Имплементация**

В `src/aiuse/codes.py`:

```python
import re


def normalize_friend_code(raw: str) -> str:
    """Убираем дефисы/пробелы, приводим к верхнему регистру. Не валидируем алфавит/длину."""
    return re.sub(r"[\s\-]+", "", raw).upper()
```

- [ ] **Step 4: Прогнать — пройдёт**

```bash
pytest tests/test_codes.py::test_normalize_friend_code -v 2>&1 | tail -5
```

Expected: 4 PASS.

- [ ] **Step 5: Коммит**

```bash
git add src/aiuse/codes.py tests/test_codes.py
git commit -m "feat(codes): normalize_friend_code для входящих запросов"
```

---

## Phase B: Friends endpoints

### Task 3: POST /api/friends — добавить друга

**Files:**
- Create: `src/aiuse/routers/friends.py`
- Modify: `src/aiuse/main.py`
- Create: `tests/test_friends.py`

- [ ] **Step 1: Написать failing тесты**

`tests/test_friends.py`:

```python
from __future__ import annotations

from httpx import AsyncClient


async def _register(client: AsyncClient, name: str = "X") -> tuple[str, str, int]:
    """Возвращает (api_secret, friend_code, server_user_id)."""
    r = await client.post("/api/profiles", json={"display_name": name})
    body = r.json()
    return body["api_secret"], body["friend_code"], body["server_user_id"]


async def test_add_friend_creates_symmetric_link(client: AsyncClient):
    a_secret, a_code, _ = await _register(client, "Alice")
    b_secret, b_code, _ = await _register(client, "Bob")

    # Alice добавляет Bob по коду
    r = await client.post(
        "/api/friends",
        json={"friend_code": b_code},
        headers={"Authorization": f"Bearer {a_secret}"},
    )
    assert r.status_code == 201
    body = r.json()
    assert body["friend_code"] == b_code
    assert body["display_name"] == "Bob"

    # Bob видит Alice в своём списке
    r2 = await client.get(
        "/api/friends", headers={"Authorization": f"Bearer {b_secret}"}
    )
    assert r2.status_code == 200
    friends = r2.json()["friends"]
    assert any(f["friend_code"] == a_code for f in friends)


async def test_add_friend_unknown_code_returns_404(client: AsyncClient):
    a_secret, _, _ = await _register(client, "Alice")
    r = await client.post(
        "/api/friends",
        json={"friend_code": "ZZZZZZZZZZ"},
        headers={"Authorization": f"Bearer {a_secret}"},
    )
    assert r.status_code == 404


async def test_add_friend_self_returns_400(client: AsyncClient):
    a_secret, a_code, _ = await _register(client, "Alice")
    r = await client.post(
        "/api/friends",
        json={"friend_code": a_code},
        headers={"Authorization": f"Bearer {a_secret}"},
    )
    assert r.status_code == 400


async def test_add_friend_already_friends_returns_409(client: AsyncClient):
    a_secret, _, _ = await _register(client, "Alice")
    _, b_code, _ = await _register(client, "Bob")

    await client.post(
        "/api/friends",
        json={"friend_code": b_code},
        headers={"Authorization": f"Bearer {a_secret}"},
    )
    r2 = await client.post(
        "/api/friends",
        json={"friend_code": b_code},
        headers={"Authorization": f"Bearer {a_secret}"},
    )
    assert r2.status_code == 409


async def test_add_friend_accepts_hyphens_in_code(client: AsyncClient):
    a_secret, _, _ = await _register(client, "Alice")
    _, b_code, _ = await _register(client, "Bob")
    # Имитируем UI который шлёт "XK7P-3M9Q-2A"
    hyphenated = f"{b_code[:4]}-{b_code[4:8]}-{b_code[8:]}"
    r = await client.post(
        "/api/friends",
        json={"friend_code": hyphenated},
        headers={"Authorization": f"Bearer {a_secret}"},
    )
    assert r.status_code == 201
```

- [ ] **Step 2: Прогнать — упадут на 404 endpoint**

```bash
pytest tests/test_friends.py -v 2>&1 | tail -10
```

Expected: 5 FAIL на 404 (endpoint не существует).

- [ ] **Step 3: Создать роутер**

`src/aiuse/routers/friends.py`:

```python
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from aiuse.auth import bearer_required
from aiuse.codes import normalize_friend_code
from aiuse.db import get_session
from aiuse.models import Block, Friendship, Profile
from aiuse.schemas import (
    AddFriendRequest,
    FriendDTO,
    FriendsListResponse,
    RemoveFriendRequest,
)

router = APIRouter(prefix="/friends", tags=["friends"])

MAX_FRIENDS = 100


@router.post("", response_model=FriendDTO, status_code=status.HTTP_201_CREATED)
async def add_friend(
    payload: AddFriendRequest,
    me: Profile = Depends(bearer_required),
    session: AsyncSession = Depends(get_session),
) -> FriendDTO:
    target_code = normalize_friend_code(payload.friend_code)

    # 1. Нельзя добавить себя
    if target_code == me.friend_code:
        raise HTTPException(status_code=400, detail="cannot add yourself")

    # 2. Ищем профиль по friend_code
    target = (
        await session.execute(select(Profile).where(Profile.friend_code == target_code))
    ).scalar_one_or_none()
    if target is None:
        raise HTTPException(status_code=404, detail="friend not found")

    # 3. Проверка blocks — одинаковый ответ для "блок" и "не существует",
    #    чтобы не палить факт блокировки.
    block_check = await session.execute(
        select(Block).where(
            or_(
                (Block.blocker_id == me.id) & (Block.blocked_id == target.id),
                (Block.blocker_id == target.id) & (Block.blocked_id == me.id),
            )
        )
    )
    if block_check.scalar_one_or_none() is not None:
        raise HTTPException(status_code=404, detail="friend not found")

    # 4. Лимит на количество друзей
    from sqlalchemy import func as sql_func

    count_stmt = (
        select(sql_func.count())
        .select_from(Friendship)
        .where(or_(Friendship.user_a_id == me.id, Friendship.user_b_id == me.id))
    )
    current = (await session.execute(count_stmt)).scalar_one()
    if current >= MAX_FRIENDS:
        raise HTTPException(status_code=409, detail=f"friend limit reached ({MAX_FRIENDS})")

    # 5. INSERT нормализованной связи (min(id), max(id)) — CHECK constraint требует
    user_a_id, user_b_id = sorted((me.id, target.id))
    existing = await session.execute(
        select(Friendship).where(
            Friendship.user_a_id == user_a_id, Friendship.user_b_id == user_b_id
        )
    )
    if existing.scalar_one_or_none() is not None:
        raise HTTPException(status_code=409, detail="already friends")

    friendship = Friendship(user_a_id=user_a_id, user_b_id=user_b_id)
    session.add(friendship)
    await session.commit()
    await session.refresh(friendship)

    return FriendDTO(
        friend_code=target.friend_code,
        display_name=target.display_name,
        sharing_enabled=target.sharing_enabled,
        added_at=friendship.created_at,
    )


@router.get("", response_model=FriendsListResponse)
async def list_friends(
    me: Profile = Depends(bearer_required),
    session: AsyncSession = Depends(get_session),
) -> FriendsListResponse:
    # Все friendships где я являюсь user_a или user_b → берём "другую" сторону.
    stmt = (
        select(Friendship, Profile)
        .join(
            Profile,
            or_(
                (Friendship.user_a_id == Profile.id) & (Friendship.user_b_id == me.id),
                (Friendship.user_b_id == Profile.id) & (Friendship.user_a_id == me.id),
            ),
        )
        .where(or_(Friendship.user_a_id == me.id, Friendship.user_b_id == me.id))
        .order_by(Friendship.created_at.desc())
    )
    rows = (await session.execute(stmt)).all()
    return FriendsListResponse(
        friends=[
            FriendDTO(
                friend_code=profile.friend_code,
                display_name=profile.display_name,
                sharing_enabled=profile.sharing_enabled,
                added_at=friendship.created_at,
            )
            for (friendship, profile) in rows
        ]
    )
```

- [ ] **Step 4: Подключить роутер в main.py**

В `src/aiuse/main.py`:

```python
from aiuse.routers import friends, health, profiles, snapshots

app = FastAPI(title="aiuse", version="0.3.0")
app.include_router(health.router, prefix="/api")
app.include_router(profiles.router, prefix="/api")
app.include_router(snapshots.router, prefix="/api")
app.include_router(friends.router, prefix="/api")
```

- [ ] **Step 5: Прогнать — все 5 должны пройти**

```bash
pytest tests/test_friends.py -v 2>&1 | tail -10
```

Expected: 5 PASS.

- [ ] **Step 6: Коммит**

```bash
git add src/aiuse/routers/friends.py src/aiuse/main.py tests/test_friends.py
git commit -m "feat(api): POST /api/friends + GET /api/friends — симметричная дружба"
```

---

### Task 4: DELETE /api/friends/{friend_code} — удалить связь + опционально blocked

**Files:**
- Modify: `src/aiuse/routers/friends.py`
- Modify: `tests/test_friends.py`

- [ ] **Step 1: Добавить failing тесты**

В конец `tests/test_friends.py`:

```python
async def test_delete_friend_removes_link(client: AsyncClient):
    a_secret, _, _ = await _register(client, "Alice")
    b_secret, b_code, _ = await _register(client, "Bob")

    await client.post(
        "/api/friends",
        json={"friend_code": b_code},
        headers={"Authorization": f"Bearer {a_secret}"},
    )
    r = await client.request(
        "DELETE",
        f"/api/friends/{b_code}",
        json={"block": False},
        headers={"Authorization": f"Bearer {a_secret}"},
    )
    assert r.status_code == 204

    # Связь пропала у обеих сторон
    rb = await client.get("/api/friends", headers={"Authorization": f"Bearer {b_secret}"})
    assert len(rb.json()["friends"]) == 0


async def test_delete_friend_with_block_returns_404_on_reAdd(client: AsyncClient):
    """Alice блокирует Bob → Bob не может снова добавить Alice (видит 404)."""
    a_secret, a_code, _ = await _register(client, "Alice")
    b_secret, b_code, _ = await _register(client, "Bob")

    await client.post(
        "/api/friends",
        json={"friend_code": b_code},
        headers={"Authorization": f"Bearer {a_secret}"},
    )
    # Alice удаляет с block=true
    r = await client.request(
        "DELETE",
        f"/api/friends/{b_code}",
        json={"block": True},
        headers={"Authorization": f"Bearer {a_secret}"},
    )
    assert r.status_code == 204

    # Bob пытается добавить Alice заново → 404 (одинаковое сообщение)
    r2 = await client.post(
        "/api/friends",
        json={"friend_code": a_code},
        headers={"Authorization": f"Bearer {b_secret}"},
    )
    assert r2.status_code == 404


async def test_delete_friend_nonexistent_returns_404(client: AsyncClient):
    a_secret, _, _ = await _register(client, "Alice")
    r = await client.request(
        "DELETE",
        "/api/friends/ZZZZZZZZZZ",
        json={"block": False},
        headers={"Authorization": f"Bearer {a_secret}"},
    )
    assert r.status_code == 404
```

- [ ] **Step 2: Прогнать — упадут**

```bash
pytest tests/test_friends.py -v -k "delete" 2>&1 | tail -10
```

Expected: 3 FAIL на 405/404.

- [ ] **Step 3: Добавить endpoint в роутер**

В `src/aiuse/routers/friends.py`:

```python
from fastapi import Response


@router.delete("/{friend_code}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_friend(
    friend_code: str,
    payload: RemoveFriendRequest,
    me: Profile = Depends(bearer_required),
    session: AsyncSession = Depends(get_session),
) -> Response:
    target_code = normalize_friend_code(friend_code)
    target = (
        await session.execute(select(Profile).where(Profile.friend_code == target_code))
    ).scalar_one_or_none()
    if target is None:
        raise HTTPException(status_code=404, detail="friend not found")

    # Удалить связь (если есть) — нормализуем (a, b) → (min, max)
    user_a_id, user_b_id = sorted((me.id, target.id))
    from sqlalchemy import delete as sql_delete

    result = await session.execute(
        sql_delete(Friendship).where(
            Friendship.user_a_id == user_a_id, Friendship.user_b_id == user_b_id
        )
    )
    # Опциональный block: INSERT в blocks (blocker=me, blocked=target)
    if payload.block:
        # ON CONFLICT DO NOTHING — повторный блок норм
        from sqlalchemy.dialects.postgresql import insert as pg_insert

        stmt = pg_insert(Block).values(blocker_id=me.id, blocked_id=target.id)
        stmt = stmt.on_conflict_do_nothing(index_elements=["blocker_id", "blocked_id"])
        await session.execute(stmt)

    await session.commit()

    # Если связи не было и блок не запрошен — 404 (нечего удалять)
    if result.rowcount == 0 and not payload.block:
        raise HTTPException(status_code=404, detail="not friends")

    return Response(status_code=status.HTTP_204_NO_CONTENT)
```

- [ ] **Step 4: Прогнать**

```bash
pytest tests/test_friends.py -v 2>&1 | tail -10
```

Expected: 8 PASS.

- [ ] **Step 5: Коммит**

```bash
git add src/aiuse/routers/friends.py tests/test_friends.py
git commit -m "feat(api): DELETE /api/friends/{code} с опциональным block"
```

---

## Phase C: Blocks endpoints

### Task 5: GET /api/blocks + DELETE /api/blocks/{code}

**Files:**
- Create: `src/aiuse/routers/blocks.py`
- Modify: `src/aiuse/main.py`
- Create: `tests/test_blocks.py`

- [ ] **Step 1: Написать failing тесты**

`tests/test_blocks.py`:

```python
from __future__ import annotations

from httpx import AsyncClient


async def _register(client: AsyncClient, name: str = "X") -> tuple[str, str, int]:
    r = await client.post("/api/profiles", json={"display_name": name})
    body = r.json()
    return body["api_secret"], body["friend_code"], body["server_user_id"]


async def test_block_list_initially_empty(client: AsyncClient):
    a_secret, _, _ = await _register(client, "Alice")
    r = await client.get("/api/blocks", headers={"Authorization": f"Bearer {a_secret}"})
    assert r.status_code == 200
    assert r.json() == {"blocked": []}


async def test_block_appears_in_list_after_delete_with_block(client: AsyncClient):
    a_secret, _, _ = await _register(client, "Alice")
    _, b_code, _ = await _register(client, "Bob")

    # Alice добавляет и сразу блокирует Bob (без существующей связи это просто блок)
    r = await client.request(
        "DELETE",
        f"/api/friends/{b_code}",
        json={"block": True},
        headers={"Authorization": f"Bearer {a_secret}"},
    )
    assert r.status_code == 204

    r2 = await client.get("/api/blocks", headers={"Authorization": f"Bearer {a_secret}"})
    assert r2.status_code == 200
    blocked = r2.json()["blocked"]
    assert len(blocked) == 1
    assert blocked[0]["friend_code"] == b_code
    assert blocked[0]["display_name"] == "Bob"


async def test_unblock_removes_from_list(client: AsyncClient):
    a_secret, _, _ = await _register(client, "Alice")
    _, b_code, _ = await _register(client, "Bob")
    await client.request(
        "DELETE",
        f"/api/friends/{b_code}",
        json={"block": True},
        headers={"Authorization": f"Bearer {a_secret}"},
    )

    r = await client.delete(
        f"/api/blocks/{b_code}",
        headers={"Authorization": f"Bearer {a_secret}"},
    )
    assert r.status_code == 204

    r2 = await client.get("/api/blocks", headers={"Authorization": f"Bearer {a_secret}"})
    assert r2.json() == {"blocked": []}


async def test_unblock_nonexistent_returns_404(client: AsyncClient):
    a_secret, _, _ = await _register(client, "Alice")
    r = await client.delete(
        "/api/blocks/ZZZZZZZZZZ",
        headers={"Authorization": f"Bearer {a_secret}"},
    )
    assert r.status_code == 404
```

- [ ] **Step 2: Прогнать — упадут**

- [ ] **Step 3: Создать роутер**

`src/aiuse/routers/blocks.py`:

```python
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import delete as sql_delete
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from aiuse.auth import bearer_required
from aiuse.codes import normalize_friend_code
from aiuse.db import get_session
from aiuse.models import Block, Profile
from aiuse.schemas import BlockDTO, BlocksListResponse

router = APIRouter(prefix="/blocks", tags=["blocks"])


@router.get("", response_model=BlocksListResponse)
async def list_blocks(
    me: Profile = Depends(bearer_required),
    session: AsyncSession = Depends(get_session),
) -> BlocksListResponse:
    stmt = (
        select(Block, Profile)
        .join(Profile, Profile.id == Block.blocked_id)
        .where(Block.blocker_id == me.id)
        .order_by(Block.created_at.desc())
    )
    rows = (await session.execute(stmt)).all()
    return BlocksListResponse(
        blocked=[
            BlockDTO(
                friend_code=profile.friend_code,
                display_name=profile.display_name,
                blocked_at=block.created_at,
            )
            for (block, profile) in rows
        ]
    )


@router.delete("/{friend_code}", status_code=status.HTTP_204_NO_CONTENT)
async def unblock(
    friend_code: str,
    me: Profile = Depends(bearer_required),
    session: AsyncSession = Depends(get_session),
) -> Response:
    target_code = normalize_friend_code(friend_code)
    target = (
        await session.execute(select(Profile).where(Profile.friend_code == target_code))
    ).scalar_one_or_none()
    if target is None:
        raise HTTPException(status_code=404, detail="not blocked")

    result = await session.execute(
        sql_delete(Block).where(
            Block.blocker_id == me.id, Block.blocked_id == target.id
        )
    )
    await session.commit()
    if result.rowcount == 0:
        raise HTTPException(status_code=404, detail="not blocked")
    return Response(status_code=status.HTTP_204_NO_CONTENT)
```

- [ ] **Step 4: Подключить в main.py**

```python
from aiuse.routers import blocks, friends, health, profiles, snapshots

app.include_router(blocks.router, prefix="/api")
```

- [ ] **Step 5: Прогнать**

```bash
pytest tests/test_blocks.py -v 2>&1 | tail -10
```

Expected: 4 PASS.

- [ ] **Step 6: Коммит**

```bash
git add src/aiuse/routers/blocks.py src/aiuse/main.py tests/test_blocks.py
git commit -m "feat(api): GET /api/blocks + DELETE /api/blocks/{code}"
```

---

## Phase D: Leaderboard

### Task 6: GET /api/leaderboard

**Files:**
- Create: `src/aiuse/routers/leaderboard.py`
- Modify: `src/aiuse/main.py`
- Create: `tests/test_leaderboard.py`

- [ ] **Step 1: Failing тесты**

`tests/test_leaderboard.py`:

```python
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from httpx import AsyncClient


async def _register(client: AsyncClient, name: str) -> tuple[str, str, int]:
    r = await client.post("/api/profiles", json={"display_name": name})
    body = r.json()
    return body["api_secret"], body["friend_code"], body["server_user_id"]


async def _send_snapshot(client: AsyncClient, secret: str, hour: str, tin: int, tout: int):
    return await client.post(
        "/api/snapshots",
        json={"snapshots": [{"hour_bucket": hour, "tokens_input": tin, "tokens_output": tout}]},
        headers={"Authorization": f"Bearer {secret}"},
    )


async def _add_friend(client: AsyncClient, secret: str, code: str):
    return await client.post(
        "/api/friends",
        json={"friend_code": code},
        headers={"Authorization": f"Bearer {secret}"},
    )


def _hour_iso(hours_ago: int) -> str:
    dt = datetime.now(timezone.utc) - timedelta(hours=hours_ago)
    return dt.replace(minute=0, second=0, microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ")


async def test_leaderboard_contains_me_and_friends_sorted(client: AsyncClient):
    a_secret, a_code, _ = await _register(client, "Alice")
    b_secret, b_code, _ = await _register(client, "Bob")
    c_secret, c_code, _ = await _register(client, "Charlie")

    await _add_friend(client, a_secret, b_code)
    await _add_friend(client, a_secret, c_code)

    # Charlie: 1000 (топ)
    await _send_snapshot(client, c_secret, _hour_iso(2), 700, 300)
    # Bob: 500
    await _send_snapshot(client, b_secret, _hour_iso(3), 300, 200)
    # Alice: 100
    await _send_snapshot(client, a_secret, _hour_iso(1), 60, 40)

    r = await client.get(
        "/api/leaderboard?period=day",
        headers={"Authorization": f"Bearer {a_secret}"},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["period"] == "day"
    entries = body["entries"]
    assert len(entries) == 3
    assert entries[0]["display_name"] == "Charlie"
    assert entries[0]["rank"] == 1
    assert entries[0]["tokens_total"] == 1000
    assert entries[1]["display_name"] == "Bob"
    assert entries[2]["display_name"] == "Alice"
    assert entries[2]["is_me"] is True
    assert entries[0]["is_me"] is False


async def test_leaderboard_excludes_users_with_sharing_disabled(client: AsyncClient):
    a_secret, _, _ = await _register(client, "Alice")
    b_secret, b_code, _ = await _register(client, "Bob")

    await _add_friend(client, a_secret, b_code)
    # Bob положил данные но выключил шаринг
    await _send_snapshot(client, b_secret, _hour_iso(2), 500, 500)
    await client.patch(
        "/api/profiles/me",
        json={"sharing_enabled": False},
        headers={"Authorization": f"Bearer {b_secret}"},
    )

    r = await client.get(
        "/api/leaderboard?period=day",
        headers={"Authorization": f"Bearer {a_secret}"},
    )
    body = r.json()
    codes = [e["friend_code"] for e in body["entries"]]
    assert b_code not in codes


async def test_leaderboard_blocked_when_sharing_disabled_for_me(client: AsyncClient):
    a_secret, _, _ = await _register(client, "Alice")
    await client.patch(
        "/api/profiles/me",
        json={"sharing_enabled": False},
        headers={"Authorization": f"Bearer {a_secret}"},
    )
    r = await client.get(
        "/api/leaderboard?period=day",
        headers={"Authorization": f"Bearer {a_secret}"},
    )
    assert r.status_code == 403


async def test_leaderboard_supports_all_periods(client: AsyncClient):
    a_secret, _, _ = await _register(client, "Alice")
    for period in ["day", "week", "month", "24h"]:
        r = await client.get(
            f"/api/leaderboard?period={period}",
            headers={"Authorization": f"Bearer {a_secret}"},
        )
        assert r.status_code == 200, period


async def test_leaderboard_invalid_period_returns_422(client: AsyncClient):
    a_secret, _, _ = await _register(client, "Alice")
    r = await client.get(
        "/api/leaderboard?period=year",
        headers={"Authorization": f"Bearer {a_secret}"},
    )
    assert r.status_code == 422
```

- [ ] **Step 2: Прогнать — упадут**

- [ ] **Step 3: Создать роутер**

`src/aiuse/routers/leaderboard.py`:

```python
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func as sql_func
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from aiuse.auth import bearer_required
from aiuse.db import get_session
from aiuse.models import Friendship, Profile, Snapshot
from aiuse.schemas import LeaderboardEntry, LeaderboardResponse

router = APIRouter(prefix="/leaderboard", tags=["leaderboard"])

Period = Literal["day", "week", "month", "24h"]


def _period_cutoff(period: Period, now: datetime) -> datetime:
    """Возвращает нижнюю границу hour_bucket."""
    if period == "day":
        return now.replace(hour=0, minute=0, second=0, microsecond=0)
    if period == "24h":
        return now - timedelta(hours=24)
    if period == "week":
        return now - timedelta(days=7)
    if period == "month":
        return now - timedelta(days=30)
    raise ValueError(f"unknown period: {period}")


@router.get("", response_model=LeaderboardResponse)
async def get_leaderboard(
    period: Period = Query(..., description="day | week | month | 24h"),
    me: Profile = Depends(bearer_required),
    session: AsyncSession = Depends(get_session),
) -> LeaderboardResponse:
    # 1. sharing_enabled = false → не показываем (free-rider protection)
    if not me.sharing_enabled:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="leaderboard is hidden while sharing is disabled",
        )

    now = datetime.now(timezone.utc)
    cutoff = _period_cutoff(period, now)

    # 2. ID юзеров для агрегации: все мои friend'ы + я
    friend_ids_stmt = select(
        sql_func.coalesce(
            sql_func.nullif(Friendship.user_a_id, me.id), Friendship.user_b_id
        ).label("friend_id")
    ).where(or_(Friendship.user_a_id == me.id, Friendship.user_b_id == me.id))
    friend_ids = [row[0] for row in (await session.execute(friend_ids_stmt)).all()]
    visible_ids = friend_ids + [me.id]

    # 3. SUM(tokens_input + tokens_output) GROUP BY user_id
    #    JOIN profiles чтобы фильтровать sharing_enabled
    stmt = (
        select(
            Profile.id,
            Profile.friend_code,
            Profile.display_name,
            sql_func.coalesce(
                sql_func.sum(Snapshot.tokens_input + Snapshot.tokens_output), 0
            ).label("total"),
        )
        .outerjoin(
            Snapshot,
            (Snapshot.user_id == Profile.id) & (Snapshot.hour_bucket >= cutoff),
        )
        .where(Profile.id.in_(visible_ids), Profile.sharing_enabled.is_(True))
        .group_by(Profile.id, Profile.friend_code, Profile.display_name)
        .order_by(sql_func.coalesce(
            sql_func.sum(Snapshot.tokens_input + Snapshot.tokens_output), 0
        ).desc())
    )
    rows = (await session.execute(stmt)).all()

    entries = [
        LeaderboardEntry(
            friend_code=fc,
            display_name=name,
            rank=idx + 1,
            tokens_total=int(total),
            is_me=(uid == me.id),
        )
        for idx, (uid, fc, name, total) in enumerate(rows)
    ]
    return LeaderboardResponse(period=period, as_of=now, entries=entries)
```

- [ ] **Step 4: Подключить в main.py**

```python
from aiuse.routers import blocks, friends, health, leaderboard, profiles, snapshots

app.include_router(leaderboard.router, prefix="/api")
```

- [ ] **Step 5: Прогнать**

```bash
pytest tests/test_leaderboard.py -v 2>&1 | tail -15
```

Expected: 5 PASS.

- [ ] **Step 6: Коммит**

```bash
git add src/aiuse/routers/leaderboard.py src/aiuse/main.py tests/test_leaderboard.py
git commit -m "feat(api): GET /api/leaderboard — SUM по friends+me с фильтрацией sharing"
```

---

## Phase E: Avatars

### Task 7: GET /api/avatars/{friend_code}

**Files:**
- Create: `src/aiuse/routers/avatars.py`
- Modify: `src/aiuse/main.py`
- Create: `tests/test_avatars.py`

- [ ] **Step 1: Failing тесты**

`tests/test_avatars.py`:

```python
from __future__ import annotations

import base64

from httpx import AsyncClient


async def _register_with_avatar(client: AsyncClient, name: str, avatar: bytes, mime: str) -> tuple[str, str]:
    r = await client.post(
        "/api/profiles",
        json={
            "display_name": name,
            "avatar_b64": base64.b64encode(avatar).decode(),
            "avatar_mime": mime,
        },
    )
    body = r.json()
    return body["api_secret"], body["friend_code"]


async def test_get_avatar_returns_bytes_with_content_type(client: AsyncClient):
    fake_jpeg = b"\xff\xd8\xff" + b"\x00" * 100
    a_secret, _ = await _register_with_avatar(client, "Alice", fake_jpeg, "image/jpeg")
    _, b_code = await _register_with_avatar(client, "Bob", fake_jpeg, "image/jpeg")

    r = await client.get(
        f"/api/avatars/{b_code}",
        headers={"Authorization": f"Bearer {a_secret}"},
    )
    assert r.status_code == 200
    assert r.headers["content-type"] == "image/jpeg"
    assert r.content == fake_jpeg
    assert r.headers.get("etag") is not None


async def test_get_avatar_etag_changes_when_avatar_changes(client: AsyncClient):
    fake_jpeg = b"\xff\xd8\xff" + b"\x00" * 100
    a_secret, _ = await _register_with_avatar(client, "Alice", fake_jpeg, "image/jpeg")
    b_secret, b_code = await _register_with_avatar(client, "Bob", fake_jpeg, "image/jpeg")

    r1 = await client.get(
        f"/api/avatars/{b_code}", headers={"Authorization": f"Bearer {a_secret}"}
    )
    etag1 = r1.headers["etag"]

    # Bob меняет аватарку
    new_avatar = b"\x89PNG\r\n\x1a\n" + b"\x00" * 100
    await client.patch(
        "/api/profiles/me",
        json={
            "avatar_b64": base64.b64encode(new_avatar).decode(),
            "avatar_mime": "image/png",
        },
        headers={"Authorization": f"Bearer {b_secret}"},
    )

    r2 = await client.get(
        f"/api/avatars/{b_code}", headers={"Authorization": f"Bearer {a_secret}"}
    )
    assert r2.headers["etag"] != etag1
    assert r2.headers["content-type"] == "image/png"


async def test_get_avatar_returns_304_on_matching_etag(client: AsyncClient):
    fake_jpeg = b"\xff\xd8\xff" + b"\x00" * 100
    a_secret, _ = await _register_with_avatar(client, "Alice", fake_jpeg, "image/jpeg")
    _, b_code = await _register_with_avatar(client, "Bob", fake_jpeg, "image/jpeg")

    r1 = await client.get(
        f"/api/avatars/{b_code}", headers={"Authorization": f"Bearer {a_secret}"}
    )
    etag = r1.headers["etag"]

    r2 = await client.get(
        f"/api/avatars/{b_code}",
        headers={"Authorization": f"Bearer {a_secret}", "If-None-Match": etag},
    )
    assert r2.status_code == 304


async def test_get_avatar_404_when_no_avatar(client: AsyncClient):
    a_secret, _, _ = await _register_no_avatar(client, "Alice")
    _, b_code, _ = await _register_no_avatar(client, "Bob")
    r = await client.get(
        f"/api/avatars/{b_code}", headers={"Authorization": f"Bearer {a_secret}"}
    )
    assert r.status_code == 404


async def _register_no_avatar(client: AsyncClient, name: str) -> tuple[str, str, int]:
    r = await client.post("/api/profiles", json={"display_name": name})
    body = r.json()
    return body["api_secret"], body["friend_code"], body["server_user_id"]


async def test_get_avatar_404_when_friend_code_unknown(client: AsyncClient):
    a_secret, _, _ = await _register_no_avatar(client, "Alice")
    r = await client.get(
        "/api/avatars/ZZZZZZZZZZ",
        headers={"Authorization": f"Bearer {a_secret}"},
    )
    assert r.status_code == 404
```

- [ ] **Step 2: Прогнать — упадут**

- [ ] **Step 3: Создать роутер**

`src/aiuse/routers/avatars.py`:

```python
from __future__ import annotations

import hashlib

from fastapi import APIRouter, Depends, Header, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from aiuse.auth import bearer_required
from aiuse.codes import normalize_friend_code
from aiuse.db import get_session
from aiuse.models import Profile

router = APIRouter(prefix="/avatars", tags=["avatars"])


def _make_etag(avatar: bytes) -> str:
    return f'"{hashlib.sha256(avatar).hexdigest()[:16]}"'


@router.get("/{friend_code}")
async def get_avatar(
    friend_code: str,
    if_none_match: str | None = Header(None, alias="If-None-Match"),
    _: Profile = Depends(bearer_required),  # auth required, но текущий юзер не важен
    session: AsyncSession = Depends(get_session),
) -> Response:
    target_code = normalize_friend_code(friend_code)
    target = (
        await session.execute(select(Profile).where(Profile.friend_code == target_code))
    ).scalar_one_or_none()
    if target is None or target.avatar is None:
        raise HTTPException(status_code=404, detail="avatar not found")

    etag = _make_etag(target.avatar)
    if if_none_match == etag:
        return Response(status_code=status.HTTP_304_NOT_MODIFIED)

    return Response(
        content=target.avatar,
        media_type=target.avatar_mime or "application/octet-stream",
        headers={
            "ETag": etag,
            "Cache-Control": "max-age=86400, private",
        },
    )
```

- [ ] **Step 4: Подключить**

```python
from aiuse.routers import avatars, blocks, friends, health, leaderboard, profiles, snapshots

app.include_router(avatars.router, prefix="/api")
```

- [ ] **Step 5: Прогнать**

```bash
pytest tests/test_avatars.py -v 2>&1 | tail -10
```

Expected: 5 PASS.

- [ ] **Step 6: Коммит**

```bash
git add src/aiuse/routers/avatars.py src/aiuse/main.py tests/test_avatars.py
git commit -m "feat(api): GET /api/avatars/{code} с ETag и 304-кэшированием"
```

---

## Phase F: E2E расширение

### Task 8: e2e smoke Alice→Bob→leaderboard

**Files:**
- Modify: `tests/test_e2e_smoke.py`

- [ ] **Step 1: Добавить тест**

В конец `tests/test_e2e_smoke.py`:

```python
async def test_two_user_friend_leaderboard_flow(client: AsyncClient):
    from datetime import datetime, timedelta, timezone

    # 1. Регистрация двух юзеров
    r1 = await client.post("/api/profiles", json={"display_name": "Alice"})
    alice_secret = r1.json()["api_secret"]
    alice_code = r1.json()["friend_code"]
    alice_headers = {"Authorization": f"Bearer {alice_secret}"}

    r2 = await client.post("/api/profiles", json={"display_name": "Bob"})
    bob_secret = r2.json()["api_secret"]
    bob_code = r2.json()["friend_code"]
    bob_headers = {"Authorization": f"Bearer {bob_secret}"}

    # 2. Bob добавляет Alice
    r3 = await client.post(
        "/api/friends", json={"friend_code": alice_code}, headers=bob_headers
    )
    assert r3.status_code == 201

    # 3. Alice шлёт snapshot — текущий час
    now = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
    r4 = await client.post(
        "/api/snapshots",
        json={"snapshots": [{
            "hour_bucket": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "tokens_input": 100,
            "tokens_output": 200,
        }]},
        headers=alice_headers,
    )
    assert r4.status_code == 200

    # 4. Bob видит Alice в лидерборде
    r5 = await client.get("/api/leaderboard?period=day", headers=bob_headers)
    entries = r5.json()["entries"]
    alice_entry = next(e for e in entries if e["friend_code"] == alice_code)
    assert alice_entry["tokens_total"] == 300
    assert alice_entry["is_me"] is False

    # 5. Alice регенерирует код → Bob больше не видит Alice
    r6 = await client.post("/api/profiles/me/regenerate-friend-code", headers=alice_headers)
    assert r6.status_code == 200

    r7 = await client.get("/api/friends", headers=bob_headers)
    assert all(f["friend_code"] != alice_code for f in r7.json()["friends"])
```

- [ ] **Step 2: Прогнать**

```bash
pytest tests/test_e2e_smoke.py -v 2>&1 | tail -10
```

Expected: оба теста (старый + новый) PASS.

- [ ] **Step 3: Полный прогон + ruff**

```bash
pytest -v 2>&1 | tail -5
ruff check src tests 2>&1 | tail -5
```

Expected: всё PASS, ruff clean.

- [ ] **Step 4: Коммит**

```bash
git add tests/test_e2e_smoke.py
git commit -m "test: e2e — два юзера, друзья, лидерборд, регенерация"
```

---

## Phase G: Deploy

### Task 9: Push в prod

**Files:** — (никаких новых файлов)

- [ ] **Step 1: Локально проверить контейнер собирается**

```bash
cd /Users/sergeytovarov/work/ai-stats-api
docker build -t aiuse-api:test . 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 2: Push на prod**

```bash
git push prod main
```

Post-receive хук на VM:
- git reset --hard origin/main
- docker compose up -d --build api
- alembic upgrade head внутри контейнера (миграции уже все применены, no-op).

- [ ] **Step 3: Verify endpoints через curl**

```bash
# health
curl -fsS https://aiuse.popovs.tech/api/health

# создать тестовый профиль
TEST_RESPONSE=$(curl -fsS -X POST https://aiuse.popovs.tech/api/profiles \
  -H 'Content-Type: application/json' \
  -d '{"display_name":"DeployTest"}')
SECRET=$(echo "$TEST_RESPONSE" | grep -o '"api_secret":"[^"]*"' | cut -d'"' -f4)
CODE=$(echo "$TEST_RESPONSE" | grep -o '"friend_code":"[^"]*"' | cut -d'"' -f4)

# проверить новый endpoint
curl -fsS https://aiuse.popovs.tech/api/friends \
  -H "Authorization: Bearer $SECRET"

curl -fsS "https://aiuse.popovs.tech/api/leaderboard?period=day" \
  -H "Authorization: Bearer $SECRET"

curl -fsS https://aiuse.popovs.tech/api/blocks \
  -H "Authorization: Bearer $SECRET"

# удалить тестовый профиль
curl -fsS -X DELETE https://aiuse.popovs.tech/api/profiles/me \
  -H "Authorization: Bearer $SECRET"
```

Expected: все запросы 200/201/204, никаких 500.

- [ ] **Step 4: Push на GitHub**

```bash
git push origin main
```

- [ ] **Step 5: Запись в CHANGELOG.md (внутри ai-stats репо)**

В `/Users/sergeytovarov/work/ai-stats/CHANGELOG.md` под `## [Unreleased]` добавить:

```markdown
### Backend v0.3.0 — friends + leaderboard endpoints
- `POST /api/friends`, `GET /api/friends`, `DELETE /api/friends/{code}` (с опц. block).
- `GET /api/blocks`, `DELETE /api/blocks/{code}`.
- `GET /api/leaderboard?period={day|week|month|24h}` — SUM tokens среди друзей + я, фильтрация неактивных профилей.
- `GET /api/avatars/{code}` — отдача bytea с ETag.
- Симметричная friendship-связь одной строкой `(min(a,b), max(a,b))`.
- Блок маскируется под 404 (не палим факт блокировки).
```

Коммит:

```bash
cd /Users/sergeytovarov/work/ai-stats
git add CHANGELOG.md
git commit -m "docs(changelog): backend v0.3.0 — friends + leaderboard endpoints"
```

---

## Self-Review

### Spec coverage

| Спек (раздел) | Покрыто? |
|---|---|
| §6.1 POST /api/friends (404/409/403) | ✓ Task 3 (404 = блок маскируется под "не найден") |
| §6.1 GET /api/friends | ✓ Task 3 |
| §6.1 DELETE /api/friends/{code} + block | ✓ Task 4 |
| §6.1 GET /api/blocks | ✓ Task 5 |
| §6.1 DELETE /api/blocks/{code} | ✓ Task 5 |
| §6.1 GET /api/leaderboard | ✓ Task 6 |
| §6.1 GET /api/avatars/{code} | ✓ Task 7 |
| §6.2 Лимиты — friends 100 | ✓ Task 3 |
| §8.1 sharing=false → не видит leaderboard | ✓ Task 6 (тест test_leaderboard_blocked_when_sharing_disabled_for_me) |
| §8.1 sharing=false других → не в leaderboard | ✓ Task 6 (test_leaderboard_excludes_users_with_sharing_disabled) |
| §8.5 регенерация → friendship рвётся | ✓ Task 8 e2e (этот эндпоинт из v0.2.0 уже это делает) |
| §8.6 блок: 403/404 одинаково | ✓ Task 3 |

### Placeholder scan

- В Task 4 Step 1 я оставил «заметку про дублирование» (`test_delete_friend_with_block_prevents_re_add` — оставил как заметку, удалить»). **Это формальный placeholder — инструкция engineer'у удалить тест**. Исправлю прямо в плане.

Исправляю Task 4 Step 1: убираю «заметочный» тест из примера, оставляю только 3 финальных теста.

### Type consistency

- `friend_code` везде проходит через `normalize_friend_code` перед поиском в БД (Tasks 3, 4, 5, 7). ✓
- `sharing_enabled.is_(True)` в leaderboard — корректное SQLAlchemy сравнение для boolean. ✓
- `Friendship.user_a_id < user_b_id` CHECK уважается через `sorted(...)` в Tasks 3-4. ✓
- `Block.blocker_id` / `blocked_id` — везде «who blocks whom», never confused. ✓

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-23-leaderboard-v0.3.0-backend.md`.

Два варианта исполнения:

1. **Subagent-Driven (recommended)** — диспатчу свежего сабагента на каждый task.
2. **Inline Execution** — исполняю задачи в этой сессии через `executing-plans`.

Какой?
