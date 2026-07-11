#!/usr/bin/env python3
"""Эксперимент v2: многоступенчатый вердикт «минимально достаточная модель».

Лестницы:
  claude-code: fable/opus (T0) -> sonnet-4-6 (T1) -> haiku-4-5 (T2)
  codex:       gpt-5.6-sol / gpt-5.5 (T0) -> gpt-5.4 (T1) -> gpt-5.4-mini|spark (T2)

Эвристика ставит heur_tier (минимальная ступень, которой хватило бы),
судья (LLM, выборка) потом корректирует. Судейская выборка выгружается
в judge_sample.tsv, вердикты загружаются обратно скриптом judge_load.py.
"""
from __future__ import annotations

import json
import random
import sqlite3
import sys
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

MSK = ZoneInfo("Europe/Moscow")
NOW = datetime.now(tz=MSK)
CUTOFF = (NOW - timedelta(days=7)).replace(hour=0, minute=0, second=0, microsecond=0)
CUTOFF_UTC = CUTOFF.astimezone(timezone.utc)
CUTOFF_STR = CUTOFF_UTC.strftime("%Y-%m-%dT%H:%M:%S")

HERE = Path(__file__).parent
DB_PATH = HERE / "ai_stats_experiment2.db"
SAMPLE_PATH = HERE / "judge_sample.tsv"

# --- Pricing (PricingTable.swift + допущение по gpt-5.6-sol) ---------------------
RATES = {
    "claude-opus":       (5.00, 25.00, 0.50, 6.25, 10.00),
    "claude-sonnet":     (3.00, 15.00, 0.30, 3.75, 6.00),
    "claude-haiku":      (1.00, 5.00, 0.10, 1.25, 2.00),
    "claude-fable":      (10.00, 50.00, 1.00, 12.50, 20.00),
    "claude-mythos":     (10.00, 50.00, 1.00, 12.50, 20.00),
    "gpt-5.6-sol":       (5.00, 30.00, 0.50, 0.0, 0.0),   # ДОПУЩЕНИЕ: как gpt-5.5
    "gpt-5.5":           (5.00, 30.00, 0.50, 0.0, 0.0),
    "gpt-5.4":           (2.50, 15.00, 0.25, 0.0, 0.0),
    "gpt-5.4-mini":      (0.75, 4.50, 0.075, 0.0, 0.0),
    "codex-auto-review": (5.00, 15.00, 0.63, 0.0, 0.0),
}


def rate_for(model: str):
    if model in RATES:
        return RATES[model]
    for prefix in ("claude-opus", "claude-sonnet", "claude-haiku", "claude-fable",
                   "claude-mythos", "gpt-5.4-mini", "gpt-5.6-sol", "gpt-5.5", "gpt-5.4"):
        if model.startswith(prefix):
            return RATES[prefix]
    return (0.0, 0.0, 0.0, 0.0, 0.0)


def cost(model: str, inp: int, out: int, cr: int, cw5: int, cw1: int) -> float:
    r = rate_for(model)
    m = 1_000_000.0
    return inp / m * r[0] + out / m * r[1] + cr / m * r[2] + cw5 / m * r[3] + cw1 / m * r[4]


# --- Лестницы моделей -------------------------------------------------------------
T0_PREFIXES = ("claude-fable", "claude-mythos", "claude-opus", "gpt-5.5", "gpt-5.6-sol")
TIER_MODELS = {
    "claude-code": {1: "claude-sonnet-4-6", 2: "claude-haiku-4-5"},
    "codex":       {1: "gpt-5.4",           2: "gpt-5.4-mini"},   # T2 = mini|spark
}
TIER_LABEL = {
    "claude-code": {0: "opus/fable по делу", 1: "хватило бы sonnet-4-6", 2: "хватило бы haiku-4-5"},
    "codex":       {0: "5.5/sol по делу",    1: "хватило бы gpt-5.4",    2: "хватило бы 5.4-mini/spark"},
}


def heur_tier(model: str, n_tools: int, n_edits: int, out_tok: int, prompt_chars: int) -> int | None:
    """Минимально достаточная ступень по форме хода. None — модель уже не T0."""
    if not model.startswith(T0_PREFIXES):
        return None
    if n_edits == 0 and n_tools == 0 and out_tok < 800 and prompt_chars < 1200:
        return 2
    if n_edits == 0 and n_tools <= 4 and out_tok < 4000:
        return 1
    return 0


