//! Точка входа zigrec. Пока командная строка: окно записи появится в задаче #18.
const std = @import("std");
const Io = std.Io;
const zigrec = @import("zigrec");

const usage =
    \\zigrec — рекордер экрана и редактор
    \\
    \\  zigrec --version                  версия и дата выпуска
    \\  zigrec --help                     эта справка
    \\
    \\  zigrec record ФАЙЛ [СЕК] [FPS]    записать экран в mp4
    \\  zigrec verify-mp4 ФАЙЛ            разобрать mp4: боксы, быстрый старт, данные
    \\
    \\  zigrec capture-smoke [N] [dxgi|gdi]
    \\        самопроверка захвата: показать N кадров и прочитать их обратно с экрана
    \\  zigrec encode-smoke ФАЙЛ [N]
    \\        самопроверка кодирования: N кадров стенда в mp4 и разбор файла
    \\  zigrec verify-raw ФАЙЛ Ш В
    \\        прочитать таймкоды из распакованного BGRA-потока и сверить порядок
    \\
    \\Ход работ: http://127.0.0.1:8000/zigrecstudio-trac
    \\
;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var buf: [8192]u8 = undefined;
    var file_writer: Io.File.Writer = .init(.stdout(), init.io, &buf);
    const w = &file_writer.interface;

    const cmd: []const u8 = if (args.len > 1) args[1] else "";
    var code: u8 = 0;

    if (args.len <= 1 or eq(cmd, "--help") or eq(cmd, "-h")) {
        try w.writeAll(usage);
    } else if (eq(cmd, "--version") or eq(cmd, "-v")) {
        try w.print("zigrec {s} ({s})\n", .{ zigrec.version.VERSION, zigrec.version.VERSION_DATE });
    } else if (eq(cmd, "capture-smoke")) {
        const frames = argInt(args, 2, 240);
        const backend: zigrec.capture.Backend = if (args.len > 3) blk: {
            if (eq(args[3], "dxgi")) break :blk .dxgi;
            if (eq(args[3], "gdi")) break :blk .gdi;
            break :blk .auto;
        } else .auto;
        code = try captureSmoke(arena, w, frames, backend);
    } else if (eq(cmd, "encode-smoke")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к файлу\n");
            code = 2;
        } else {
            code = try encodeSmoke(init.io, arena, w, args[2], argInt(args, 3, 120));
        }
    } else if (eq(cmd, "verify-mp4")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к файлу\n");
            code = 2;
        } else {
            code = try verifyMp4(init.io, arena, w, args[2]);
        }
    } else if (eq(cmd, "verify-raw")) {
        if (args.len < 5) {
            try w.writeAll("нужны файл, ширина и высота\n");
            code = 2;
        } else {
            code = try verifyRaw(init.io, arena, w, args[2], argInt(args, 3, 0), argInt(args, 4, 0));
        }
    } else if (eq(cmd, "record")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к файлу\n");
            code = 2;
        } else {
            code = try record(init.io, arena, w, args[2], argInt(args, 3, 5), argInt(args, 4, 30));
        }
    } else {
        try w.print("неизвестная команда: {s}\n\n", .{cmd});
        try w.writeAll(usage);
        code = 2;
    }

    try w.flush();
    if (code != 0) std.process.exit(code);
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn argInt(args: []const []const u8, index: usize, default: u32) u32 {
    if (args.len <= index) return default;
    return std.fmt.parseInt(u32, args[index], 10) catch default;
}

// ------------------------------------------------------------ самопроверки

