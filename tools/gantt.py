# -*- coding: utf-8 -*-
r"""План работ диаграммой Ганта — из трекера, а не из головы.

Диаграмма, нарисованная руками, устаревает на первой же закрытой задаче
и начинает врать. Эта собирается из состояния задач: что закрыто — закрыто,
что открыто — открыто, доля готового считается, а не пишется.

Даты закрытого настоящие, из трекера. Даты открытого — **план, а не
обещание**, и в самом документе это сказано прямо: они расставлены по
порядку эпиков, по два дня на задачу.

Запуск:
    python tools\gantt.py            — напечатать
    python tools\gantt.py --write    — положить в docs/pm/README.md
"""
import argparse
import datetime
import io
import json
import os
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "docs", "pm", "README.md")
TRAC = r"D:\pm\soft\zigrecstudio-trac"
TRAC_PYTHON = r"D:\pm\soft\trac-venv\Scripts\python.exe"

# Эпики по этапам дорожной карты. Номера — из трекера.
PHASES = [
    ("Цель 1: запись в нормальный mp4", [2, 3, 4, 5]),
    ("Звук", [6]),
    ("Редактор", [7, 8]),
    ("Паритет и выпуск", [9]),
]

# Дни на одну открытую задачу — грубая мерка для плана.
DAYS_PER_TASK = 2

READ = r'''
# -*- coding: utf-8 -*-
import sys, json
from trac.env import Environment
from trac.ticket.model import Ticket
env = Environment(r"%s")
out = []
for tid in range(1, 300):
    try:
        t = Ticket(env, tid)
    except Exception:
        continue
    changes = list(t.get_changelog())
    # У тикета время создания лежит в поле "time", а не в отдельном свойстве.
    first = t["time"] if t["time"] else (changes[0][0] if changes else None)
    last = changes[-1][0] if changes else first
    if first is None:
        continue
    out.append({
        "id": tid,
        "summary": t["summary"],
        "status": t["status"],
        "created": first.isoformat(),
        "changed": last.isoformat(),
    })
sys.stdout.write(json.dumps(out, ensure_ascii=False))
'''


def read_tickets():
    script = os.path.join(tempfile.gettempdir(), "zigrec_gantt_read.py")
    with io.open(script, "w", encoding="utf-8") as f:
        f.write(READ % TRAC)
    out = subprocess.run([TRAC_PYTHON, script], capture_output=True, text=True,
                         encoding="utf-8", errors="replace")
    at = out.stdout.find("[")
    if at < 0:
        sys.stderr.write(out.stdout + out.stderr)
        raise SystemExit("не удалось прочитать трекер")
    return {t["id"]: t for t in json.loads(out.stdout[at:])}


def day(iso):
    return datetime.datetime.fromisoformat(iso).date()


def clean(text):
    """Убрать из названия служебную приставку уровня и знаки, которые
    ломают разметку диаграммы."""
    for tag in ("[L0] ", "[L1] ", "[L2] ", "[L3] "):
        if text.startswith(tag):
            text = text[len(tag):]
    return text.replace(":", " —").replace(",", " ").strip()


def children_of(tickets, epic_id):
    """Задачи эпика. Связь в трекере не заведена, поэтому берём по разделам
    дорожной карты: номера задач идут следом за своим эпиком."""
    ranges = {2: (10, 11), 3: (13, 15), 4: (12, 17), 5: (18, 19),
              6: (20, 22), 7: (23, 25), 8: (26, 27), 9: (28, 31)}
    lo, hi = ranges.get(epic_id, (0, -1))
    return [t for t in tickets.values() if lo <= t["id"] <= hi]


def build(tickets):
    lines = []
    plan_from = None

    # Начало плана — следующий день после последнего закрытого.
    for t in tickets.values():
        if t["status"] == "closed":
            d = day(t["changed"])
            plan_from = d if plan_from is None else max(plan_from, d)
    plan_from = (plan_from or datetime.date.today()) + datetime.timedelta(days=1)
    cursor = plan_from

    for title, epic_ids in PHASES:
        lines.append("    section %s" % title)
        for epic_id in epic_ids:
            epic = tickets.get(epic_id)
            if not epic:
                continue
            kids = children_of(tickets, epic_id)
            done = [k for k in kids if k["status"] == "closed"]

            if epic["status"] == "closed":
                start = min([day(k["created"]) for k in kids] or [day(epic["created"])])
                end = day(epic["changed"])
                if end <= start:
                    end = start + datetime.timedelta(days=1)
                lines.append("    %s :done, %s, %s" % (
                    clean(epic["summary"]), start.isoformat(), end.isoformat()))
                continue

            days = max(len(kids) - len(done), 1) * DAYS_PER_TASK
            state = "active" if done else ""
            mark = (state + ", ") if state else ""
            lines.append("    %s :%s%s, %dd" % (
                clean(epic["summary"]), mark, cursor.isoformat(), days))
            cursor += datetime.timedelta(days=days)

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()

    tickets = read_tickets()
    work = [t for t in tickets.values() if t["id"] != 1]
    closed = [t for t in work if t["status"] == "closed"]
    share = 100.0 * len(closed) / max(len(work), 1)

    chart = build(tickets)
    today = datetime.date.today().isoformat()

    text = """# План работ

Диаграмма собирается из трекера инструментом `tools/gantt.py`, а не рисуется
руками: нарисованная руками устаревает на первой же закрытой задаче и начинает
врать.

**Готово %.1f%%** — %d задач из %d. Обновлено %s.

Даты закрытого настоящие. Даты открытого — план, а не обещание: они расставлены
по порядку эпиков, по два дня на оставшуюся задачу.

```mermaid
gantt
    title Zig-Rec Studio
    dateFormat YYYY-MM-DD
    axisFormat %%d.%%m
%s
```

## Что за чем

**Цель 1** закрыта: запись куска экрана в mp4, который открывается в браузере,
Windows Media Player, VLC и PowerPoint. Четыре эпика — инфраструктура, захват,
кодирование, управление записью.

**Звук** идёт следом, потому что без него запись экрана наполовину немая.
Микрофон уже пишется отдельной дорожкой; остались системный звук и несколько
дорожек в одном файле.

**Редактор** — самая большая часть впереди: плеер с точной перемоткой, таймлайн
с дорожками и отменой, резка, экспорт без перекодирования.

**Паритет и выпуск** в конце: сравнение с CamStudio и OBS по расходу процессора,
размеру и качеству, потом версия 1.0.

Подробности по каждой задаче — в [задачах на GitHub](https://github.com/j0k/ZigRec-Studio/issues).
""" % (share, len(closed), len(work), today, chart)

    if args.write:
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        with io.open(OUT, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("записано:", OUT)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