# --- Turn model (парсеры идентичны v1, prompt_head расширен до 300) ----------------
@dataclass
class Turn:
    source: str
    ts: str = ""
    session: str = ""
    project: str = ""
    model: str = ""
    effort: str = ""
    prompt_head: str = ""
    prompt_chars: int = 0
    n_requests: int = 0
    n_tool_calls: int = 0
    n_edits: int = 0
    input_tokens: int = 0
    cache_read: int = 0
    cache_create_5m: int = 0
    cache_create_1h: int = 0
    output_tokens: int = 0
    models_seen: set = field(default_factory=set)

    @property
    def cost_usd(self) -> float:
        return cost(self.model, self.input_tokens, self.output_tokens,
                    self.cache_read, self.cache_create_5m, self.cache_create_1h)


def is_real_prompt(d: dict) -> str | None:
    if d.get("type") != "user" or d.get("isSidechain"):
        return None
    if d.get("isMeta"):
        return None
    msg = d.get("message") or {}
    content = msg.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
            return None
        texts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
        if texts:
            return "\n".join(texts)
    return None


EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}


def parse_claude(turns: list[Turn]):
    root = Path.home() / ".claude" / "projects"
    files = [p for p in root.rglob("*.jsonl")
             if datetime.fromtimestamp(p.stat().st_mtime, tz=MSK) >= CUTOFF]
    for path in files:
        cur: Turn | None = None
        seen_msg_usage: dict[str, tuple] = {}
        turn_msg_ids: set[str] = set()
        try:
            lines = path.read_text(errors="replace").splitlines()
        except OSError:
            continue

        def flush(t: Turn | None):
            if t is None:
                return
            for mid in turn_msg_ids:
                u = seen_msg_usage.get(mid)
                if not u:
                    continue
                t.n_requests += 1
                t.input_tokens += u[0]
                t.cache_read += u[1]
                t.cache_create_5m += u[2]
                t.cache_create_1h += u[3]
                t.output_tokens += u[4]
            if t.n_requests > 0 and t.model:
                turns.append(t)

        for line in lines:
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            ts = d.get("timestamp", "")
            if ts and ts < CUTOFF_STR:
                continue
            prompt = is_real_prompt(d)
            if prompt is not None:
                flush(cur)
                turn_msg_ids = set()
                cur = Turn(source="claude-code", ts=ts,
                           session=d.get("sessionId", path.stem),
                           project=d.get("cwd", ""),
                           prompt_head=prompt[:300].replace("\n", " ").replace("\t", " "),
                           prompt_chars=len(prompt))
                continue
            if d.get("type") == "assistant" and cur is not None:
                msg = d.get("message") or {}
                usage = msg.get("usage")
                model = msg.get("model", "")
                if model == "<synthetic>":
                    continue
                mid = msg.get("id") or d.get("requestId") or d.get("uuid")
                if usage and mid:
                    cc = usage.get("cache_creation") or {}
                    seen_msg_usage[mid] = (
                        usage.get("input_tokens", 0) or 0,
                        usage.get("cache_read_input_tokens", 0) or 0,
                        cc.get("ephemeral_5m_input_tokens",
                               usage.get("cache_creation_input_tokens", 0) or 0),
                        cc.get("ephemeral_1h_input_tokens", 0) or 0,
                        usage.get("output_tokens", 0) or 0,
                    )
                    turn_msg_ids.add(mid)
                if model and not d.get("isSidechain"):
                    cur.model = model
                    cur.models_seen.add(model)
                if not d.get("isSidechain"):
                    for b in (msg.get("content") or []):
                        if isinstance(b, dict) and b.get("type") == "tool_use":
                            cur.n_tool_calls += 1
                            if b.get("name") in EDIT_TOOLS:
                                cur.n_edits += 1
        flush(cur)