fn captureSmoke(allocator: std.mem.Allocator, w: anytype, frames: u32, backend: zigrec.capture.Backend) !u8 {
    try w.print("[smoke] захват: показываем {d} кадров и читаем их обратно с экрана\n", .{frames});
    try w.flush();

    const report = zigrec.smoke.run(allocator, .{ .frames = frames, .backend = backend }) catch |err| {
        try w.print("[smoke] ПРОВАЛ: {s}\n", .{@errorName(err)});
        try w.writeAll(explain(err));
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

/// Кодирование без захвата: кадры берём у стенда, поэтому результат
/// повторяем и не зависит ни от экрана, ни от того, что на нём происходит.
fn encodeSmoke(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8, frames: u32) !u8 {
    const bench = zigrec.testbench;
    const width: u32 = bench.min_width;
    const height: u32 = 64;
    const fps: u32 = 30;

    try w.print("[encode] {d} кадров стенда {d}x{d} в {s}\n", .{ frames, width, height, path });
    try w.flush();

    const screen = try bench.Screen.init(width, height, fps);
    const buf = try allocator.alloc(u8, screen.frameBytes());
    defer allocator.free(buf);

    var enc = zigrec.encode.Writer.create(path, width, height, .{ .fps = fps }) catch |err| {
        try w.print("[encode] ПРОВАЛ на создании писателя: {s}\n", .{@errorName(err)});
        return 1;
    };

    const frame_ns: u64 = std.time.ns_per_s / fps;
    var i: u32 = 1;
    while (i <= frames) : (i += 1) {
        try screen.render(buf, i);
        enc.writeFrame(buf, width * 4, frame_ns * i) catch |err| {
            try w.print("[encode] ПРОВАЛ на кадре {d}: {s}\n", .{ i, @errorName(err) });
            enc.abort();
            return 1;
        };
    }

    const summary = enc.finish() catch |err| {
        try w.print("[encode] ПРОВАЛ на закрытии файла: {s}\n", .{@errorName(err)});
        return 1;
    };
    try w.print("[encode] записано кадров {d}, длительность {d:.2} с\n", .{
        summary.frames,
        @as(f64, @floatFromInt(summary.duration_ns)) / @as(f64, std.time.ns_per_s),
    });

    try fastStart(io, allocator, w, path);

    const ok = try verifyMp4(io, allocator, w, path);
    if (ok != 0) return ok;
    if (summary.frames + 1 < frames) {
        try w.writeAll("[encode] ПРОВАЛ: до файла дошли не все кадры\n");
        return 1;
    }
    try w.writeAll("[encode] ФАЙЛ ГОДНЫЙ\n");
    return 0;
}

/// Перенести moov в начало: своими руками, потому что штатный ключ
/// Media Foundation портит файл (см. src/encode.zig).
fn fastStart(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8) !void {
    const moved = zigrec.mp4.makeFastStart(io, allocator, path) catch |err| {
        try w.print("[mp4] не удалось перенести moov в начало: {s}\n", .{@errorName(err)});
        return;
    };
    if (moved) try w.writeAll("[mp4] moov перенесён в начало файла\n");
}

fn verifyMp4(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8) !u8 {
    var boxes: [64]zigrec.mp4.Box = undefined;
    const layout = zigrec.mp4.inspect(io, allocator, path, &boxes) catch |err| {
        try w.print("[mp4] ПРОВАЛ: {s} ({s})\n", .{ @errorName(err), path });
        return 1;
    };

    try w.print("[mp4] {s}: {d} байт, боксов {d}\n", .{ path, layout.total, layout.boxes.len });
    for (layout.boxes) |b| {
        try w.print("[mp4]   {d:>10}  {s}  {d}\n", .{ b.offset, b.kind, b.size });
    }
    if (!layout.playable()) {
        try w.writeAll("[mp4] ПРОВАЛ: нет moov или пустой mdat — файл не играется\n");
        return 1;
    }
    if (!layout.fastStart()) {
        try w.writeAll("[mp4] ПРОВАЛ: moov после mdat — браузер не начнёт играть, пока не скачает целиком\n");
        return 1;
    }
    try w.print("[mp4] moov перед mdat, данных {d} байт\n", .{layout.mdat_size});
    return 0;
}

/// Проверка распакованного потока: сюда попадает то, что вернул чужой
/// декодер. Так видно, пережил ли таймкод кодирование.
fn verifyRaw(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8, width: u32, height: u32) !u8 {
    if (width == 0 or height == 0) {
        try w.writeAll("[raw] нужны ширина и высота\n");
        return 2;
    }
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1 << 30)) catch |err| {
        try w.print("[raw] ПРОВАЛ: не читается {s}: {s}\n", .{ path, @errorName(err) });
        return 1;
    };
    defer allocator.free(data);

    const stride = width * 4;
    const frame_bytes = @as(usize, stride) * height;
    if (frame_bytes == 0 or data.len < frame_bytes) {
        try w.writeAll("[raw] ПРОВАЛ: в потоке нет ни одного кадра\n");
        return 1;
    }

    const count = data.len / frame_bytes;
    var seen = try allocator.alloc(u32, count);
    defer allocator.free(seen);
    var n: usize = 0;
    for (0..count) |k| {
        const frame = data[k * frame_bytes ..][0..frame_bytes];
        seen[n] = zigrec.testbench.readIndex(frame, width, stride) catch continue;
        n += 1;
    }

    const t = zigrec.testbench.tally(seen[0..n]);
    try w.print("[raw] кадров {d}, прочитано номеров {d}\n", .{ count, n });
    try w.print("[raw] потери {d}, повторы {d}, порядок сбит {d} раз\n", .{ t.dropped, t.duplicated, t.out_of_order });
    if (n > 0) try w.print("[raw] первый номер {d}, последний {d}\n", .{ seen[0], seen[n - 1] });

    if (n < count or !t.ok()) {
        try w.writeAll("[raw] ПРОВАЛ: таймкоды не пережили кодирование\n");
        return 1;
    }
    try w.writeAll("[raw] ТАЙМКОДЫ ЦЕЛЫ\n");
    return 0;
}

