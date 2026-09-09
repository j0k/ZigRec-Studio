//! Точка входа zigrec. Пока командная строка: окно записи появится в задаче #18.
const std = @import("std");
const Io = std.Io;
const zigrec = @import("zigrec");

const usage =
    \\zigrec — рекордер экрана и редактор
    \\
    \\  zigrec --version           версия и дата выпуска
    \\  zigrec --help              эта справка
    \\  zigrec capture-smoke [N] [dxgi|gdi]
    \\        самопроверка захвата: показать N кадров и прочитать их обратно с экрана
    \\
    \\Запись в файл ещё не подключена: идёт этап 0 (каркас и захват).
    \\Ход работ: http://127.0.0.1:8000/zigrecstudio-trac
    \\
;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var buf: [4096]u8 = undefined;
    var file_writer: Io.File.Writer = .init(.stdout(), init.io, &buf);
    const w = &file_writer.interface;

    const cmd: ?[]const u8 = if (args.len > 1) args[1] else null;
    var code: u8 = 0;

    if (cmd) |a| {
        if (std.mem.eql(u8, a, "--version") or std.mem.eql(u8, a, "-v")) {
            try w.print("zigrec {s} ({s})\n", .{ zigrec.version.VERSION, zigrec.version.VERSION_DATE });
        } else if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            try w.writeAll(usage);
        } else if (std.mem.eql(u8, a, "capture-smoke")) {
            const frames: u32 = if (args.len > 2)
                std.fmt.parseInt(u32, args[2], 10) catch 240
            else
                240;
            const backend: zigrec.capture.Backend = if (args.len > 3) blk: {
                if (std.mem.eql(u8, args[3], "dxgi")) break :blk .dxgi;
                if (std.mem.eql(u8, args[3], "gdi")) break :blk .gdi;
                break :blk .auto;
            } else .auto;
            code = try captureSmoke(arena, w, frames, backend);
        } else {
            try w.print("неизвестная команда: {s}\n\n", .{a});
            try w.writeAll(usage);
            code = 2;
        }
    } else {
        try w.writeAll(usage);
    }

    try w.flush();
    if (code != 0) std.process.exit(code);
}

fn captureSmoke(allocator: std.mem.Allocator, w: anytype, frames: u32, backend: zigrec.capture.Backend) !u8 {
    try w.print("[smoke] захват: показываем {d} кадров и читаем их обратно с экрана\n", .{frames});
    try w.flush();

    const report = zigrec.smoke.run(allocator, .{ .frames = frames, .backend = backend }) catch |err| {
        try w.print("[smoke] ПРОВАЛ: {s}\n", .{@errorName(err)});
        try w.writeAll(switch (err) {
            error.AccessDenied => "  захват запрещён: экран блокировки или выход занят другим процессом\n",
            error.NoDevice => "  не создаётся устройство D3D11: нет видеоадаптера или драйвера\n",
            error.NoOutput => "  нет такого монитора\n",
            else => "",
        });
        return 1;
    };

    try w.print("[smoke] экран {d}x{d}, путь {s}\n", .{ report.width, report.height, report.backend.label() });
    try w.print("[smoke] показано {d}, снято {d}, совпало номеров {d}\n", .{ report.shown, report.captured, report.matched });
    try w.print("[smoke] потери {d}, повторы {d}, порядок сбит {d} раз\n", .{
        report.tally.dropped,
        report.tally.duplicated,
        report.tally.out_of_order,
    });
    try w.print("[smoke] кадров в секунду {d:.1}, накоплено системой {d}, простоев {d}, пересозданий дубликации {d}\n", .{
        report.stats.fps(),
        report.stats.dropped,
        report.stats.idle,
        report.stats.recoveries,
    });

    if (!report.ok()) {
        try w.writeAll("[smoke] ПРОВАЛ: снято слишком мало кадров или номера не сходятся\n");
        return 1;
    }
    try w.writeAll("[smoke] ЗАХВАТ ЖИВОЙ\n");
    return 0;
}

test "версия ядра доступна из exe" {
    try std.testing.expect(zigrec.version.VERSION.len > 0);
    _ = zigrec.version.current();
}
