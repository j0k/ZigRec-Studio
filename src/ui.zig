//! Окно записи: кнопки, индикатор, трей, горячие клавиши, выбор области рамкой.
//!
//! Задачи #18 и #19.
//!
//! **Решение по оконному стеку (задача #18).** Взяли чистый Win32 с обычными
//! системными элементами, без Direct2D и без ImGui. Причины: exe остаётся
//! маленьким и без зависимостей, элементы выглядят так же, как во всей системе,
//! и рисовать здесь нечего — это панель из шести кнопок и строки состояния.
//! Direct2D понадобится редактору, когда дойдёт дело до таймлайна; тогда его и
//! добавим рядом, а не потащим сейчас ради одной панели.
//!
//! Всё — широкие версии функций (`CreateWindowExW`, `GetWindowTextW`):
//! узкие отдают текст в кодировке системы, и русские подписи превращаются в мусор.
const std = @import("std");
const builtin = @import("builtin");
const win32 = @import("win32.zig");
const c = win32.c;
const recorder = @import("recorder.zig");
const source = @import("source.zig");
const capture_types = @import("capture_types.zig");
const version = @import("version.zig");
const errors = @import("errors.zig");

pub const Rect = capture_types.Rect;

const id_record = 101;
const id_pause = 102;
const id_area = 103;
const id_full = 104;
const id_cursor = 105;
const id_open = 106;
const id_fps = 107;
const id_preset = 108;
const id_area_rec = 109;

const hotkey_record = 1;
const hotkey_pause = 2;

const wm_tray = c.WM_APP + 1;
const timer_tick = 1;

/// Состояние окна. Одно на процесс: окно тоже одно.
const App = struct {
    allocator: std.mem.Allocator,
    rec: recorder.Recorder,
    settings: recorder.Settings = .{},
    /// Что снимаем. `null` — весь экран.
    area: ?Rect = null,
    window_title: ?[]const u8 = null,
    out_dir: []const u8 = "",
    last_path: [std.fs.max_path_bytes]u8 = undefined,
    last_path_len: usize = 0,
    counter: u32 = 1,

    hwnd: c.HWND = null,
    status: c.HWND = null,
    btn_record: c.HWND = null,
    btn_pause: c.HWND = null,
    btn_open: c.HWND = null,
    chk_cursor: c.HWND = null,
    cb_fps: c.HWND = null,
    cb_preset: c.HWND = null,
    lbl_file: c.HWND = null,
    tray_added: bool = false,
    tray_tip: [128]u8 = @splat(0),
};

var app: App = undefined;

/// `MAKEINTRESOURCE` — макрос, и translate-c его не переносит. Номера
/// стандартных курсоров и значков не менялись с девяностых.
fn intResource(n: u16) [*c]const u16 {
    // Не comptime: на известном во время компиляции числе Zig требует
    // доказательства выравнивания, а здесь это не адрес, а номер ресурса.
    var addr: usize = n;
    addr += 0;
    return @ptrFromInt(addr);
}
fn idcArrow() [*c]const u16 {
    return intResource(32512);
}
fn idcCross() [*c]const u16 {
    return intResource(32515);
}
fn idiInfo() [*c]const u16 {
    return intResource(32516);
}

fn wide(comptime s: []const u8) [:0]const u16 {
    return std.unicode.utf8ToUtf16LeStringLiteral(s);
}

fn setText(hwnd: c.HWND, text: []const u8) void {
    var buf: [512]u16 = undefined;
    const n = std.unicode.utf8ToUtf16Le(&buf, text) catch return;
    buf[n] = 0;
    _ = c.SetWindowTextW(hwnd, @ptrCast(&buf));
}