// ------------------------------------------------------------------ запись

fn record(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8, seconds: u32, fps: u32) !u8 {
    try w.print("[rec] пишем экран в {s}: {d} с, до {d} кадров в секунду\n", .{ path, seconds, fps });
    try w.flush();

    var cap = zigrec.capture.Capturer.open(allocator, .{}) catch |err| {
        try w.print("[rec] ПРОВАЛ: захват не открылся: {s}\n", .{@errorName(err)});
        try w.writeAll(explain(err));
        return 1;
    };
    defer cap.deinit();

    const size = cap.frameSize();
    try w.print("[rec] экран {d}x{d}, путь {s}\n", .{ size.width, size.height, cap.backend().label() });

    var enc = zigrec.encode.Writer.create(path, size.width, size.height, .{ .fps = fps }) catch |err| {
        try w.print("[rec] ПРОВАЛ: кодировщик не создался: {s}\n", .{@errorName(err)});
        return 1;
    };

    const started = zigrec.win32.nowNs();
    const until = started + @as(u64, seconds) * std.time.ns_per_s;
    var written: u64 = 0;
    while (zigrec.win32.nowNs() < until) {
        const frame = cap.next(200) catch |err| {
            try w.print("[rec] ПРОВАЛ на захвате: {s}\n", .{@errorName(err)});
            enc.abort();
            return 1;
        } orelse continue;
        enc.writeFrame(frame.pixels, frame.stride, frame.timestamp_ns) catch |err| {
            try w.print("[rec] ПРОВАЛ на кодировании: {s}\n", .{@errorName(err)});
            cap.release();
            enc.abort();
            return 1;
        };
        written += 1;
        cap.release();
    }

    const summary = enc.finish() catch |err| {
        try w.print("[rec] ПРОВАЛ на закрытии файла: {s}\n", .{@errorName(err)});
        return 1;
    };
    const stats = cap.stats();
    const secs = @as(f64, @floatFromInt(zigrec.win32.nowNs() - started)) / @as(f64, std.time.ns_per_s);
    try w.print("[rec] кадров записано {d} за {d:.1} с ({d:.1} в секунду), простоев {d}, потерь {d}\n", .{
        summary.frames,
        secs,
        @as(f64, @floatFromInt(summary.frames)) / @max(secs, 0.001),
        stats.idle,
        stats.dropped,
    });
    if (summary.frames == 0) {
        try w.writeAll("[rec] ПРОВАЛ: за всё время экран не отдал ни одного кадра\n");
        return 1;
    }
    try fastStart(io, allocator, w, path);
    return verifyMp4(io, allocator, w, path);
}

fn explain(err: anyerror) []const u8 {
    return switch (err) {
        error.AccessDenied => "  захват запрещён: экран блокировки или выход занят другим процессом\n",
        error.NoDevice => "  не создаётся устройство D3D11: нет видеоадаптера или драйвера\n",
        error.NoOutput => "  нет такого монитора\n",
        error.Unsupported => "  захват возможен только на Windows\n",
        else => "",
    };
}

test "версия ядра доступна из exe" {
    try std.testing.expect(zigrec.version.VERSION.len > 0);
    _ = zigrec.version.current();
}

test "разбор числового аргумента" {
    const args = [_][]const u8{ "zigrec", "record", "out.mp4", "12", "плохо" };
    try std.testing.expectEqual(@as(u32, 12), argInt(&args, 3, 5));
    try std.testing.expectEqual(@as(u32, 30), argInt(&args, 4, 30));
    try std.testing.expectEqual(@as(u32, 7), argInt(&args, 9, 7));
}
