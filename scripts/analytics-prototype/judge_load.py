#!/usr/bin/env python3
"""Загружает вердикты судьи в БД v2 и считает скорректированную экономию.

Судья: LLM-разметка выборки judge_sample.tsv (в эксперименте — Claude в сессии,
в проде — Haiku). Вердикт = минимально достаточная ступень лестницы:
0 — нужен frontier, 1 — средняя модель, 2 — маленькая.
"""
import sqlite3
from pathlib import Path

HERE = Path(__file__).parent
DB = HERE / "ai_stats_experiment2.db"

# --- Вердикты судьи (id -> tier) --------------------------------------------------
JUDGE = {
    # claude-code
    533: 1, 79: 1, 9: 1, 600: 0, 266: 0, 216: 1, 208: 0, 150: 1, 599: 1, 76: 0,
    564: 0, 702: 0, 465: 0, 59: 1, 498: 0, 590: 1, 174: 1, 169: 1, 261: 1, 427: 1,
    438: 1, 658: 1, 741: 1, 159: 2, 710: 1, 415: 1, 689: 1, 588: 1, 429: 1, 613: 1,
    288: 2, 71: 2, 324: 1, 168: 2,
    # codex
    1949: 1, 1797: 1, 1396: 1, 1521: 0, 2352: 0, 1936: 1, 1368: 0, 1357: 0, 1990: 0,
    1359: 0, 1976: 1, 1954: 1, 2163: 0, 1565: 0, 1323: 2, 1916: 1, 1760: 1, 1800: 1,
    1483: 2, 2343: 2, 1715: 1, 1084: 1, 1808: 1, 1672: 1, 1987: 2, 1849: 1, 1843: 1,
    2144: 1, 2014: 1, 1707: 1, 1470: 2, 1445: 1, 1384: 2, 1478: 1, 1487: 2, 1447: 2,
    2316: 2, 1983: 2, 1394: 1, 2331: 2, 1462: 2, 2268: 1, 1944: 2, 1490: 2, 1469: 2,
}

RATES = {
    "claude-sonnet-4-6": (3.00, 15.00, 0.30, 3.75, 6.00),
    "claude-haiku-4-5":  (1.00, 5.00, 0.10, 1.25, 2.00),
    "gpt-5.4":           (2.50, 15.00, 0.25, 0.0, 0.0),
    "gpt-5.4-mini":      (0.75, 4.50, 0.075, 0.0, 0.0),
}
TIER_MODELS = {
    "claude-code": {1: "claude-sonnet-4-6", 2: "claude-haiku-4-5"},
    "codex":       {1: "gpt-5.4",           2: "gpt-5.4-mini"},
}


def cost_at(model, inp, out, cr, cw5, cw1):
    r = RATES[model]
    m = 1e6
    return inp / m * r[0] + out / m * r[1] + cr / m * r[2] + cw5 / m * r[3] + cw1 / m * r[4]


con = sqlite3.connect(DB)
for tid, tier in JUDGE.items():
    con.execute("UPDATE turns SET judge_tier = ? WHERE id = ?", (tier, tid))
con.commit()

q = lambda sql, *a: con.execute(sql, a).fetchall()

# --- Матрица согласия эвристика vs судья -----------------------------------------
print("== Согласие эвристики и судьи (по выборке, ходов) ==")
print(f"{'':>22} {'судья: frontier':>16} {'судья: средняя':>15} {'судья: маленькая':>17}")
for src in ("claude-code", "codex"):
    for ht in (0, 1, 2):
        row = [0, 0, 0]
        for (jt, n) in q("""SELECT judge_tier, COUNT(*) FROM turns
                            WHERE source=? AND heur_tier=? AND judge_tier IS NOT NULL
                            GROUP BY judge_tier""", src, ht):
            row[jt] = n
        if sum(row):
            print(f"{src} эвр.T{ht:<3} {row[0]:>16} {row[1]:>15} {row[2]:>17}")

# --- Скорректированная экономия (ratio-оценка по стратам) --------------------------
print("\n== Экономия по судье (стратифицированная ratio-оценка) ==")
grand = {}
for src in ("claude-code", "codex"):
    corrected = 0.0
    heur_saved_h = 0.0
    for ht in (0, 1, 2):
        # выборка страты: фактическая экономия по вердикту судьи
        rows = q("""SELECT cost_usd, judge_tier, input_tokens, output_tokens, cache_read,
                           cache_create_5m, cache_create_1h
                    FROM turns WHERE source=? AND heur_tier=? AND judge_tier IS NOT NULL""",
                 src, ht)
        if not rows:
            continue
        s_cost = sum(r[0] for r in rows)
        s_saved = 0.0
        for c, jt, inp, out, cr, cw5, cw1 in rows:
            if jt in (1, 2):
                s_saved += c - cost_at(TIER_MODELS[src][jt], inp, out, cr, cw5, cw1)
        ratio = s_saved / s_cost if s_cost else 0.0
        # население страты (только human — судья видел только их)
        pop_cost, pop_heur_saved = q("""SELECT SUM(cost_usd),
                                               SUM(cost_usd - COALESCE(cf_usd, cost_usd))
                                        FROM turns WHERE source=? AND heur_tier=?
                                        AND origin='human'""", src, ht)[0]
        pop_cost = pop_cost or 0.0
        corrected += ratio * pop_cost
        heur_saved_h += pop_heur_saved or 0.0
        print(f"  {src} эвр.T{ht}: доля экономии по судье {ratio*100:5.1f}% "
              f"-> на страте ${ratio * pop_cost:7.2f} (эвристика давала ${pop_heur_saved or 0:7.2f})")
    grand[src] = (corrected, heur_saved_h)

# --- Итоговая карточка -------------------------------------------------------------
WEEKLY_LIMIT_PCT_CODEX = 75.0  # из rate_limits (эпохи, experiment2)
print("\n" + "=" * 72)
print("ИТОГ С СУДЬЁЙ: «за неделю ты потратил X; правильный свитчинг дал бы…»")
print("=" * 72)
for src, title in (("codex", "CODEX (план pro)"), ("claude-code", "CLAUDE CODE")):
    tok, c_total = q("""SELECT SUM(input_tokens + cache_read + cache_create_5m
                                   + cache_create_1h + output_tokens), SUM(cost_usd)
                        FROM turns WHERE source=?""", src)[0]
    judge_saved, heur_saved = grand[src]
    freed_tok = tok / c_total * judge_saved
    print(f"\n{title}")
    if src == "codex":
        print(f"  Потрачено: {tok/1e6:,.0f} млн ток · ${c_total:,.0f} · ≈{WEEKLY_LIMIT_PCT_CODEX:.0f}% недельного лимита")
        print(f"  Судья: экономия ${judge_saved:,.0f} (эвристика говорила ${heur_saved:,.0f}) · "
              f"−{judge_saved / c_total * WEEKLY_LIMIT_PCT_CODEX:.1f} п.п. недельного лимита · "
              f"+{freed_tok/1e6:,.0f} млн ток обычной работы")
    else:
        print(f"  Потрачено: {tok/1e6:,.0f} млн ток · ${c_total:,.0f}")
        print(f"  Судья: экономия ${judge_saved:,.0f} (эвристика говорила ${heur_saved:,.0f}) · "
              f"−{judge_saved / c_total * 100:.1f}% недельного объёма · "
              f"+{freed_tok/1e6:,.0f} млн ток обычной работы")
con.commit()
con.close()