/// Кнопка. Номер ставим отдельным вызовом, а не через параметр меню:
/// туда Windows ждёт указатель, и малый номер вроде 101 — это невыровненный
/// адрес, на котором Zig честно падает.
fn button(parent: c.HWND, comptime text: []const u8, id: c_int, x: i32, y: i32, w: i32, h: i32, style: u32) c.HWND {
    const hwnd = c.CreateWindowExW(
        0,
        wide("BUTTON"),
        wide(text),
        @as(c.DWORD, @bitCast(@as(u32, c.WS_CHILD | c.WS_VISIBLE | c.WS_TABSTOP) | style)),
        x,
        y,
        w,
        h,
        parent,
        null,
        @ptrCast(c.GetModuleHandleW(null)),
        null,
    );
    // GWLP_ID = -12
    _ = c.SetWindowLongPtrW(hwnd, -12, id);
    return hwnd;
}

/// Подпись рядом с элементом.
fn label(parent: c.HWND, comptime text: []const u8, x: i32, y: i32, w: i32, h: i32) c.HWND {
    return c.CreateWindowExW(
        0,
        wide("STATIC"),
        wide(text),
        c.WS_CHILD | c.WS_VISIBLE,
        x,
        y,
        w,
        h,
        parent,
        null,
        @ptrCast(c.GetModuleHandleW(null)),
        null,
    );
}

/// Выпадающий список без поля ввода.
fn combo(parent: c.HWND, id: c_int, x: i32, y: i32, w: i32, h: i32) c.HWND {
    const hwnd = c.CreateWindowExW(
        0,
        wide("COMBOBOX"),
        wide(""),
        @as(c.DWORD, @bitCast(@as(u32, c.WS_CHILD | c.WS_VISIBLE | c.WS_TABSTOP | c.CBS_DROPDOWNLIST))),
        x,
        y,
        w,
        h,
        parent,
        null,
        @ptrCast(c.GetModuleHandleW(null)),
        null,
    );
    _ = c.SetWindowLongPtrW(hwnd, -12, id);
    return hwnd;
}

fn addItem(combo_hwnd: c.HWND, text: []const u8) void {
    var buf: [64]u16 = undefined;
    const n = std.unicode.utf8ToUtf16Le(&buf, text) catch return;
    buf[n] = 0;
    _ = c.SendMessageW(combo_hwnd, c.CB_ADDSTRING, 0, @bitCast(@intFromPtr(&buf)));
}

fn applyFont(hwnd: c.HWND) void {
    const font = c.GetStockObject(c.DEFAULT_GUI_FONT);
    _ = c.SendMessageW(hwnd, c.WM_SETFONT, @intFromPtr(font), 1);
}

/// Куда писать по умолчанию: `Видео\ZigRecStudio` в профиле пользователя.
fn defaultDir(allocator: std.mem.Allocator) ![]const u8 {
    var wide_home: [512]u16 = undefined;
    const n = c.GetEnvironmentVariableW(wide("USERPROFILE"), &wide_home, wide_home.len);
    if (n == 0 or n >= wide_home.len) return try allocator.dupe(u8, ".");
    var home: [1024]u8 = undefined;
    const len = std.unicode.utf16LeToUtf8(&home, wide_home[0..n]) catch
        return try allocator.dupe(u8, ".");
    const dir = try std.fmt.allocPrint(allocator, "{s}\\Videos\\ZigRecStudio", .{home[0..len]});
    // Каталог создаём через Windows: он сам разберётся с уже существующим
    // и не потребует тащить сюда интерфейс ввода-вывода.
    var wide_dir: [1024]u16 = undefined;
    const dn = std.unicode.utf8ToUtf16Le(&wide_dir, dir) catch return dir;
    wide_dir[dn] = 0;
    _ = c.CreateDirectoryW(@ptrCast(&wide_dir), null);
    return dir;
}

fn nextPath(out: []u8) ![]const u8 {
    var name_buf: [128]u8 = undefined;
    const name = try recorder.buildName(&name_buf, "zigrec-%d-%t.mp4", recorder.DateTime.now(), app.counter);
    return std.fmt.bufPrint(out, "{s}\\{s}", .{ app.out_dir, name });
}