def parse_codex(turns: list[Turn], rl_samples: list[tuple]):
    root = Path.home() / ".codex" / "sessions"
    files = [p for p in root.rglob("*.jsonl")
             if datetime.fromtimestamp(p.stat().st_mtime, tz=MSK) >= CUTOFF]
    for path in files:
        session_id = ""
        cwd = ""
        cur: Turn | None = None
        prev_total = (0, 0, 0, 0)

        def flush(t: Turn | None):
            if t is not None and (t.n_requests > 0 or t.input_tokens > 0):
                turns.append(t)

        try:
            f = path.open(errors="replace")
        except OSError:
            continue
        with f:
            for line in f:
                try:
                    d = json.loads(line)
                except json.JSONDecodeError:
                    continue
                t = d.get("type")
                p = d.get("payload") or {}
                if t == "session_meta":
                    session_id = p.get("id", path.stem)
                    cwd = p.get("cwd", "")
                elif t == "turn_context":
                    flush(cur)
                    ts = d.get("timestamp", "")
                    if ts and ts < CUTOFF_STR:
                        cur = None
                        continue
                    cur = Turn(source="codex", ts=ts,
                               session=session_id, project=p.get("cwd", cwd),
                               model=p.get("model", ""), effort=p.get("effort", "") or "")
                elif t == "response_item" and cur is not None:
                    pt = p.get("type")
                    if pt == "message" and p.get("role") == "user" and not cur.prompt_head:
                        texts = [c.get("text", "") for c in (p.get("content") or [])
                                 if isinstance(c, dict) and c.get("type") in ("input_text", "text")]
                        joined = "\n".join(texts)
                        cur.prompt_head = joined[:300].replace("\n", " ").replace("\t", " ")
                        cur.prompt_chars = len(joined)
                    elif pt in ("custom_tool_call", "function_call", "local_shell_call"):
                        cur.n_tool_calls += 1
                        if "patch" in (p.get("name") or ""):
                            cur.n_edits += 1
                elif t == "event_msg" and p.get("type") == "token_count":
                    rl = p.get("rate_limits") or {}
                    ts = d.get("timestamp", "")
                    if rl.get("limit_id") == "codex" and ts >= CUTOFF_STR:
                        pri = (rl.get("primary") or {}).get("used_percent")
                        sec = (rl.get("secondary") or {}).get("used_percent")
                        if pri is not None or sec is not None:
                            rl_samples.append((ts, pri, sec))
                    info = p.get("info") or {}
                    total = info.get("total_token_usage") or {}
                    cum = (total.get("input_tokens", 0), total.get("cached_input_tokens", 0),
                           total.get("output_tokens", 0), total.get("reasoning_output_tokens", 0))
                    d_in = max(0, cum[0] - prev_total[0])
                    d_cached = max(0, cum[1] - prev_total[1])
                    d_out = max(0, cum[2] - prev_total[2])
                    prev_total = cum
                    if cur is not None and (d_in or d_out):
                        cur.input_tokens += max(0, d_in - d_cached)
                        cur.cache_read += d_cached
                        cur.output_tokens += d_out
                        cur.n_requests += 1
            flush(cur)


def origin_of(prompt_head: str) -> str:
    h = prompt_head.lstrip()
    if h.startswith("<command-"):
        return "human"          # слэш-команда — инициатива пользователя
    if h.startswith("<"):
        return "auto"           # task-notification, system-обвязка и т.п.
    return "human"


