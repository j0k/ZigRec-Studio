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


def stable_bytes(data):
    """Обнулить в exe отметки времени сборки.

    Иначе CRC32 меряет не код, а минуту, в которую нажали «собрать»: Windows
    пишет в заголовок PE время сборки, и ещё по одной такой отметке — в каждую
    запись каталога отладочных данных. Проверено: две сборки из одного коммита
    различались ровно двадцатью байтами из миллиона, и все двадцать были этими
    отметками.

    Без обнуления столбец CRC32 был бы бесполезен: он не совпадал бы сам с собой
    при повторной сборке, и обещание «пересборка даёт то же число» не выполнялось
    бы никогда.
    """
    buf = bytearray(data)
    if buf[:2] != b"MZ":
        return bytes(buf)
    pe = int.from_bytes(buf[0x3C:0x40], "little")
    if buf[pe:pe + 4] != b"PE\0\0":
        return bytes(buf)

    # Отметка времени в заголовке файла.
    buf[pe + 8:pe + 12] = b"\0\0\0\0"

    sections_at = pe + 24
    magic = int.from_bytes(buf[sections_at:sections_at + 2], "little")
    # У 64-битного образа таблица каталогов данных начинается дальше.
    dirs_at = sections_at + (112 if magic == 0x20B else 96)
    section_count = int.from_bytes(buf[pe + 6:pe + 8], "little")
    opt_size = int.from_bytes(buf[pe + 20:pe + 22], "little")
    headers_at = sections_at + opt_size

    # Каталог отладочных данных — седьмая запись таблицы.
    debug_rva = int.from_bytes(buf[dirs_at + 6 * 8:dirs_at + 6 * 8 + 4], "little")
    debug_size = int.from_bytes(buf[dirs_at + 6 * 8 + 4:dirs_at + 6 * 8 + 8], "little")
    if debug_rva == 0 or debug_size == 0:
        return bytes(buf)

    # Адрес в памяти переводим в смещение в файле по таблице секций.
    debug_at = None
    for i in range(section_count):
        at = headers_at + i * 40
        va = int.from_bytes(buf[at + 12:at + 16], "little")
        vsize = int.from_bytes(buf[at + 8:at + 12], "little")
        raw = int.from_bytes(buf[at + 20:at + 24], "little")
        if va <= debug_rva < va + max(vsize, 1):
            debug_at = raw + (debug_rva - va)
            break
    if debug_at is None:
        return bytes(buf)

    # Каждая запись — 28 байт. Обнуляем и саму отметку времени, и то,
    # на что запись указывает: там лежит отпечаток конкретной сборки
    # (запись «Reproducible» — это хеш всего файла, он меняется от чего угодно).
    for i in range(debug_size // 28):
        at = debug_at + i * 28
        if at + 28 > len(buf):
            break
        buf[at + 4:at + 8] = b"\0\0\0\0"
        size = int.from_bytes(buf[at + 16:at + 20], "little")
        raw = int.from_bytes(buf[at + 24:at + 28], "little")
        if raw and size and raw + size <= len(buf):
            buf[raw:raw + size] = b"\0" * size
    return bytes(buf)


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
        # Размер берём настоящий, а сумму — по коду без отметок времени сборки.
        return len(data), zlib.crc32(stable_bytes(data)) & 0xFFFFFFFF, code, tests
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

    if args.wiki and args.only:
        # Иначе неполный пересчёт молча затирает страницу двумя строками:
        # проверено на себе, дважды. --only — только для консоли.
        sys.stderr.write("--only и --wiki вместе нельзя: в вики пойдёт обрезанная таблица\n")
        return 2

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
любой версии обязана дать тот же CRC32; если не даёт — что-то изменилось
в окружении сборки, и это повод разобраться.

Чтобы это обещание выполнялось, сумма считается **не по всему файлу**, а по
файлу без отметок времени сборки. Windows пишет время сборки в заголовок
`PE` и ещё по одной отметке — в каждую запись каталога отладочных данных,
вместе с отпечатком самого файла. Две сборки из одного коммита различались
ровно двадцатью байтами из миллиона, и все двадцать были этими отметками:
сумма по сырому файлу мерила бы минуту, в которую нажали «собрать», а не код.
Размер в таблице — настоящий, размер файла целиком.

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
    # Код возврата важен: инструмент зовут из скриптов, и отказ должен
    # быть отказом, а не строчкой в выводе при нулевом коде.
    sys.exit(main() or 0)