fn startRecording() void {
    if (app.rec.isBusy()) return;
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = nextPath(&path_buf) catch return;
    @memcpy(app.last_path[0..path.len], path);
    app.last_path_len = path.len;

    const src: source.Source = if (app.area) |a| .{ .area = a } else .{ .monitor = app.settings.monitor };
    // Файл проверяем до захвата: занятый плеером файл — частая причина,
    // и узнать о ней надо сразу, а не в конце записи.
    errors.ensureWritable(path) catch |err| {
        setText(app.status, errors.explain(err));
        return;
    };
    app.rec.start(path, src, app.settings) catch |err| {
        setText(app.status, errors.explain(err));
        return;
    };
    app.counter += 1;
    setText(app.btn_record, "Стоп (F9)");
    _ = c.EnableWindow(app.btn_pause, 1);
}

fn stopRecording() void {
    if (!app.rec.isBusy()) return;
    app.rec.stop();
    setText(app.btn_record, "Записать экран (F9)");
    setText(app.btn_pause, "Пауза (F10)");
    _ = c.EnableWindow(app.btn_pause, 0);
    _ = c.EnableWindow(app.btn_open, 1);
}

fn togglePause() void {
    if (!app.rec.isBusy()) return;
    app.rec.pause();
}

fn openLastFile() void {
    if (app.last_path_len == 0) return;
    var buf: [std.fs.max_path_bytes]u16 = undefined;
    const n = std.unicode.utf8ToUtf16Le(&buf, app.last_path[0..app.last_path_len]) catch return;
    buf[n] = 0;
    _ = c.ShellExecuteW(null, wide("open"), @ptrCast(&buf), null, null, c.SW_SHOWNORMAL);
}

fn updateStatus() void {
    const p = app.rec.snapshot();
    var buf: [512]u8 = undefined;
    const secs = @as(f64, @floatFromInt(p.elapsed_ns)) / @as(f64, std.time.ns_per_s);
    var src_buf: [64]u8 = undefined;
    const source_text = if (app.area) |a|
        std.fmt.bufPrint(&src_buf, "область {d}x{d}", .{ a.width, a.height }) catch "область"
    else
        "весь экран";

    const text = if (p.state == .idle) blk: {
        if (p.message_len > 0) {
            break :blk std.fmt.bufPrint(&buf, "{s}\r\n{s} · источник: {s}", .{
                p.message_text(),
                hotkey_note,
                source_text,
            }) catch "готов";
        }
        break :blk std.fmt.bufPrint(&buf, "готов · {s}\r\nисточник: {s}", .{
            hotkey_note,
            source_text,
        }) catch "готов";
    } else std.fmt.bufPrint(&buf, "{s}  {d:0>2}:{d:0>2}\r\nкадров {d}, потерь {d}, путь {s}, кадр {d}x{d}", .{
        p.state.label(),
        @as(u32, @intFromFloat(secs)) / 60,
        @as(u32, @intFromFloat(secs)) % 60,
        p.frames,
        p.dropped,
        p.backend.label(),
        p.area.width,
        p.area.height,
    }) catch "идёт запись";

    setText(app.status, text);
    setText(app.btn_pause, if (p.state == .paused) "Продолжить (F10)" else "Пауза (F10)");
    updateTrayTip(p, secs);

    // Имя файла на виду: человек должен знать, куда пишется, не открывая папку.
    var file_buf: [std.fs.max_path_bytes]u8 = undefined;
    if (p.state == .idle) {
        if (nextPath(&file_buf)) |path| {
            setText(app.lbl_file, std.fs.path.basename(path));
        } else |_| {}
    } else if (app.last_path_len > 0) {
        setText(app.lbl_file, std.fs.path.basename(app.last_path[0..app.last_path_len]));
    }

    // Кнопка вернулась в исходное, если запись кончилась сама.
    if (p.state == .idle) {
        setText(app.btn_record, "Записать экран (F9)");
        _ = c.EnableWindow(app.btn_pause, 0);
    }
}

