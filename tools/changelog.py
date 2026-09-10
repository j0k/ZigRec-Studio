# -*- coding: utf-8 -*-
r"""Журнал версий: размер и CRC32 итогового exe, строки кода.

Каждая прошлая версия **собирается заново** из своего коммита в отдельном
рабочем каталоге. Так число в таблице — это то, что действительно получается
из того кода, а не запись по памяти. Пересборка любой строки должна давать
тот же CRC32.

Запуск:
    python tools\changelog.py              — посчитать и напечатать таблицу
    python tools\changelog.py --wiki       — сразу положить в вики Trac
    python tools\changelog.py --only 3     — только три последние версии
"""
import argparse
import io
import os
import re
import shutil
import subprocess
import sys
import zlib

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKTREE = os.path.join(REPO, ".changelog-build")
TRAC_ENV = r"D:\pm\soft\zigrecstudio-trac"
TRAC_PYTHON = r"D:\pm\soft\trac-venv\Scripts\python.exe"


def run(args, cwd=REPO, check=True):
    out = subprocess.run(args, cwd=cwd, capture_output=True, text=True,
                         encoding="utf-8", errors="replace")
    if check and out.returncode != 0:
        raise RuntimeError("%s -> %d\n%s" % (" ".join(args), out.returncode, out.stderr[-800:]))
    return out.stdout


def find_zig():
    found = shutil.which("zig")
    if found:
        return found
    base = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Microsoft", "WinGet", "Packages")
    for root, _dirs, files in os.walk(base):
        if "zig.exe" in files:
            return os.path.join(root, "zig.exe")
    raise RuntimeError("Zig не найден")


ZIG = find_zig()


def versions():
    """Коммиты, в которых менялась версия: (версия, дата, хеш, заголовок)."""
    log = run(["git", "log", "--reverse", "--format=%H|%ad|%s", "--date=short", "--", "src/version.zig"])
    result = []
    seen = set()
    for line in log.splitlines():
        if not line.strip():
            continue
        sha, date, subject = line.split("|", 2)
        try:
            src = run(["git", "show", "%s:src/version.zig" % sha])
        except RuntimeError:
            continue
        match = re.search(r'VERSION = "([0-9.]+)"', src)
        if not match:
            continue
        version = match.group(1)
        if version in seen:
            # Одна версия — одна строка: берём коммит, где она появилась.
            continue
        seen.add(version)
        result.append((version, date, sha, subject))
    return result


def count_lines(path):
    """Строки кода и строки тестов отдельно.

    Раздельно, потому что иначе непонятно, растёт код или растут проверки.
    Тестом считается всё от `test "..." {` до закрывающей скобки того же уровня.
    """
    code = tests = 0
    for root, _dirs, files in os.walk(os.path.join(path, "src")):
        for name in files:
            if not name.endswith(".zig"):
                continue
            depth = None
            with io.open(os.path.join(root, name), encoding="utf-8", errors="replace") as f:
                for line in f:
                    stripped = line.strip()
                    if depth is None and re.match(r'^test\s+["{]', stripped):
                        depth = line.count("{") - line.count("}")
                        tests += 1
                        continue
                    if depth is not None:
                        tests += 1
                        depth += line.count("{") - line.count("}")
                        if depth <= 0:
                            depth = None
                        continue
                    code += 1
    build = os.path.join(path, "build.zig")
    if os.path.isfile(build):
        with io.open(build, encoding="utf-8", errors="replace") as f:
            code += sum(1 for _ in f)
    return code, tests


