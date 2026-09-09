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
    \\  zigrec record ФАЙЛ [ключи]        записать экран в mp4
    \\        --sec N          сколько секунд писать (по умолчанию 5)
    \\        --fps N          частота кадров (по умолчанию 30)
    \\        --monitor N      номер монитора (по умолчанию 0)
    \\        --area x,y,ш,в   прямоугольник рабочего стола
    \\        --window ТЕКСТ   окно, найденное по части заголовка; область едет за окном
    \\  zigrec monitors                   какие есть мониторы
    \\  zigrec windows                    какие есть видимые окна
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
        } else if (parseRecordArgs(args[3..])) |opt| {
            code = try record(init.io, arena, w, args[2], opt);
        } else |err| {
            try w.print("ключи записи: {s}\n", .{@errorName(err)});
            try w.writeAll(usage);
            code = 2;
        }
    } else if (eq(cmd, "ui") or eq(cmd, "окно")) {
        zigrec.ui.run(arena) catch |err| {
            try w.print("окно не открылось: {s}\n", .{@errorName(err)});
            code = 1;
        };
    } else if (eq(cmd, "monitors")) {
        code = try listMonitors(arena, w);
    } else if (eq(cmd, "windows")) {
        code = try listWindows(w);
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

/// Что и как писать. Разбор ключей отделён от самой записи, чтобы его
/// можно было проверить тестом.
const RecordArgs = struct {
    seconds: u32 = 5,
    fps: u32 = 30,
    monitor: u32 = 0,
    area: ?zigrec.source.Rect = null,
    window: ?[]const u8 = null,
    cursor: bool = true,
    clicks: bool = true,
    preset: zigrec.encode.Preset = .text_ui,
    bitrate_kbps: ?u32 = null,
    gop: u32 = 60,
};

const ArgError = error{
    /// Ключ есть, значения нет.
    MissingValue,
    /// Значение не разобралось.
    BadValue,
    /// Ключ неизвестен.
    UnknownKey,
    /// Указано несколько источников сразу.
    OneSourceOnly,
};

fn parseRecordArgs(args: []const []const u8) ArgError!RecordArgs {
    var out = RecordArgs{};
    var sources: u32 = 0;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const key = args[i];
        const has_value = i + 1 < args.len;
        if (eq(key, "--sec")) {
            if (!has_value) return ArgError.MissingValue;
            i += 1;
            out.seconds = std.fmt.parseInt(u32, args[i], 10) catch return ArgError.BadValue;
        } else if (eq(key, "--fps")) {
            if (!has_value) return ArgError.MissingValue;
            i += 1;
            out.fps = std.fmt.parseInt(u32, args[i], 10) catch return ArgError.BadValue;
            if (out.fps == 0 or out.fps > 240) return ArgError.BadValue;
        } else if (eq(key, "--monitor")) {
            if (!has_value) return ArgError.MissingValue;
            i += 1;
            out.monitor = std.fmt.parseInt(u32, args[i], 10) catch return ArgError.BadValue;
            sources += 1;
        } else if (eq(key, "--area")) {
            if (!has_value) return ArgError.MissingValue;
            i += 1;
            out.area = zigrec.source.parseArea(args[i]) orelse return ArgError.BadValue;
            sources += 1;
        } else if (eq(key, "--window")) {
            if (!has_value) return ArgError.MissingValue;
            i += 1;
            out.window = args[i];
            sources += 1;
        } else if (eq(key, "--no-cursor")) {
            out.cursor = false;
        } else if (eq(key, "--no-clicks")) {
            out.clicks = false;
        } else if (eq(key, "--preset")) {
            if (!has_value) return ArgError.MissingValue;
            i += 1;
            if (eq(args[i], "text")) {
                out.preset = .text_ui;
            } else if (eq(args[i], "video")) {
                out.preset = .video;
            } else if (eq(args[i], "max")) {
                out.preset = .max;
            } else return ArgError.BadValue;
        } else if (eq(key, "--bitrate")) {
            if (!has_value) return ArgError.MissingValue;
            i += 1;
            const v = std.fmt.parseInt(u32, args[i], 10) catch return ArgError.BadValue;
            if (v < 100 or v > 200_000) return ArgError.BadValue;
            out.bitrate_kbps = v;
        } else if (eq(key, "--gop")) {
            if (!has_value) return ArgError.MissingValue;
            i += 1;
            const v = std.fmt.parseInt(u32, args[i], 10) catch return ArgError.BadValue;
            if (v < 1 or v > 600) return ArgError.BadValue;
            out.gop = v;
        } else {
            return ArgError.UnknownKey;
        }
    }
    if (sources > 1) return ArgError.OneSourceOnly;
    return out;
}