/// Как в итоге зарегистрировались горячие клавиши.
var hotkey_note: []const u8 = "";

/// Горячие клавиши. Сначала пробуем голые F9 и F10: их удобно нажимать вслепую.
/// Если заняты другой программой — а F9 занимают часто, — берём Ctrl+Alt+F9
/// и говорим об этом в окне. Молча остаться без горячих клавиш нельзя:
/// человек нажмёт и решит, что запись идёт.
fn registerHotkeys(hwnd: c.HWND) void {
    const mod_ctrl_alt: c.UINT = c.MOD_CONTROL | c.MOD_ALT;
    const plain_rec = c.RegisterHotKey(hwnd, hotkey_record, 0, c.VK_F9) != 0;
    const plain_pause = c.RegisterHotKey(hwnd, hotkey_pause, 0, c.VK_F10) != 0;
    if (plain_rec and plain_pause) {
        hotkey_note = "F9 — запись, F10 — пауза";
        return;
    }
    if (plain_rec) _ = c.UnregisterHotKey(hwnd, hotkey_record);
    if (plain_pause) _ = c.UnregisterHotKey(hwnd, hotkey_pause);

    const alt_rec = c.RegisterHotKey(hwnd, hotkey_record, mod_ctrl_alt, c.VK_F9) != 0;
    const alt_pause = c.RegisterHotKey(hwnd, hotkey_pause, mod_ctrl_alt, c.VK_F10) != 0;
    if (alt_rec and alt_pause) {
        hotkey_note = "F9 занята, работают Ctrl+Alt+F9 и Ctrl+Alt+F10";
        return;
    }
    hotkey_note = "горячие клавиши заняты, работают только кнопки";
}

/// Подсказка значка в трее: состояние видно, даже когда окно свёрнуто
/// и человек работает на другом рабочем столе.
fn updateTrayTip(p: recorder.Progress, secs: f64) void {
    if (!app.tray_added) return;
    var text_buf: [128]u8 = undefined;
    const text = if (p.state == .idle)
        std.fmt.bufPrint(&text_buf, "ZigRecStudio — {s}", .{p.state.label()}) catch return
    else
        std.fmt.bufPrint(&text_buf, "ZigRecStudio — {s} {d:0>2}:{d:0>2}, кадров {d}", .{
            p.state.label(),
            @as(u32, @intFromFloat(secs)) / 60,
            @as(u32, @intFromFloat(secs)) % 60,
            p.frames,
        }) catch return;
    if (std.mem.eql(u8, text, app.tray_tip[0..text.len])) return;
    @memcpy(app.tray_tip[0..text.len], text);

    var nid = std.mem.zeroes(c.NOTIFYICONDATAW);
    nid.cbSize = @sizeOf(c.NOTIFYICONDATAW);
    nid.hWnd = app.hwnd;
    nid.uID = 1;
    nid.uFlags = c.NIF_TIP;
    var wide_tip: [128]u16 = undefined;
    const n = std.unicode.utf8ToUtf16Le(&wide_tip, text) catch return;
    @memcpy(nid.szTip[0..n], wide_tip[0..n]);
    nid.szTip[n] = 0;
    _ = c.Shell_NotifyIconW(c.NIM_MODIFY, &nid);
}

fn addTray(hwnd: c.HWND) void {
    var nid = std.mem.zeroes(c.NOTIFYICONDATAW);
    nid.cbSize = @sizeOf(c.NOTIFYICONDATAW);
    nid.hWnd = hwnd;
    nid.uID = 1;
    nid.uFlags = c.NIF_ICON | c.NIF_MESSAGE | c.NIF_TIP;
    nid.uCallbackMessage = wm_tray;
    nid.hIcon = c.LoadIconW(null, idiInfo()); // IDI_INFORMATION
    const tip = wide("ZigRecStudio");
    @memcpy(nid.szTip[0..tip.len], tip);
    app.tray_added = c.Shell_NotifyIconW(c.NIM_ADD, &nid) != 0;
}

