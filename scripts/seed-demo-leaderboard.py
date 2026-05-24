#!/usr/bin/env python3
"""
Подмешивает previous_rank в leaderboard_cache локальной БД Burn, чтобы при
скриншотах в popover'е и в widget'е была видна динамика — стрелки ▲N / ▼N /
NEW рядом с каждой строкой.

Зачем: leaderboard_cache.payload_json хранит entries без previous_rank в
"свежей" БД. Без него UI рисует пустое место вместо стрелки. Для пиара
скриншотов нужно показать разнообразие — кто поднялся, кто упал, кто
новый, кто без изменений.

Workflow:
  1. killall Burn                                        # чтобы app не перезаписал cache
  2. ./scripts/seed-demo-leaderboard.py --backup --seed  # бэкап + посев
  3. open /Applications/Burn.app                         # запускаем
  4. Быстро (10-15 сек) делаем screenshots —
     ДО следующего sync'а от aiuse-сервера (он перезатрёт cache)
  5. ./scripts/seed-demo-leaderboard.py --restore        # возвращаем бэкап

Если sharing_enabled = false на сервере, aiuse не отдаст leaderboard
(вернёт 403) и наш seed останется в cache подольше — это удобнее.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

DB_PATH = Path.home() / "Library/Group Containers/group.com.sergeytovarov.aistats/stats.db"
BACKUP_PATH = DB_PATH.with_suffix(".db.demo-backup")
CONFIG_PATH = Path.home() / ".config/ai-stats/config.json"

PERIODS = ["day", "week", "month", "24h"]


def _set_demo_mode(enabled: bool) -> None:
    """Переключает demo_mode в config.json. Сохраняет остальные поля."""
    if not CONFIG_PATH.exists():
        print(f"⚠  config не найден: {CONFIG_PATH}, demo_mode не выставлен")
        return
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        try:
            cfg = json.load(f)
        except json.JSONDecodeError as e:
            print(f"⚠  невалидный config.json: {e}")
            return
    cfg["demo_mode"] = enabled
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    print(f"✓ demo_mode = {enabled} в {CONFIG_PATH}")


def _open_db() -> sqlite3.Connection:
    if not DB_PATH.exists():
        sys.exit(f"DB не найдена: {DB_PATH}\nЗапусти Burn хотя бы один раз чтобы создались таблицы.")
    return sqlite3.connect(DB_PATH)


def backup() -> None:
    """Сохраняет полный bin-копию stats.db рядом с оригиналом."""
    if BACKUP_PATH.exists():
        print(f"⚠  бэкап уже есть: {BACKUP_PATH}\n   удалю старый и сделаю новый")
        BACKUP_PATH.unlink()
    shutil.copy2(DB_PATH, BACKUP_PATH)
    print(f"✓ backup → {BACKUP_PATH}")


def restore() -> None:
    """Восстанавливает stats.db из бэкапа + выключает demo_mode."""
    if not BACKUP_PATH.exists():
        sys.exit(f"бэкап не найден: {BACKUP_PATH}\nнечего восстанавливать")
    shutil.copy2(BACKUP_PATH, DB_PATH)
    print(f"✓ restore ← {BACKUP_PATH}")
    _set_demo_mode(False)


def _seed_previous_ranks(entries: list[dict]) -> list[dict]:
    """
    Распределяет previous_rank по entries чтобы покрыть все визуальные кейсы:
    - rank 1 → previous_rank 2 (▲1 поднялся)
    - rank 2 → previous_rank 1 (▼1 опустился)
    - rank 3 → previous_rank 3 (без стрелки)
    - rank 4 → previous_rank 6 (▲2 большое поднятие)
    - rank 5 → None (NEW)
    - rank 6 → previous_rank 4 (▼2 большое падение)
    - rank 7+ → previous_rank rank-1 (▲1 для каждого)
    """
    out = []
    for e in entries:
        rank = e.get("rank", 0)
        if rank == 1:
            prev = 2
        elif rank == 2:
            prev = 1
        elif rank == 3:
            prev = 3
        elif rank == 4:
            prev = 6
        elif rank == 5:
            prev = None
        elif rank == 6:
            prev = 4
        else:
            prev = max(1, rank - 1)
        new = dict(e)
        new["previous_rank"] = prev
        out.append(new)
    return out


def _seed_tokens(entries: list[dict]) -> list[dict]:
    """
    Подставляет реалистичные tokens_total по rank. fake-друзья на сервере
    имеют 0 токенов (они не шарят данные), а для скриншотов нужны цифры
    которые выглядят живыми.

    Шкала уменьшается экспоненциально — реалистично для leaderboard'а
    активных AI-пользователей: лидер шпарит сильно больше последних.

    Не трогаем entries с уже непустым tokens_total > 0 — это сохраняет
    реальные данные тех, кто реально шарит (например меня самого).
    """
    rank_to_tokens = {
        1: 80_000_000,
        2: 52_000_000,
        3: 38_000_000,
        4: 21_000_000,
        5: 9_500_000,
        6: 4_200_000,
        7: 1_800_000,
        8: 700_000,
    }
    out = []
    for e in entries:
        rank = e.get("rank", 0)
        current_tokens = e.get("tokens_total", 0) or 0
        new = dict(e)
        if current_tokens == 0 and rank in rank_to_tokens:
            new["tokens_total"] = rank_to_tokens[rank]
        out.append(new)
    return out


def seed() -> None:
    """Перезаписывает leaderboard_cache.payload_json — добавляет previous_rank."""
    conn = _open_db()
    cur = conn.cursor()
    cur.execute("SELECT period, payload_json FROM leaderboard_cache")
    rows = cur.fetchall()
    if not rows:
        sys.exit("leaderboard_cache пустой — нет ни одного period'а.\n"
                 "Запусти Burn, дай ему синкнуться с aiuse, потом вернись.")

    touched = 0
    now_iso = datetime.now(timezone.utc).isoformat()
    for period, payload_json in rows:
        try:
            payload = json.loads(payload_json)
        except json.JSONDecodeError as e:
            print(f"⚠  [{period}] невалидный JSON в cache: {e}, пропускаю")
            continue

        entries = payload.get("entries", [])
        if not entries:
            print(f"⚠  [{period}] нет entries, пропускаю")
            continue

        seeded = _seed_previous_ranks(entries)
        seeded = _seed_tokens(seeded)
        payload["entries"] = seeded
        # Также обновим as_of чтобы UI не показывал «вчера»
        payload["as_of"] = now_iso

        new_json = json.dumps(payload, ensure_ascii=False)
        cur.execute(
            "UPDATE leaderboard_cache SET payload_json = ?, fetched_at = ? WHERE period = ?",
            (new_json, datetime.now(timezone.utc).timestamp(), period),
        )
        touched += 1
        print(f"✓ [{period}] обновил {len(entries)} entries с previous_rank")

    conn.commit()
    conn.close()
    print(f"\n✓ всего обновлено periods: {touched}")

    # Включаем demo_mode чтобы Burn не затёр cache при initial sync.
    _set_demo_mode(True)

    print("\nТеперь:")
    print("  1. killall Burn  (если открыт)")
    print("  2. open /Applications/Burn.app")
    print("  3. Делай screenshots — cache не затрётся, demo_mode выключен sync")
    print("  4. Когда закончил: ./scripts/seed-demo-leaderboard.py --restore")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backup", action="store_true",
                        help="сделать бэкап текущей stats.db в .demo-backup")
    parser.add_argument("--seed", action="store_true",
                        help="добавить previous_rank в leaderboard_cache всех periods")
    parser.add_argument("--restore", action="store_true",
                        help="восстановить stats.db из .demo-backup")
    args = parser.parse_args()

    if not (args.backup or args.seed or args.restore):
        parser.print_help()
        sys.exit(1)

    if args.backup:
        backup()
    if args.seed:
        seed()
    if args.restore:
        restore()


if __name__ == "__main__":
    main()
