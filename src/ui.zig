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
const frame_overlay = @import("frame_overlay.zig");
const rec_dot = @import("rec_dot.zig");
const mic = @import("mic.zig");

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
const id_sound = 110;

const hotkey_record = 1;
const hotkey_pause = 2;

const wm_tray = c.WM_APP + 1;
const timer_tick = 1;
const timer_frame = 2;
const timer_wave = 3;

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
    btn_area_rec: c.HWND = null,
    /// Фаза пульсации значков: та же, что у рамки, чтобы дышали в такт.
    pulse: u8 = 0,
    /// Состояние, в котором кнопки нарисованы сейчас.
    drawn_state: recorder.State = .idle,
    chk_sound: c.HWND = null,
    lbl_sound_note: c.HWND = null,
    sound_on: bool = false,
    microphone: mic.Capture = .{},
    tray_added: bool = false,
    tray_tip: [128]u8 = @splat(0),
};

var app: App = undefined;

/// Стандартные курсоры и значки задаются номером ресурса, а не адресом.
///
/// В заголовке это макрос `MAKEINTRESOURCE`, который translate-c не переносит,
/// и подсунуть номер как указатель нельзя: 32515 — нечётный «адрес», и Zig
/// в безопасном режиме честно падает на проверке выравнивания. Поэтому
/// объявляем те же функции Windows с целочисленным параметром.
const loadCursorById = @extern(
    *const fn (?*anyopaque, usize) callconv(.winapi) ?*anyopaque,
    .{ .name = "LoadCursorW" },
);
const loadIconById = @extern(
    *const fn (?*anyopaque, usize) callconv(.winapi) ?*anyopaque,
    .{ .name = "LoadIconW" },
);

/// Номера из заголовков Windows, не менялись с девяностых.
const idc_arrow = 32512;
const idc_cross = 32515;
const idi_information = 32516;

/// Положить дескриптор Windows в поле-указатель.
///
/// Дескрипторы окон, курсоров и значков — не адреса, а номера в таблицах ядра,
/// и выровнены они как попало. Любое приведение через `@alignCast` на них
/// падает в безопасном режиме. Копируем биты как есть: это ровно то, что делает
/// C, и единственный честный способ положить не-указатель в поле-указатель.
fn putHandle(field: anytype, value: ?*anyopaque) void {
    const raw: usize = @intFromPtr(value);
    @memcpy(std.mem.asBytes(field), std.mem.asBytes(&raw));
}

fn setSystemCursor(field: anytype, id: usize) void {
    putHandle(field, loadCursorById(null, id));
}

fn setSystemIcon(field: anytype, id: usize) void {
    putHandle(field, loadIconById(null, id));
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
    // Проверка создаёт файл; если запись потом не начнётся, в папке останется
    // пустой mp4. Убираем его сразу — кодировщик создаст файл заново.
    errors.removeIfEmpty(path);
    app.rec.start(path, src, app.settings) catch |err| {
        setText(app.status, errors.explain(err));
        return;
    };
    app.counter += 1;
    setText(app.btn_record, "Стоп");
    _ = c.EnableWindow(app.btn_pause, 1);
    // Рамка нужна только для куска экрана: весь экран обводить нечего.
    if (app.area) |a| frame_overlay.show(a);
    // Пунктиру нужен свой такт, чаще, чем обновление строки состояния.
    _ = c.SetTimer(app.hwnd, timer_frame, 50, null);
}