fn removeTray(hwnd: c.HWND) void {
    if (!app.tray_added) return;
    var nid = std.mem.zeroes(c.NOTIFYICONDATAW);
    nid.cbSize = @sizeOf(c.NOTIFYICONDATAW);
    nid.hWnd = hwnd;
    nid.uID = 1;
    _ = c.Shell_NotifyIconW(c.NIM_DELETE, &nid);
    app.tray_added = false;
}

fn wndProc(hwnd: c.HWND, msg: c.UINT, wp: c.WPARAM, lp: c.LPARAM) callconv(.winapi) c.LRESULT {
    switch (msg) {
        c.WM_CREATE => {
            app.hwnd = hwnd;
            app.status = c.CreateWindowExW(
                0,
                wide("STATIC"),
                wide("готов"),
                c.WS_CHILD | c.WS_VISIBLE,
                14,
                14,
                430,
                40,
                hwnd,
                null,
                @ptrCast(c.GetModuleHandleW(null)),
                null,
            );
            app.btn_record = button(hwnd, "Записать экран (F9)", id_record, 14, 66, 176, 32, c.BS_DEFPUSHBUTTON);
            _ = button(hwnd, "Записать область…", id_area_rec, 198, 66, 160, 32, 0);
            app.btn_pause = button(hwnd, "Пауза (F10)", id_pause, 366, 66, 126, 32, 0);

            _ = button(hwnd, "Выбрать область…", id_area, 14, 106, 176, 30, 0);
            _ = button(hwnd, "Весь экран", id_full, 198, 106, 160, 30, 0);
            app.chk_cursor = button(hwnd, "Курсор и клики", id_cursor, 366, 106, 126, 30, c.BS_AUTOCHECKBOX);

            _ = label(hwnd, "Кадров/с", 14, 152, 90, 20);
            app.cb_fps = combo(hwnd, id_fps, 104, 148, 84, 200);
            for ([_][]const u8{ "15", "24", "30", "60" }) |item| addItem(app.cb_fps, item);
            _ = c.SendMessageW(app.cb_fps, c.CB_SETCURSEL, 2, 0);

            _ = label(hwnd, "Качество", 206, 152, 90, 20);
            app.cb_preset = combo(hwnd, id_preset, 296, 148, 130, 200);
            for ([_][]const u8{ "текст", "видео", "максимум" }) |item| addItem(app.cb_preset, item);
            _ = c.SendMessageW(app.cb_preset, c.CB_SETCURSEL, 0, 0);

            app.btn_open = button(hwnd, "Открыть запись", id_open, 366, 190, 126, 30, 0);
            app.lbl_file = label(hwnd, "", 14, 196, 344, 22);
            _ = c.SendMessageW(app.chk_cursor, c.BM_SETCHECK, 1, 0);
            _ = c.EnableWindow(app.btn_pause, 0);
            _ = c.EnableWindow(app.btn_open, 0);

            for ([_]c.HWND{ app.status, app.btn_record, app.btn_pause, app.btn_open, app.chk_cursor, app.cb_fps, app.cb_preset, app.lbl_file }) |h| applyFont(h);
            for ([_]c_int{ id_area, id_full, id_area_rec }) |id| applyFont(c.GetDlgItem(hwnd, id));

            registerHotkeys(hwnd);
            addTray(hwnd);
            _ = c.SetTimer(hwnd, timer_tick, 200, null);
            return 0;
        },
        c.WM_COMMAND => {
            const id = wp & 0xFFFF;
            switch (id) {
                id_record => if (app.rec.isBusy()) stopRecording() else startRecording(),
                id_pause => togglePause(),
                id_open => openLastFile(),
                id_full => {
                    app.area = null;
                    updateStatus();
                },
                id_area => {
                    if (selectArea()) |r| {
                        app.area = r;
                        updateStatus();
                    }
                },
                id_area_rec => {
                    // Два действия: нажали кнопку — обвели рамку — пошла запись.
                    if (app.rec.isBusy()) {
                        stopRecording();
                    } else if (selectArea()) |r| {
                        app.area = r;
                        startRecording();
                    }
                },
                id_fps => {
                    const sel = c.SendMessageW(app.cb_fps, c.CB_GETCURSEL, 0, 0);
                    app.settings.fps = switch (sel) {
                        0 => 15,
                        1 => 24,
                        3 => 60,
                        else => 30,
                    };
                },
                id_preset => {
                    const sel = c.SendMessageW(app.cb_preset, c.CB_GETCURSEL, 0, 0);
                    app.settings.preset = switch (sel) {
                        1 => .video,
                        2 => .max,
                        else => .text_ui,
                    };
                },
                id_cursor => {
                    const checked = c.SendMessageW(app.chk_cursor, c.BM_GETCHECK, 0, 0) != 0;
                    app.settings.cursor = checked;
                    app.settings.clicks = checked;
                },
                else => {},
            }
            return 0;
        },
        c.WM_HOTKEY => {
            switch (wp) {
                hotkey_record => if (app.rec.isBusy()) stopRecording() else startRecording(),
                hotkey_pause => togglePause(),
                else => {},
            }
            return 0;
        },
        c.WM_TIMER => {
            updateStatus();
            return 0;
        },
        wm_tray => {
            if (lp == c.WM_LBUTTONUP or lp == c.WM_LBUTTONDBLCLK) {
                if (c.IsWindowVisible(hwnd) != 0) {
                    _ = c.ShowWindow(hwnd, c.SW_HIDE);
                } else {
                    _ = c.ShowWindow(hwnd, c.SW_SHOW);
                    _ = c.SetForegroundWindow(hwnd);
                }
            }
            return 0;
        },
        c.WM_KEYDOWN => {
            // Esc убирает окно в трей: запись продолжается, состояние видно
            // по подсказке значка. Закрыть насовсем — крестик или Alt+F4.
            if (wp == c.VK_ESCAPE) {
                _ = c.ShowWindow(hwnd, c.SW_HIDE);
                return 0;
            }
            return 0;
        },
        c.WM_SIZE => {
            if (wp == c.SIZE_MINIMIZED) _ = c.ShowWindow(hwnd, c.SW_HIDE);
            return 0;
        },
        c.WM_CLOSE => {
            stopRecording();
            removeTray(hwnd);
            _ = c.UnregisterHotKey(hwnd, hotkey_record);
            _ = c.UnregisterHotKey(hwnd, hotkey_pause);
            _ = c.DestroyWindow(hwnd);
            return 0;
        },
        c.WM_DESTROY => {
            c.PostQuitMessage(0);
            return 0;
        },
        else => {},
    }
    return c.DefWindowProcW(hwnd, msg, wp, lp);
}