def build_at(sha):
    """Собрать релизный exe из коммита. Возвращает (размер, CRC32) или None."""
    if os.path.isdir(WORKTREE):
        run(["git", "worktree", "remove", "--force", WORKTREE], check=False)
        shutil.rmtree(WORKTREE, ignore_errors=True)
    run(["git", "worktree", "add", "--detach", WORKTREE, sha])
    try:
        code, tests = count_lines(WORKTREE)
        if not os.path.isfile(os.path.join(WORKTREE, "build.zig")):
            return None, None, code, tests
        out = subprocess.run([ZIG, "build", "-Doptimize=ReleaseFast"], cwd=WORKTREE,
                             capture_output=True, text=True, encoding="utf-8", errors="replace")
        exe = os.path.join(WORKTREE, "zig-out", "bin", "zigrec.exe")
        if out.returncode != 0 or not os.path.isfile(exe):
            return None, None, code, tests
        with open(exe, "rb") as f:
            data = f.read()
        return len(data), zlib.crc32(data) & 0xFFFFFFFF, code, tests
    finally:
        run(["git", "worktree", "remove", "--force", WORKTREE], check=False)
        shutil.rmtree(WORKTREE, ignore_errors=True)


def table(rows):
    out = []
    out.append("|| **Версия** || **Дата** || **Что изменилось** || **exe, байт** || **CRC32** || **Код** || **Тесты** ||")
    for version, date, subject, size, crc, code, tests in rows:
        size_text = "{:,}".format(size).replace(",", " ") if size else "не собирается"
        crc_text = "`%08X`" % crc if crc else "—"
        out.append("|| `%s` || %s || %s || %s || %s || %d || %d ||" % (
            version, date, subject, size_text, crc_text, code, tests))
    return "\n".join(out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--wiki", action="store_true", help="положить таблицу в вики Trac")
    parser.add_argument("--only", type=int, default=0, help="только N последних версий")
    args = parser.parse_args()

    items = versions()
    if args.only:
        items = items[-args.only:]

    rows = []
    for version, date, sha, subject in items:
        sys.stderr.write("собираю %s (%s)...\n" % (version, sha[:8]))
        sys.stderr.flush()
        size, crc, code, tests = build_at(sha)
        rows.append((version, date, subject, size, crc, code, tests))

    text = table(rows)
    print(text)

    if args.wiki:
        page = PAGE_TEMPLATE % (text, ZIG)
        # Текст страницы передаём файлом, а не строкой внутри кода: в нём есть
        # пути Windows с обратными косыми, и любая попытка их «зашить» в исходник
        # кончается ошибкой разбора escape-последовательностей.
        page_file = os.path.join(REPO, ".changelog-page.txt")
        script = os.path.join(REPO, ".changelog-wiki.py")
        with io.open(page_file, "w", encoding="utf-8") as f:
            f.write(page)
        with io.open(script, "w", encoding="utf-8") as f:
            f.write(WIKI_SCRIPT % (TRAC_ENV, page_file.replace("\\", "/")))
        out = subprocess.run([TRAC_PYTHON, script], capture_output=True, text=True,
                             encoding="utf-8", errors="replace")
        sys.stderr.write(out.stdout + out.stderr)
        os.remove(script)
        os.remove(page_file)


PAGE_TEMPLATE = """= Журнал версий =

Версия проекта — `A.B.C.D` по уровням канбана (см. [wiki:Versioning]).
Для каждой версии здесь: что изменилось, размер релизного `zigrec.exe`,
его контрольная сумма CRC32 и число строк кода.

**Числа считаются честно.** Каждая строка получена пересборкой того самого
коммита в отдельном рабочем каталоге, а не записана по памяти. Пересборка
любой версии должна дать тот же CRC32; если не даёт — что-то изменилось
в окружении сборки, и это повод разобраться.

Код и тесты считаются раздельно: иначе по одному числу не понять, растёт
сам инструмент или растут его проверки.

%s

Таблица делается инструментом `tools/changelog.py`; после бампа версии его
надо перезапустить. Сборка: `%s`.
"""

WIKI_SCRIPT = '''# -*- coding: utf-8 -*-
import sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
from trac.env import Environment
from trac.wiki.model import WikiPage
env = Environment(r"%s")
p = WikiPage(env, "Changelog")
p.text = io.open(r"%s", encoding="utf-8").read()
p.save("claude", "Журнал версий: размеры, CRC32, строки кода")
print("Changelog v%%d" %% p.version)
'''


if __name__ == "__main__":
    main()
