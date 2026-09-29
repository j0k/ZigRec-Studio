//! Вход для ярлыка: окно без консоли.
//!
//! Владелец (28.09.2026): «нажимаю на иконку — открывается консоль и быстро
//! закрывается, и дальше я вижу GUI».
//!
//! **Консоль создаёт Windows, а не мы.** У программы с признаком «консольная»
//! окно консоли заводится ДО первой нашей строки кода: спрятать её мы успеваем,
//! но мигнуть она успевает раньше. Изнутри такой программы этого не убрать —
//! убирается только признаком в самом exe.
//!
//! **Почему не сделать таким же `zigrec.exe`.** Признак «оконная» меняет не
//! только консоль: `cmd` перестаёт ЖДАТЬ такую программу. Всё, что зовёт
//! `zigrec record ... && следующий шаг`, поехало бы вперёд, не дождавшись
//! записи, — и вместе с этим развалился бы `check.cmd`, где полсотни шагов
//! идут один за другим. Поэтому exe два, как `python.exe` и `pythonw.exe`:
//! командная строка получает свой, ярлык — свой.
//!
//! Здесь нарочно нет ни разбора ключей, ни справки: всё это живёт в
//! `main.zig`. Один файл — окно, другой — команды.
const std = @import("std");
const builtin = @import("builtin");
const zigrec = @import("zigrec");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    // Ярлык может нести за собой файл: так открывают запись двойным щелчком
    // по mp4. Один путь — это «открой его в редакторе», иначе главное окно.
    //
    // В редактор идём, ТОЛЬКО если такой файл существует. Старый ярлык на
    // рабочем столе владельца нёс за собой слово «ui» (оно имело смысл для
    // консольного exe), и оконный принял его за имя файла: открывался
    // редактор с надписью «файл не читается». Чужой аргумент не должен
    // уводить от главного окна — в него и возвращаемся.
    // Слово «edit» — просьба открыть редактор. Её присылает само окно,
    // когда нажимают «Редактировать»: оно запускает нас же с этим словом.
    //
    // Владелец увидел, как «Edit» открывает ВТОРОЕ главное окно: оконный
    // exe слова не знал, принимал его за имя файла, файла такого не было —
    // и он честно открывал главное окно. Ошибка появилась вместе с
    // разделением на два exe: прежний, консольный, это слово понимал.
    if (args.len > 1 and (std.mem.eql(u8, args[1], "edit") or std.mem.eql(u8, args[1], "редактор"))) {
        const file: ?[]const u8 = if (args.len > 2 and args[2].len > 0) args[2] else null;
        zigrec.editor.run(arena, file) catch |err| {
            report("не открыть редактор", err);
        };
        return;
    }

    if (args.len > 1 and args[1].len > 0 and args[1][0] != '-' and fileThere(args[1])) {
        zigrec.editor.run(arena, args[1]) catch |err| {
            report("не открыть редактор", err);
        };
        return;
    }

    zigrec.ui.runFull(arena, false, false) catch |err| {
        report("не открыть окно", err);
    };
}

/// Есть ли такой файл на самом деле.
fn fileThere(path: []const u8) bool {
    if (builtin.os.tag != .windows) return false;
    var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return false;
    file.close(io);
    return true;
}

/// Сказать словами. Консоли у нас нет, поэтому говорим окном — иначе отказ
/// выглядел бы как «ничего не произошло», и человек жал бы по ярлыку снова.
fn report(what: []const u8, err: anyerror) void {
    if (builtin.os.tag != .windows) return;
    const c = zigrec.win32.c;
    var text: [256]u8 = undefined;
    const line = std.fmt.bufPrint(&text, "{s}: {s}", .{ what, @errorName(err) }) catch what;
    var wide: [512]u16 = undefined;
    const n = std.unicode.utf8ToUtf16Le(&wide, line) catch return;
    wide[n] = 0;
    _ = c.MessageBoxW(null, @ptrCast(&wide), zigrec.lang.tw("Zig-Rec Studio"), c.MB_ICONERROR);
}