// ------------------------------------------------------- выбор области рамкой

const Selector = struct {
    var start_x: i32 = 0;
    var start_y: i32 = 0;
    var cur_x: i32 = 0;
    var cur_y: i32 = 0;
    var dragging: bool = false;
    var done: bool = false;
    var cancelled: bool = false;
};

fn selectorProc(hwnd: c.HWND, msg: c.UINT, wp: c.WPARAM, lp: c.LPARAM) callconv(.winapi) c.LRESULT {
    switch (msg) {
        c.WM_LBUTTONDOWN => {
            Selector.dragging = true;
            Selector.start_x = @as(i16, @truncate(@as(i32, @intCast(lp & 0xFFFF))));
            Selector.start_y = @as(i16, @truncate(@as(i32, @intCast((lp >> 16) & 0xFFFF))));
            Selector.cur_x = Selector.start_x;
            Selector.cur_y = Selector.start_y;
            return 0;
        },
        c.WM_MOUSEMOVE => {
            if (!Selector.dragging) return 0;
            Selector.cur_x = @as(i16, @truncate(@as(i32, @intCast(lp & 0xFFFF))));
            Selector.cur_y = @as(i16, @truncate(@as(i32, @intCast((lp >> 16) & 0xFFFF))));
            _ = c.InvalidateRect(hwnd, null, 1);
            return 0;
        },
        c.WM_LBUTTONUP => {
            Selector.dragging = false;
            Selector.done = true;
            _ = c.DestroyWindow(hwnd);
            return 0;
        },
        c.WM_KEYDOWN => {
            if (wp == c.VK_ESCAPE) {
                Selector.cancelled = true;
                _ = c.DestroyWindow(hwnd);
            }
            return 0;
        },
        c.WM_PAINT => {
            var ps: c.PAINTSTRUCT = undefined;
            const dc = c.BeginPaint(hwnd, &ps);
            if (Selector.dragging) {
                var r = c.RECT{
                    .left = @min(Selector.start_x, Selector.cur_x),
                    .top = @min(Selector.start_y, Selector.cur_y),
                    .right = @max(Selector.start_x, Selector.cur_x),
                    .bottom = @max(Selector.start_y, Selector.cur_y),
                };
                const brush = c.CreateSolidBrush(0x00E0A040);
                _ = c.FrameRect(dc, &r, brush);
                _ = c.DeleteObject(brush);
            }
            _ = c.EndPaint(hwnd, &ps);
            return 0;
        },
        c.WM_DESTROY => {
            c.PostQuitMessage(0);
            return 0;
        },
        else => {},
    }
    return c.DefWindowProcW(hwnd, msg, wp, lp);
}

