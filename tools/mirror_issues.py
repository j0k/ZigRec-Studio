# -*- coding: utf-8 -*-
r"""Перенести открытые задачи из Trac в задачи GitHub.

Зачем. Трекер живёт на этой машине, и снаружи его никто не видит. Чтобы
работа была видна на GitHub — в списке задач и на доске проекта, — открытые
задачи переносятся туда.

Перенос **повторяемый**: задача, которая уже есть на GitHub, узнаётся по
строке `Trac #N` в тексте и обновляется, а не заводится второй раз. Иначе
каждый запуск плодил бы дубли.

Закрытые задачи не переносятся: на GitHub нужен список того, что впереди,
а не архив. История закрытого лежит в трекере и в журнале версий.

Запуск:
    set ZIGREC_GH_TOKEN=...
    python tools\mirror_issues.py            — показать, что будет сделано
    python tools\mirror_issues.py --apply    — сделать
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request

REPO = "j0k/ZigRec-Studio"
TRAC = r"D:\pm\soft\zigrecstudio-trac"
TRAC_PYTHON = r"D:\pm\soft\trac-venv\Scripts\python.exe"

# Метки: по одной на эпик плюс тип работы. Больше не нужно — метки полезны,
# пока их можно окинуть взглядом.
LABELS = {
    "эпик": ("6f42c1", "Крупная веха, объединяет задачи"),
    "запись": ("0e8a16", "Захват экрана и кодирование"),
    "звук": ("1d76db", "Микрофон, системный звук, дорожки"),
    "редактор": ("d93f0b", "Плеер, таймлайн, резка, экспорт"),
    "выпуск": ("fbca04", "Паритет, сравнения, релиз"),
}

# Какой эпик к какой метке. Номера — из трекера.
EPIC_LABEL = {
    1: "эпик",
    6: "звук",
    7: "редактор",
    8: "редактор",
    9: "выпуск",
}
TICKET_LABEL = {
    20: "звук", 21: "звук", 22: "звук",
    23: "редактор", 24: "редактор", 25: "редактор", 26: "редактор", 27: "редактор",
    28: "редактор", 29: "запись",
    30: "выпуск", 31: "выпуск",
}


def api(method, path, payload=None, token=None):
    url = path if path.startswith("http") else "https://api.github.com/repos/%s/%s" % (REPO, path)
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "zigrec-mirror")
    if data is not None:
        req.add_header("Content-Type", "application/json; charset=utf-8")
    try:
        with urllib.request.urlopen(req) as r:
            body = r.read().decode("utf-8")
            return json.loads(body) if body else {}, None
    except urllib.error.HTTPError as e:
        return None, "%d %s: %s" % (e.code, e.reason, e.read().decode("utf-8", "replace")[:200])


READ_TRAC = r'''
# -*- coding: utf-8 -*-
import sys, io, json
from trac.env import Environment
from trac.ticket.model import Ticket
env = Environment(r"%s")
out = []
for tid in range(1, 200):
    try:
        t = Ticket(env, tid)
    except Exception:
        continue
    if t["status"] == "closed":
        continue
    out.append({"id": tid, "summary": t["summary"], "type": t["type"],
                "description": t["description"] or ""})
sys.stdout.write(json.dumps(out, ensure_ascii=False))
'''


def read_tickets():
    import subprocess
    import tempfile
    script = os.path.join(tempfile.gettempdir(), "zigrec_read_trac.py")
    with open(script, "w", encoding="utf-8") as f:
        f.write(READ_TRAC % TRAC)
    out = subprocess.run([TRAC_PYTHON, script], capture_output=True, text=True,
                         encoding="utf-8", errors="replace")
    text = out.stdout.strip()
    at = text.find("[")
    if at < 0:
        sys.stderr.write(out.stdout + out.stderr)
        raise SystemExit("не удалось прочитать трекер")
    return json.loads(text[at:])


def body_for(ticket):
    """Текст задачи. Внизу — метка происхождения, по ней узнаётся повтор."""
    text = ticket["description"].strip()
    # Ссылки вида #NN в трекере значат другие тикеты трекера, а на GitHub —
    # другие номера. Оставляем как есть, но говорим, о чём речь.
    return "%s\n\n---\nПеренесено из внутреннего трекера: Trac #%d" % (text, ticket["id"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="действительно создавать")
    args = parser.parse_args()

    token = os.environ.get("ZIGREC_GH_TOKEN")
    if not token:
        raise SystemExit("нет ZIGREC_GH_TOKEN")

    tickets = read_tickets()
    print("открытых задач в трекере: %d" % len(tickets))

    if args.apply:
        for name, (color, about) in LABELS.items():
            api("POST", "labels", {"name": name, "color": color, "description": about}, token)

    existing = {}
    page = 1
    while True:
        got, err = api("GET", "issues?state=all&per_page=100&page=%d" % page, token=token)
        if err or not got:
            break
        for issue in got:
            body = issue.get("body") or ""
            marker = "Trac #"
            at = body.find(marker)
            if at >= 0:
                number = body[at + len(marker):].split()[0].strip()
                if number.isdigit():
                    existing[int(number)] = issue["number"]
        if len(got) < 100:
            break
        page += 1
    print("уже перенесено: %d" % len(existing))

    created = updated = 0
    for t in tickets:
        label = EPIC_LABEL.get(t["id"]) or TICKET_LABEL.get(t["id"])
        labels = [label] if label else []
        payload = {"title": t["summary"], "body": body_for(t), "labels": labels}

        if t["id"] in existing:
            if args.apply:
                api("PATCH", "issues/%d" % existing[t["id"]], payload, token)
            updated += 1
            print("  обновить #%d -> задача %d" % (t["id"], existing[t["id"]]))
            continue

        if args.apply:
            made, err = api("POST", "issues", payload, token)
            if err:
                print("  ПРОВАЛ на #%d: %s" % (t["id"], err))
                continue
            print("  создана задача %d — %s" % (made["number"], t["summary"][:60]))
        else:
            print("  создать: %s" % t["summary"][:70])
        created += 1

    print("создано %d, обновлено %d%s" % (created, updated, "" if args.apply else " (это был показ, без --apply)"))


if __name__ == "__main__":
    main()
