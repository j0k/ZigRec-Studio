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
    if (args.len > 1 and args[1].len > 0 and args[1][0] != '-') {
        zigrec.editor.run(arena, args[1]) catch |err| {
            report("не открыть редактор", err);
        };
        return;
    }

    zigrec.ui.runFull(arena, false, false) catch |err| {
        report("не открыть окно", err);
    };
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
