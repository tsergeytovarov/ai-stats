#!/usr/bin/env python3
"""Эксперимент v3: продовая карточка за последние 30 дней (фикс-окно, без переключалок).

Статистика + советы: топ-утечки лимита с конкретными рекомендациями и шпаргалка
по моделям (описания Codex — живьём из ~/.codex/models_cache.json).
Судейские поправки — стратифицированные коэффициенты из 7-дневной судейской выборки.
"""
from __future__ import annotations

import json
import sqlite3
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

import experiment2 as e2

MSK = ZoneInfo("Europe/Moscow")
WINDOW_DAYS = 30

# Перебиваем окно v2 на 30 дней (парсеры читают модульные глобалы)
e2.CUTOFF = (datetime.now(tz=MSK) - timedelta(days=WINDOW_DAYS)).replace(
    hour=0, minute=0, second=0, microsecond=0)
e2.CUTOFF_UTC = e2.CUTOFF.astimezone(timezone.utc)
e2.CUTOFF_STR = e2.CUTOFF_UTC.strftime("%Y-%m-%dT%H:%M:%S")

DB_PATH = Path(__file__).parent / "ai_stats_experiment3.db"

# Доля экономии по судье внутри страты (source, heur_tier) — из judge_load.py (n=79)
JUDGE_RATIO = {
    ("claude-code", 0): 0.057, ("claude-code", 1): 0.643, ("claude-code", 2): 0.768,
    ("codex", 0): 0.072,       ("codex", 1): 0.534,       ("codex", 2): 0.807,
}

# Шпаргалка Claude — из политики пользователя (AGENTS.md, model/effort hints)
CLAUDE_GUIDE = [
    ("haiku",  "поиск по коду, explorer-агенты, простые правки, саммари"),
    ("sonnet", "основная работа: коммиты, PR, скиллы, рефакторинг, объяснения"),
    ("opus",   "архитектура, глубокое ревью, сложный дебаг, длинный контекст"),
    ("fable",  "только самые тяжёлые long-horizon задачи"),
]


def codex_guide() -> list[tuple[str, str]]:
    """Живые описания моделей из кэша самого Codex."""
    try:
        cache = json.load(open(Path.home() / ".codex" / "models_cache.json"))
        return [(m["slug"], m.get("description", ""))
                for m in cache.get("models", [])
                if m.get("visibility") == "list"]
    except Exception:
        return []


_CONFIRM = {"да", "ага", "угу", "ок", "окей", "нет", "готово", "ясно", "понял",
            "поняла", "спс", "спасибо", "yes", "no", "ok", "okay", "yep", "y", "n"}


def is_filler(head: str) -> bool:
    """Подтверждение/реплика внутри сессии — не утечка (нельзя свитчить модель)."""
    s = head.strip().lower()
    if not s:
        return True
    if s.startswith("<"):
        return False
    if not any(ch.isalpha() for ch in s):
        return True
    words = [w for w in "".join(ch if ch.isalpha() else " " for ch in s).split() if w]
    return bool(words) and all(w in _CONFIRM for w in words)


def norm_prefix(head: str) -> str:
    """Ключ кластера: нормализованное начало промпта.

    Любой auto-ход (промпт с '<', кроме слэш-команд) — спецкластер «Фоновые
    уведомления»: совет «болталки» к системной обвязке неприменим.
    """
    h = head.strip().lower()
    if h.startswith("<command-"):
        return "<слэш-команды>"
    if h.startswith("<"):
        return "<фоновые уведомления>"
    return h[:60]


