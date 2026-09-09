//! Точка входа zigrec. Пока командная строка: окно появится в задаче #18.
const std = @import("std");
const Io = std.Io;
const zigrec = @import("zigrec");

const usage =
    \\zigrec — рекордер экрана и редактор
    \\
    \\  zigrec --version     версия и дата выпуска
    \\  zigrec --help        эта справка
    \\
    \\Запись и редактор ещё не подключены: идёт этап 0 (каркас и захват).
    \\Ход работ: http://127.0.0.1:8000/zigrecstudio-trac
    \\
;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var buf: [4096]u8 = undefined;
    var file_writer: Io.File.Writer = .init(.stdout(), init.io, &buf);
    const w = &file_writer.interface;

    const arg: ?[]const u8 = if (args.len > 1) args[1] else null;
    var bad = false;

    if (arg) |a| {
        if (std.mem.eql(u8, a, "--version") or std.mem.eql(u8, a, "-v")) {
            try w.print("zigrec {s} ({s})\n", .{ zigrec.version.VERSION, zigrec.version.VERSION_DATE });
        } else if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            try w.writeAll(usage);
        } else {
            try w.print("неизвестный ключ: {s}\n\n", .{a});
            try w.writeAll(usage);
            bad = true;
        }
    } else {
        try w.writeAll(usage);
    }

    try w.flush();
    if (bad) std.process.exit(2);
}

test "версия ядра доступна из exe" {
    try std.testing.expect(zigrec.version.VERSION.len > 0);
    _ = zigrec.version.current();
}