/// Затемнить экран и дать обвести прямоугольник. `null` — если передумали.
fn selectArea() ?Rect {
    if (builtin.os.tag != .windows) return null;
    const hinst: c.HINSTANCE = @ptrCast(c.GetModuleHandleW(null));
    var wc = std.mem.zeroes(c.WNDCLASSEXW);
    wc.cbSize = @sizeOf(c.WNDCLASSEXW);
    wc.lpfnWndProc = selectorProc;
    wc.hInstance = hinst;
    wc.lpszClassName = wide("ZigRecSelect");
    wc.hbrBackground = @ptrCast(@alignCast(c.GetStockObject(c.BLACK_BRUSH)));
    wc.hCursor = c.LoadCursorW(null, idcCross()); // IDC_CROSS
    _ = c.RegisterClassExW(&wc);
    defer _ = c.UnregisterClassW(wide("ZigRecSelect"), hinst);

    const d = source.desktopArea();
    Selector.done = false;
    Selector.cancelled = false;
    Selector.dragging = false;

    const overlay = c.CreateWindowExW(
        c.WS_EX_TOPMOST | c.WS_EX_LAYERED | c.WS_EX_TOOLWINDOW,
        wide("ZigRecSelect"),
        wide("Обведите область, Esc — отмена"),
        c.WS_POPUP,
        d.x,
        d.y,
        @intCast(d.width),
        @intCast(d.height),
        null,
        null,
        hinst,
        null,
    ) orelse return null;
    // Полупрозрачное затемнение: видно, что под рамкой, но понятно, что идёт выбор.
    _ = c.SetLayeredWindowAttributes(overlay, 0, 90, c.LWA_ALPHA);
    _ = c.ShowWindow(overlay, c.SW_SHOW);
    _ = c.SetForegroundWindow(overlay);

    var msg: c.MSG = undefined;
    while (c.GetMessageW(&msg, null, 0, 0) > 0) {
        _ = c.TranslateMessage(&msg);
        _ = c.DispatchMessageW(&msg);
        if (Selector.done or Selector.cancelled) break;
    }
    if (Selector.cancelled or !Selector.done) return null;

    const r = Rect{
        .x = d.x + @min(Selector.start_x, Selector.cur_x),
        .y = d.y + @min(Selector.start_y, Selector.cur_y),
        .width = @intCast(@abs(Selector.cur_x - Selector.start_x)),
        .height = @intCast(@abs(Selector.cur_y - Selector.start_y)),
    };
    const even = r.evenSized();
    // Случайный щелчок без протягивания — это не выбор области.
    if (even.width < 16 or even.height < 16) return null;
    return even;
}