def main():
    turns: list[Turn] = []
    rl_samples: list[tuple] = []
    parse_claude(turns)
    parse_codex(turns, rl_samples)
    print(f"Ходов собрано: {len(turns)}", file=sys.stderr)

    DB_PATH.unlink(missing_ok=True)
    con = sqlite3.connect(DB_PATH)
    con.execute("""
        CREATE TABLE turns (
            id INTEGER PRIMARY KEY,
            source TEXT, ts TEXT, day TEXT, session TEXT, project TEXT,
            model TEXT, effort TEXT, origin TEXT,
            prompt_head TEXT, prompt_chars INT,
            n_requests INT, n_tool_calls INT, n_edits INT,
            input_tokens INT, cache_read INT, cache_create_5m INT, cache_create_1h INT,
            output_tokens INT, cost_usd REAL,
            heur_tier INT,            -- 0 по делу / 1 средняя / 2 маленькая / NULL не-T0
            cf_model TEXT, cf_usd REAL,   -- counterfactual по heur_tier
            judge_tier INT            -- вердикт судьи (заполняется judge_load.py)
        )""")
    for t in turns:
        if not t.ts:
            continue
        try:
            day = datetime.fromisoformat(t.ts.replace("Z", "+00:00")).astimezone(MSK).strftime("%Y-%m-%d")
        except ValueError:
            continue
        tier = heur_tier(t.model, t.n_tool_calls, t.n_edits, t.output_tokens, t.prompt_chars)
        cf_model = cf_usd = None
        if tier in (1, 2):
            cf_model = TIER_MODELS[t.source][tier]
            cf_usd = cost(cf_model, t.input_tokens, t.output_tokens, t.cache_read,
                          t.cache_create_5m, t.cache_create_1h)
        con.execute("""INSERT INTO turns (source, ts, day, session, project, model, effort,
                        origin, prompt_head, prompt_chars, n_requests, n_tool_calls, n_edits,
                        input_tokens, cache_read, cache_create_5m, cache_create_1h,
                        output_tokens, cost_usd, heur_tier, cf_model, cf_usd, judge_tier)
                       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,NULL)""",
                    (t.source, t.ts, day, t.session, t.project, t.model, t.effort,
                     origin_of(t.prompt_head), t.prompt_head, t.prompt_chars,
                     t.n_requests, t.n_tool_calls, t.n_edits,
                     t.input_tokens, t.cache_read, t.cache_create_5m, t.cache_create_1h,
                     t.output_tokens, t.cost_usd, tier, cf_model, cf_usd))
    con.commit()

    def q(sql):
        return con.execute(sql).fetchall()

    # --- Лимит Codex (эпохи, как в v1) ---------------------------------------------
    weekly_added = 0.0
    if rl_samples:
        rl_samples.sort(key=lambda s: s[0])
        epoch_start = epoch_max = None
        for _, _, sec in rl_samples:
            if sec is None:
                continue
            if epoch_start is None:
                epoch_start = epoch_max = sec
            elif epoch_max - sec > 30:
                weekly_added += epoch_max - epoch_start
                epoch_start = epoch_max = sec
            else:
                epoch_max = max(epoch_max, sec)
        if epoch_start is not None:
            weekly_added += epoch_max - epoch_start

    # --- Разбивка по ступеням --------------------------------------------------------
    print("\n== Минимально достаточная модель (эвристика), только T0-ходы ==")
    print(f"{'source':<12} {'ступень':<28} {'ходов':>6} {'из них auto':>11} "
          f"{'cost':>9} {'cf':>9} {'экономия':>9}")
    for src, tier, n, n_auto, c, cf in q("""
            SELECT source, heur_tier, COUNT(*), SUM(origin='auto'),
                   SUM(cost_usd), SUM(COALESCE(cf_usd, cost_usd))
            FROM turns WHERE heur_tier IS NOT NULL
            GROUP BY source, heur_tier ORDER BY source, heur_tier"""):
        label = TIER_LABEL[src][tier]
        print(f"{src:<12} {label:<28} {n:>6,} {n_auto:>11,} "
              f"${c:>8,.0f} ${cf:>8,.0f} ${c - cf:>8,.2f}")

    # --- Итоговая карточка -------------------------------------------------------------
    print("\n" + "=" * 72)
    print("ИТОГ: если бы каждый ход шёл на минимально достаточной модели (эвристика)")
    print("=" * 72)
    for src, title in (("codex", "CODEX (план pro)"), ("claude-code", "CLAUDE CODE")):
        tok, c_total = q(f"""SELECT SUM(input_tokens + cache_read + cache_create_5m
                                        + cache_create_1h + output_tokens), SUM(cost_usd)
                             FROM turns WHERE source='{src}'""")[0]
        saved, saved_h = q(f"""SELECT SUM(cost_usd - cf_usd),
                                      SUM(CASE WHEN origin='human' THEN cost_usd - cf_usd ELSE 0 END)
                               FROM turns WHERE source='{src}' AND cf_usd IS NOT NULL""")[0]
        saved, saved_h = saved or 0.0, saved_h or 0.0
        freed_tokens = tok / c_total * saved
        print(f"\n{title}")
        if src == "codex" and weekly_added > 0:
            print(f"  Потрачено: {tok/1e6:,.0f} млн ток · ${c_total:,.0f} · ≈{weekly_added:.0f}% недельного лимита")
            print(f"  Экономия: ${saved:,.0f} (из них твои ходы ${saved_h:,.0f}, остальное — фоновые) · "
                  f"−{saved / c_total * weekly_added:.1f} п.п. лимита · +{freed_tokens/1e6:,.0f} млн ток")
        else:
            print(f"  Потрачено: {tok/1e6:,.0f} млн ток · ${c_total:,.0f}")
            print(f"  Экономия: ${saved:,.0f} (твои ходы ${saved_h:,.0f}) · "
                  f"−{saved / c_total * 100:.1f}% недельного объёма · +{freed_tokens/1e6:,.0f} млн ток")

    # --- Выборка для судьи ---------------------------------------------------------
    random.seed(42)
    sample_rows = []
    for src in ("claude-code", "codex"):
        for tier in (0, 1, 2):
            rows = q(f"""SELECT id, source, model, n_tool_calls, n_edits, output_tokens,
                                prompt_chars, prompt_head
                         FROM turns
                         WHERE source='{src}' AND heur_tier={tier} AND origin='human'
                           AND prompt_head != ''""")
            sample_rows.extend(random.sample(rows, min(15, len(rows))))
    with open(SAMPLE_PATH, "w") as f:
        f.write("id\tsource\tmodel\ttools\tedits\tout_tok\tprompt_chars\tprompt_head\n")
        for r in sample_rows:
            f.write("\t".join(str(x) for x in r) + "\n")
    print(f"\nВыборка для судьи: {len(sample_rows)} ходов -> {SAMPLE_PATH}")
    print(f"База: {DB_PATH}")
    con.close()


if __name__ == "__main__":
    main()