fn listMonitors(allocator: std.mem.Allocator, w: anytype) !u8 {
    const list = zigrec.source.listMonitors(allocator) catch |err| {
        try w.print("не получилось перечислить мониторы: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(list);
    for (list) |m| {
        try w.print("монитор {d}: {d}x{d} в точке ({d},{d}){s}\n", .{
            m.index,
            m.area.width,
            m.area.height,
            m.area.x,
            m.area.y,
            if (m.primary) " — основной" else "",
        });
    }
    const d = zigrec.source.desktopArea();
    try w.print("рабочий стол целиком: {d}x{d} в точке ({d},{d})\n", .{ d.width, d.height, d.x, d.y });
    return 0;
}

fn listWindows(w: anytype) !u8 {
    const c = zigrec.win32.c;
    var count: u32 = 0;
    var hwnd = c.GetTopWindow(null);
    while (hwnd != null and count < 40) : (hwnd = c.GetWindow(hwnd, c.GW_HWNDNEXT)) {
        if (c.IsWindowVisible(hwnd) == 0) continue;
        var title_buf: [1024]u8 = undefined;
        const title = zigrec.source.windowTitle(hwnd, &title_buf);
        if (title.len == 0) continue;
        const area = zigrec.source.windowArea(hwnd) catch continue;
        if (area.width < 100 or area.height < 100) continue;
        try w.print("{d}x{d} в точке ({d},{d})  {s}\n", .{
            area.width,
            area.height,
            area.x,
            area.y,
            title,
        });
        count += 1;
    }
    if (count == 0) try w.writeAll("видимых окон не нашлось\n");
    return 0;
}

fn record(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8, opt: RecordArgs) !u8 {
    try w.print("[rec] пишем в {s}: {d} с, до {d} кадров в секунду\n", .{ path, opt.seconds, opt.fps });
    try w.flush();

    // Окно ищем до открытия захвата: если его нет, незачем и начинать.
    var src: zigrec.source.Source = .{ .monitor = opt.monitor };
    if (opt.window) |title| {
        const hwnd = zigrec.source.findWindow(title) catch |err| {
            try w.print("[rec] ПРОВАЛ: окно «{s}» не найдено ({s})\n", .{ title, @errorName(err) });
            return 1;
        };
        src = .{ .window = hwnd };
    } else if (opt.area) |a| {
        src = .{ .area = a };
    }

    var cap = zigrec.capture.Capturer.open(allocator, .{ .output = opt.monitor }) catch |err| {
        try w.print("[rec] ПРОВАЛ: захват не открылся: {s}\n", .{@errorName(err)});
        try w.writeAll(explain(err));
        return 1;
    };
    defer cap.deinit();

    const screen = cap.frameSize();
    // Размер кадра выбирается один раз: кодировщик не умеет менять его на ходу.
    // Окно во время записи можно двигать — область поедет следом, — но если его
    // растянуть, в кадре останется прежний прямоугольник.
    const area = zigrec.source.resolve(src, screen) catch |err| {
        try w.print("[rec] ПРОВАЛ: источник не определился: {s}\n", .{@errorName(err)});
        return 1;
    };
    try w.print("[rec] экран {d}x{d}, путь {s}\n", .{ screen.width, screen.height, cap.backend().label() });
    try w.print("[rec] снимаем {d}x{d} в точке ({d},{d})\n", .{ area.width, area.height, area.x, area.y });

    const settings = zigrec.encode.Settings{
        .fps = opt.fps,
        .preset = opt.preset,
        .bitrate_kbps = opt.bitrate_kbps,
        .gop = opt.gop,
    };
    try w.print("[rec] пресет «{s}», битрейт {d} кбит/с, ключевой кадр каждые {d}\n", .{
        opt.preset.label(),
        settings.bitrate(area.width, area.height),
        opt.gop,
    });
    var enc = zigrec.encode.Writer.create(path, area.width, area.height, settings) catch |err| {
        try w.print("[rec] ПРОВАЛ: кодировщик не создался: {s}\n", .{@errorName(err)});
        return 1;
    };

    // Курсор дорисовываем сами: захват отдаёт рабочий стол без него. Для этого
    // нужен свой буфер — кадр захвата открыт только на чтение.
    var painter = zigrec.cursor.Painter.init(allocator, .{ .draw = opt.cursor, .clicks = opt.clicks });
    defer painter.deinit();
    const out_stride = area.width * 4;
    const canvas: ?[]u8 = if (opt.cursor)
        try allocator.alloc(u8, @as(usize, out_stride) * area.height)
    else
        null;
    defer if (canvas) |b| allocator.free(b);

    const started = zigrec.win32.nowNs();
    const until = started + @as(u64, opt.seconds) * std.time.ns_per_s;
    var written: u64 = 0;
    var moved: u64 = 0;
    var current = area;
    while (zigrec.win32.nowNs() < until) {
        const frame = cap.next(200) catch |err| {
            try w.print("[rec] ПРОВАЛ на захвате: {s}\n", .{@errorName(err)});
            enc.abort();
            return 1;
        } orelse continue;

        // Окно могли подвинуть: берём его положение заново, а размер держим
        // прежний — иначе кадр перестанет соответствовать заголовку файла.
        if (src.isWindow()) {
            if (zigrec.source.resolve(src, screen)) |now| {
                if (now.x != current.x or now.y != current.y) {
                    moved += 1;
                    current.x = now.x;
                    current.y = now.y;
                    current = current.clampTo(screen.width, screen.height);
                    current.width = area.width;
                    current.height = area.height;
                }
            } else |_| {}
        }

        const view = zigrec.capture_types.cropView(frame.pixels, frame.stride, current);

        var pixels = view;
        var pixels_stride = frame.stride;
        if (canvas) |buf| {
            // Копируем построчно в свой буфер и рисуем поверх курсор.
            var row: u32 = 0;
            while (row < area.height) : (row += 1) {
                const from = @as(usize, row) * frame.stride;
                if (from + out_stride > view.len) break;
                @memcpy(buf[@as(usize, row) * out_stride ..][0..out_stride], view[from..][0..out_stride]);
            }
            painter.poll(frame.timestamp_ns);
            painter.paint(
                buf,
                out_stride,
                .{ .width = area.width, .height = area.height },
                screen.x + current.x,
                screen.y + current.y,
                frame.timestamp_ns,
            );
            pixels = buf;
            pixels_stride = out_stride;
        }

        enc.writeFrame(pixels, pixels_stride, frame.timestamp_ns) catch |err| {
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

test "ключи записи: умолчания" {
    const a = try parseRecordArgs(&.{});
    try std.testing.expectEqual(@as(u32, 5), a.seconds);
    try std.testing.expectEqual(@as(u32, 30), a.fps);
    try std.testing.expectEqual(@as(u32, 0), a.monitor);
    try std.testing.expect(a.area == null);
    try std.testing.expect(a.window == null);
}

test "ключи записи: область и время" {
    const a = try parseRecordArgs(&.{ "--sec", "12", "--area", "10,20,640,480" });
    try std.testing.expectEqual(@as(u32, 12), a.seconds);
    try std.testing.expectEqual(@as(u32, 640), a.area.?.width);
}

test "ключи записи: окно по части заголовка" {
    const a = try parseRecordArgs(&.{ "--window", "Блокнот", "--fps", "60" });
    try std.testing.expectEqualStrings("Блокнот", a.window.?);
    try std.testing.expectEqual(@as(u32, 60), a.fps);
}

test "ключи записи: два источника сразу — ошибка" {
    try std.testing.expectError(
        ArgError.OneSourceOnly,
        parseRecordArgs(&.{ "--area", "0,0,10,10", "--window", "что-то" }),
    );
}

test "ключи записи: пропущенное значение и мусор" {
    try std.testing.expectError(ArgError.MissingValue, parseRecordArgs(&.{"--sec"}));
    try std.testing.expectError(ArgError.BadValue, parseRecordArgs(&.{ "--fps", "0" }));
    try std.testing.expectError(ArgError.BadValue, parseRecordArgs(&.{ "--fps", "999" }));
    try std.testing.expectError(ArgError.BadValue, parseRecordArgs(&.{ "--area", "плохо" }));
    try std.testing.expectError(ArgError.UnknownKey, parseRecordArgs(&.{"--луна"}));
}

test "ключи качества" {
    const a = try parseRecordArgs(&.{ "--preset", "max", "--gop", "30", "--bitrate", "8000" });
    try std.testing.expectEqual(zigrec.encode.Preset.max, a.preset);
    try std.testing.expectEqual(@as(u32, 30), a.gop);
    try std.testing.expectEqual(@as(u32, 8000), a.bitrate_kbps.?);
}

test "ключи качества: мусор отвергается" {
    try std.testing.expectError(ArgError.BadValue, parseRecordArgs(&.{ "--preset", "лучший" }));
    try std.testing.expectError(ArgError.BadValue, parseRecordArgs(&.{ "--bitrate", "10" }));
    try std.testing.expectError(ArgError.BadValue, parseRecordArgs(&.{ "--gop", "0" }));
}

test "ключи курсора" {
    const a = try parseRecordArgs(&.{ "--no-cursor", "--no-clicks" });
    try std.testing.expect(!a.cursor);
    try std.testing.expect(!a.clicks);
    const b = try parseRecordArgs(&.{});
    try std.testing.expect(b.cursor and b.clicks);
}