def main():
    turns: list[e2.Turn] = []
    rl_samples: list[tuple] = []
    e2.parse_claude(turns)
    e2.parse_codex(turns, rl_samples)

    DB_PATH.unlink(missing_ok=True)
    con = sqlite3.connect(DB_PATH)
    con.execute("""CREATE TABLE turns (
        source TEXT, ts TEXT, model TEXT, origin TEXT, project TEXT,
        prompt_head TEXT, cluster TEXT, heur_tier INT,
        cost_usd REAL, cf_usd REAL, exp_saved REAL, tokens INT)""")
    for t in turns:
        if not t.ts:
            continue
        tier = e2.heur_tier(t.model, t.n_tool_calls, t.n_edits, t.output_tokens, t.prompt_chars)
        if is_filler(t.prompt_head):
            tier = None   # подтверждение — не утечка, exp 0
        cf = None
        if tier in (1, 2):
            cf = e2.cost(e2.TIER_MODELS[t.source][tier], t.input_tokens, t.output_tokens,
                         t.cache_read, t.cache_create_5m, t.cache_create_1h)
        c = t.cost_usd
        # ожидаемая экономия: для T1/T2 — фактический counterfactual, для T0 — судейский коэффициент
        if tier is None:
            exp = 0.0
        elif tier == 0:
            exp = JUDGE_RATIO[(t.source, 0)] * c
        else:
            exp = max(0.0, c - cf)
        tokens = (t.input_tokens + t.cache_read + t.cache_create_5m
                  + t.cache_create_1h + t.output_tokens)
        con.execute("INSERT INTO turns VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                    (t.source, t.ts, t.model, e2.origin_of(t.prompt_head), t.project,
                     t.prompt_head, norm_prefix(t.prompt_head), tier, c, cf, exp, tokens))
    con.commit()
    q = lambda sql: con.execute(sql).fetchall()

    # Недельный лимит Codex: эпохи за месяц -> суммарный расход и средненедельный
    weekly_epochs = []
    if rl_samples:
        rl_samples.sort(key=lambda s: s[0])
        start = mx = None
        for _, _, sec in rl_samples:
            if sec is None:
                continue
            if start is None:
                start = mx = sec
            elif mx - sec > 30:
                weekly_epochs.append(mx - start)
                start = mx = sec
            else:
                mx = max(mx, sec)
        if start is not None:
            weekly_epochs.append(mx - start)
    month_limit_pct = sum(weekly_epochs)
    avg_week_pct = month_limit_pct / (WINDOW_DAYS / 7) if month_limit_pct else 0.0

    # ==================== КАРТОЧКА ====================
    W = 96
    print("┌" + "─" * W + "┐")

    def pr(s=""):
        print("│ " + s[:W - 2].ljust(W - 2) + " │")

    def hr():
        print("├" + "─" * W + "┤")

    pr(f"ЗА ПОСЛЕДНИЕ 30 ДНЕЙ ({e2.CUTOFF.strftime('%d.%m')} — {datetime.now(tz=MSK).strftime('%d.%m')})")
    for src, title in (("codex", "Codex"), ("claude-code", "Claude Code")):
        tok, c_total, exp = q(f"""SELECT SUM(tokens), SUM(cost_usd), SUM(exp_saved)
                                  FROM turns WHERE source='{src}'""")[0]
        exp_pct = exp / c_total * 100
        hr()
        pr(f"{title}: {tok/1e9:.2f} млрд ток · ${c_total:,.0f}")
        if src == "codex" and avg_week_pct:
            pr(f"  недельный лимит: в среднем ≈{avg_week_pct:.0f}%/нед, "
               f"за месяц суммарно ≈{month_limit_pct:.0f} п.п.")
            pr(f"  УТЕКАЕТ: ≈{exp_pct:.0f}% объёма = ${exp:,.0f}/мес "
               f"≈ {exp_pct / 100 * avg_week_pct:.1f} п.п. недельного лимита еженедельно")
        else:
            pr(f"  УТЕКАЕТ: ≈{exp_pct:.0f}% объёма = ${exp:,.0f}/мес "
               f"(≈ столько же % недельного лимита)")

    # Топ-утечки с советами
    hr()
    pr("ГЛАВНЫЕ УТЕЧКИ И ЧТО ДЕЛАТЬ")
    clusters = q("""SELECT t1.source, t1.cluster, COUNT(*), SUM(t1.exp_saved),
                           (SELECT model FROM turns t2
                            WHERE t2.source = t1.source AND t2.cluster = t1.cluster
                            GROUP BY model ORDER BY SUM(exp_saved) DESC LIMIT 1),
                           AVG(t1.heur_tier IS NOT NULL AND t1.heur_tier > 0)
                    FROM turns t1
                    GROUP BY t1.source, t1.cluster
                    HAVING COUNT(*) >= 3 AND SUM(t1.exp_saved) > 1
                    ORDER BY SUM(t1.exp_saved) DESC LIMIT 6""")
    for i, (src, cluster, n, saved, model, _) in enumerate(clusters, 1):
        short = ("труба рерайта: роль «" + cluster[5:40].strip() + "…»"
                 if cluster.startswith("ты — ") else cluster[:44])
        pr(f"{i}. [{src}] {short}")
        if cluster.startswith("ты — "):
            advice = "зафиксируй модель этой роли в конфиге трубы: sonnet/gpt-5.4"
        elif cluster.startswith("<фоновые"):
            advice = "фоновые уведомления — переведи обработку на дешёвую модель"
        else:
            advice = ("короткие вопросы/болталка — задавай на " +
                      ("luna/spark" if src == "codex" else "haiku") +
                      " или в новом лёгком чате")
        pr(f"   {n} ходов на {model} · ≈${saved:,.0f}/мес · {advice}")

    # Шпаргалка по моделям
    hr()
    pr("ШПАРГАЛКА: КАКУЮ МОДЕЛЬ КОГДА")
    pr("Codex (описания из models_cache самого Codex):")
    for slug, desc in codex_guide():
        pr(f"  {slug:<20} {desc[:48]}")
    pr("Claude (твоя же политика из AGENTS.md):")
    for slug, desc in CLAUDE_GUIDE:
        pr(f"  {slug:<20} {desc[:48]}")
    print("└" + "─" * W + "┘")

    # Справочно: сколько ходов вообще и разбивка по ступеням
    print("\nСправочно (30 дней):")
    for src, n, t0, t1, t2 in q("""SELECT source, COUNT(*),
                SUM(heur_tier=0), SUM(heur_tier=1), SUM(heur_tier=2)
                FROM turns GROUP BY source"""):
        print(f"  {src}: {n} ходов; T0-модели: по делу {t0 or 0}, "
              f"хватило бы средней {t1 or 0}, маленькой {t2 or 0}")
    print(f"База: {DB_PATH}")
    con.close()


if __name__ == "__main__":
    main()