fn stopRecording() void {
    if (!app.rec.isBusy()) return;
    _ = c.KillTimer(app.hwnd, timer_frame);
    frame_overlay.hide();
    app.rec.stop();
    setText(app.btn_record, "Записать экран");
    setText(app.btn_pause, "Пауза");
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
    setText(app.btn_pause, if (p.state == .paused) "Продолжить" else "Пауза");
    updateTrayTip(p, secs);

    // Значки на кнопках зависят от состояния записи. Когда запись кончилась
    // сама, такт пульсации уже выключен, и без этой перерисовки на кнопке
    // остался бы квадрат «идёт запись».
    if (p.state != app.drawn_state) {
        app.drawn_state = p.state;
        for ([_]c.HWND{ app.btn_record, app.btn_area_rec, app.btn_pause }) |h| {
            _ = c.InvalidateRect(h, null, 0);
        }
    }

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
        setText(app.btn_record, "Записать экран");
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
        std.fmt.bufPrint(&text_buf, "Zig-Rec Studio — {s}", .{p.state.label()}) catch return
    else
        std.fmt.bufPrint(&text_buf, "Zig-Rec Studio — {s} {d:0>2}:{d:0>2}, кадров {d}", .{
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

/// Нарисовать кнопку записи: значок слева, подпись справа.
///
/// Рисуем сами, потому что системная кнопка не умеет показывать состояние
/// значком, а подпись «Стоп» без красного квадрата читается медленнее.
fn drawRecordButton(item: *c.DRAWITEMSTRUCT) void {
    const dc = item.hDC;
    var rc = item.rcItem;

    // Рамка и фон — системные, чтобы кнопка выглядела как все кнопки Windows.
    var state: c.UINT = c.DFCS_BUTTONPUSH;
    if (item.itemState & c.ODS_SELECTED != 0) state |= c.DFCS_PUSHED;
    if (item.itemState & c.ODS_DISABLED != 0) state |= c.DFCS_INACTIVE;
    _ = c.DrawFrameControl(dc, &rc, c.DFC_BUTTON, state);

    const enabled = item.itemState & c.ODS_DISABLED == 0;
    const rec_state = app.rec.state();
    const id = item.CtlID;
    const look = if (id == id_pause)
        rec_dot.pauseLook(rec_state, enabled)
    else
        rec_dot.recordLook(rec_state, enabled, app.pulse);

    // Значок слева, по центру высоты.
    const cx = rc.left + 16;
    const cy = @divTrunc(rc.top + rc.bottom, 2);
    const r: i32 = @intCast(look.radius);
    const brush = c.CreateSolidBrush(look.color);
    defer _ = c.DeleteObject(brush);

    switch (look.shape) {
        .circle => {
            const old = c.SelectObject(dc, brush);
            const pen = c.CreatePen(c.PS_SOLID, 1, look.color);
            const old_pen = c.SelectObject(dc, pen);
            _ = c.Ellipse(dc, cx - r, cy - r, cx + r, cy + r);
            _ = c.SelectObject(dc, old_pen);
            _ = c.DeleteObject(pen);
            _ = c.SelectObject(dc, old);
        },
        .ring => {
            const pen = c.CreatePen(c.PS_SOLID, 2, look.color);
            const old_pen = c.SelectObject(dc, pen);
            const hollow = c.GetStockObject(c.HOLLOW_BRUSH);
            const old_brush = c.SelectObject(dc, hollow);
            _ = c.Ellipse(dc, cx - r, cy - r, cx + r, cy + r);
            _ = c.SelectObject(dc, old_brush);
            _ = c.SelectObject(dc, old_pen);
            _ = c.DeleteObject(pen);
        },
        .square => {
            var box = c.RECT{ .left = cx - r, .top = cy - r, .right = cx + r, .bottom = cy + r };
            _ = c.FillRect(dc, &box, brush);
        },
    }

    // Подпись справа от значка.
    var text: [256]u16 = undefined;
    const n = c.GetWindowTextW(item.hwndItem, &text, text.len);
    if (n > 0) {
        var text_rc = c.RECT{ .left = rc.left + 30, .top = rc.top, .right = rc.right - 6, .bottom = rc.bottom };
        _ = c.SetBkMode(dc, c.TRANSPARENT);
        _ = c.SetTextColor(dc, if (enabled) @as(c.COLORREF, 0x00202020) else @as(c.COLORREF, 0x00909090));
        const font = c.GetStockObject(c.DEFAULT_GUI_FONT);
        const old_font = c.SelectObject(dc, font);
        _ = c.DrawTextW(dc, &text, n, &text_rc, c.DT_LEFT | c.DT_VCENTER | c.DT_SINGLELINE | c.DT_END_ELLIPSIS);
        _ = c.SelectObject(dc, old_font);
    }

    if (item.itemState & c.ODS_FOCUS != 0) {
        var focus_rc = c.RECT{ .left = rc.left + 3, .top = rc.top + 3, .right = rc.right - 3, .bottom = rc.bottom - 3 };
        _ = c.DrawFocusRect(dc, &focus_rc);
    }
}

/// Место осциллографа в окне.
fn waveRect() c.RECT {
    return .{ .left = 112, .top = 228, .right = 492, .bottom = 316 };
}

/// Осциллограф микрофона: настоящая форма сигнала, а не полоска уровня.
///
/// По полоске видно только «громко или тихо». По волне видно, говорит человек
/// или в микрофон дует ветер, и сразу заметно, что вход выбран не тот:
/// прямая линия вместо волны.
fn drawWave(hwnd: c.HWND, dc: c.HDC) void {
    const box = waveRect();
    const w = box.right - box.left;
    const h = box.bottom - box.top;

    // Тёмное поле: волна на нём видна лучше, чем на сером фоне окна.
    var rc = box;
    const back = c.CreateSolidBrush(if (app.sound_on) @as(c.COLORREF, 0x00201810) else @as(c.COLORREF, 0x00E8E8E8));
    _ = c.FillRect(dc, &rc, back);
    _ = c.DeleteObject(back);

    _ = c.SetBkMode(dc, c.TRANSPARENT);
    const font = c.GetStockObject(c.DEFAULT_GUI_FONT);
    const old_font = c.SelectObject(dc, font);
    defer _ = c.SelectObject(dc, old_font);

    if (!app.sound_on) {
        _ = c.SetTextColor(dc, 0x00808080);
        drawTextIn(dc, box, "звук выключен");
        return;
    }

    if (app.microphone.failure) |err| {
        _ = c.SetTextColor(dc, 0x004040D0);
        drawTextIn(dc, box, errors.short(err));
        return;
    }

    // Средняя линия.
    const mid = box.top + @divTrunc(h, 2);
    var axis = c.RECT{ .left = box.left, .top = mid, .right = box.right, .bottom = mid + 1 };
    const axis_brush = c.CreateSolidBrush(0x00404040);
    _ = c.FillRect(dc, &axis, axis_brush);
    _ = c.DeleteObject(axis_brush);

    var samples: [380]f32 = undefined;
    const count: usize = @intCast(@min(w, @as(i32, @intCast(samples.len))));
    app.microphone.ring.snapshot(samples[0..count]);

    const pen = c.CreatePen(c.PS_SOLID, 2, 0x0040D040);
    const old_pen = c.SelectObject(dc, pen);
    defer {
        _ = c.SelectObject(dc, old_pen);
        _ = c.DeleteObject(pen);
    }

    const half: f32 = @floatFromInt(@divTrunc(h, 2) - 6);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const x = box.left + @as(i32, @intCast(i));
        const y = mid - @as(i32, @intFromFloat(samples[i] * half));
        if (i == 0) {
            _ = c.MoveToEx(dc, x, y, null);
        } else {
            _ = c.LineTo(dc, x, y);
        }
    }

    const level = app.microphone.ring.level();
    var text: [128]u8 = undefined;
    const note = if (level.isClipping())
        "  ПЕРЕГРУЗ"
    else if (level.isSilent())
        "  тишина"
    else
        "";
    const line = std.fmt.bufPrint(&text, "{d:.0} дБ{s}", .{ level.dbfs(), note }) catch "";
    _ = c.SetTextColor(dc, if (level.isClipping()) @as(c.COLORREF, 0x004040F0) else @as(c.COLORREF, 0x0060D060));
    const label_rc = c.RECT{ .left = box.left + 6, .top = box.top + 4, .right = box.right - 6, .bottom = box.top + 22 };
    drawTextInRect(dc, label_rc, line);
    _ = hwnd;
}

fn drawTextIn(dc: c.HDC, box: c.RECT, text: []const u8) void {
    const inner = c.RECT{ .left = box.left + 8, .top = box.top + 8, .right = box.right - 8, .bottom = box.bottom - 4 };
    drawTextInRect(dc, inner, text);
}

fn drawTextInRect(dc: c.HDC, rect: c.RECT, text: []const u8) void {
    var wide_buf: [512]u16 = undefined;
    const n = std.unicode.utf8ToUtf16Le(&wide_buf, text) catch return;
    var rc = rect;
    _ = c.DrawTextW(dc, &wide_buf, @intCast(n), &rc, c.DT_LEFT | c.DT_TOP | c.DT_WORDBREAK);
}

fn addTray(hwnd: c.HWND) void {
    var nid = std.mem.zeroes(c.NOTIFYICONDATAW);
    nid.cbSize = @sizeOf(c.NOTIFYICONDATAW);
    nid.hWnd = hwnd;
    nid.uID = 1;
    nid.uFlags = c.NIF_ICON | c.NIF_MESSAGE | c.NIF_TIP;
    nid.uCallbackMessage = wm_tray;
    setSystemIcon(&nid.hIcon, idi_information);
    const tip = wide("Zig-Rec Studio");
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
            app.btn_record = button(hwnd, "Записать экран", id_record, 14, 66, 170, 32, c.BS_OWNERDRAW);
            app.btn_area_rec = button(hwnd, "Записать область", id_area_rec, 192, 66, 186, 32, c.BS_OWNERDRAW);
            app.btn_pause = button(hwnd, "Пауза", id_pause, 386, 66, 106, 32, c.BS_OWNERDRAW);

            _ = button(hwnd, "Выбрать область…", id_area, 14, 106, 176, 30, 0);
            _ = button(hwnd, "Весь экран", id_full, 198, 106, 160, 30, 0);
            app.chk_cursor = button(hwnd, "Курсор и клики", id_cursor, 366, 106, 126, 30, c.BS_AUTOCHECKBOX);
            app.chk_sound = button(hwnd, "Звук", id_sound, 14, 232, 90, 24, c.BS_AUTOCHECKBOX);
            // Галочка не должна врать: пока звук слышно, но в файл он не идёт.
            app.lbl_sound_note = label(hwnd, "звук слышно, но в файл он пока не пишется", 14, 324, 478, 20);

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

            for ([_]c.HWND{ app.status, app.btn_record, app.btn_pause, app.btn_open, app.chk_cursor, app.cb_fps, app.cb_preset, app.lbl_file, app.chk_sound, app.lbl_sound_note }) |h| applyFont(h);
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
                id_sound => {
                    app.sound_on = c.SendMessageW(app.chk_sound, c.BM_GETCHECK, 0, 0) != 0;
                    if (app.sound_on) {
                        app.microphone.start() catch {};
                        _ = c.SetTimer(hwnd, timer_wave, 80, null);
                    } else {
                        _ = c.KillTimer(hwnd, timer_wave);
                        app.microphone.stop();
                    }
                    _ = c.InvalidateRect(hwnd, null, 1);
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
        c.WM_PAINT => {
            var ps: c.PAINTSTRUCT = undefined;
            const dc = c.BeginPaint(hwnd, &ps);
            drawWave(hwnd, dc);
            _ = c.EndPaint(hwnd, &ps);
            return 0;
        },
        c.WM_DRAWITEM => {
            const item: *c.DRAWITEMSTRUCT = @ptrFromInt(@as(usize, @bitCast(lp)));
            drawRecordButton(item);
            return 1;
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
            if (wp == timer_wave) {
                var box = waveRect();
                _ = c.InvalidateRect(hwnd, &box, 0);
                return 0;
            }
            if (wp == timer_frame) {
                frame_overlay.animate();
                app.pulse = rec_dot.pulseFromAlpha(frame_overlay.currentAlpha());
                _ = c.InvalidateRect(app.btn_record, null, 0);
                _ = c.InvalidateRect(app.btn_area_rec, null, 0);
                _ = c.InvalidateRect(app.btn_pause, null, 0);
                return 0;
            }
            updateStatus();
            // Запись могла кончиться сама (ошибка, конец времени) — рамку убираем.
            if (frame_overlay.isShown() and !app.rec.isBusy()) {
                _ = c.KillTimer(hwnd, timer_frame);
                frame_overlay.hide();
            }
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
            app.microphone.stop();
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
            // Затемнение: сплошная заливка, поверх которой лежит прозрачность окна.
            var full: c.RECT = undefined;
            _ = c.GetClientRect(hwnd, &full);
            const back = c.CreateSolidBrush(0x00000000);
            _ = c.FillRect(dc, &full, back);
            _ = c.DeleteObject(back);
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
            // Никакого PostQuitMessage: цикл рамки вложен в цикл главного окна,
            // и WM_QUIT завершил бы оба. Программа закрывалась сразу после
            // выбора области, не начав запись. Выход из вложенного цикла — по
            // флагам done и cancelled.
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
    // Фон не задаём: дескриптор системной кисти не обязан быть выровнен так,
    // как ждёт указатель в Zig, и @alignCast на нём падает. Затемнение рисуем
    // сами в WM_PAINT — заодно видно, что именно закрашивается.
    wc.hbrBackground = null;
    setSystemCursor(&wc.hCursor, idc_cross);
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

    // Программа собрана как консольная, чтобы работали команды и коды возврата.
    // Но окну консоль не нужна: при запуске с ярлыка она мигала бы чёрным
    // прямоугольником рядом. Прячем её, если она наша собственная.
    if (c.GetConsoleWindow()) |console| {
        var console_pid: c.DWORD = 0;
        _ = c.GetWindowThreadProcessId(console, &console_pid);
        if (console_pid == c.GetCurrentProcessId()) _ = c.ShowWindow(console, c.SW_HIDE);
    }

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
    setSystemCursor(&wc.hCursor, idc_arrow);
    if (c.RegisterClassExW(&wc) == 0) return error.WindowFailed;

    var title_buf: [128]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buf, "Zig-Rec Studio v{s}", .{version.VERSION}) catch "Zig-Rec Studio";
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
        410,
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