// ------------------------------------------------------------------- запуск

pub fn run(allocator: std.mem.Allocator) !void {
    return runWith(allocator, false);
}

/// `start_hidden` — начать сразу в трее: окно можно не открывать вовсе,
/// хватает значка и горячих клавиш.
pub fn runWith(allocator: std.mem.Allocator, start_hidden: bool) !void {
    if (builtin.os.tag != .windows) return error.Unsupported;
    _ = c.SetProcessDPIAware();

    app = .{ .allocator = allocator, .rec = recorder.Recorder.init(allocator) };
    app.out_dir = try defaultDir(allocator);
    defer allocator.free(app.out_dir);

    const hinst: c.HINSTANCE = @ptrCast(c.GetModuleHandleW(null));
    var wc = std.mem.zeroes(c.WNDCLASSEXW);
    wc.cbSize = @sizeOf(c.WNDCLASSEXW);
    wc.lpfnWndProc = wndProc;
    wc.hInstance = hinst;
    wc.lpszClassName = wide("ZigRecMain");
    wc.hbrBackground = @ptrFromInt(@as(usize, c.COLOR_BTNFACE) + 1);
    wc.hCursor = c.LoadCursorW(null, idcArrow()); // IDC_ARROW
    if (c.RegisterClassExW(&wc) == 0) return error.WindowFailed;

    var title_buf: [128]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buf, "ZigRecStudio {s}", .{version.VERSION}) catch "ZigRecStudio";
    var title_w: [128]u16 = undefined;
    const tn = try std.unicode.utf8ToUtf16Le(&title_w, title);
    title_w[tn] = 0;

    const hwnd = c.CreateWindowExW(
        0,
        wide("ZigRecMain"),
        @ptrCast(&title_w),
        c.WS_OVERLAPPED | c.WS_CAPTION | c.WS_SYSMENU | c.WS_MINIMIZEBOX,
        c.CW_USEDEFAULT,
        c.CW_USEDEFAULT,
        520,
        300,
        null,
        null,
        hinst,
        null,
    ) orelse return error.WindowFailed;
    _ = c.ShowWindow(hwnd, if (start_hidden) c.SW_HIDE else c.SW_SHOW);
    _ = c.UpdateWindow(hwnd);

    var msg: c.MSG = undefined;
    while (c.GetMessageW(&msg, null, 0, 0) > 0) {
        // IsDialogMessage даёт Tab, стрелки и пробел по элементам: без него
        // окно управляется только мышью, а по стилю клавиатура наравне.
        if (c.IsDialogMessageW(hwnd, &msg) != 0) continue;
        _ = c.TranslateMessage(&msg);
        _ = c.DispatchMessageW(&msg);
    }
}

// ---------------------------------------------------------------- тесты

test "имя файла для окна берётся по шаблону с датой и временем" {
    var buf: [128]u8 = undefined;
    const stamp = recorder.DateTime{ .year = 2026, .month = 9, .day = 10, .hour = 1, .minute = 2, .second = 3 };
    const name = try recorder.buildName(&buf, "zigrec-%d-%t.mp4", stamp, 1);
    try std.testing.expectEqualStrings("zigrec-2026-09-10-01-02-03.mp4", name);
}
