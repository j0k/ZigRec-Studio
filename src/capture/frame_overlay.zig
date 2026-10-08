//! Мигающая пунктирная рамка вокруг записываемой области.
//!
//! Пока идёт запись куска экрана, человек должен видеть границы этого куска,
//! не гадая по памяти. Рамка «бежит» пунктиром и плавно пульсирует — статичную
//! линию глаз перестаёт замечать через полминуты, а бегущая читается сразу.
//!
//! Рамка рисуется **снаружи** области, а не по её краю: иначе она попала бы
//! в кадр и осталась в готовом видео. Окно рамки прозрачно для мыши
//! (`WS_EX_TRANSPARENT`) — сквозь него можно работать, как будто его нет.
//!
//! За рамку область **перетаскивают мышью** (#195). Тянет не сама линия —
//! в неё не попасть, — а **красный квадрат у каждого угла**. Почему не линия:
//! окно рамки слоёное с цветовым ключом, и Windows пропускает клики сквозь
//! прозрачные пиксели. Значит, ловятся только сами штрихи пунктира — три точки
//! через две, да ещё с разрывами между штрихами; у угла, куда целятся чаще
//! всего, попасть почти невозможно, а промах уходит в программу под рамкой.
//! Квадрат же — сплошной, в него попадают сразу, и он виден как ручка.
//!
//! Квадраты стоят **снаружи** области, сразу за её углами: внутри они попали
//! бы в кадр и остались в готовом видео. Значит, и в записи их нет. Внутри
//! области окон нет вовсе, и клики там проходят в записываемую программу.
const std = @import("std");
const builtin = @import("builtin");
const win32 = @import("../win32.zig");
const c = win32.c;
const types = @import("capture_types.zig");

pub const Rect = types.Rect;

/// Толщина линии рамки в пикселях.
pub const thickness: i32 = 3;
/// Длина штриха и промежутка.
const dash_on: i32 = 14;
const dash_off: i32 = 10;

/// Сторона квадрата-ручки в углу. Крупная нарочно: в мелкую не попасть
/// мышью, а Ручка — единственное место, за которое область берут.
pub const pad_size: i32 = 26;

const class_name = "ZigRecFrameOverlay";
const corner_class_name = "ZigRecAreaCorner";

/// Окну записи: ручку тянут, область просят переставить (#195).
///
/// Координаты кладём в `pending`, а сообщением только будим окно: `wParam`
/// и `lParam` — числа, в них две координаты не поместятся, а городить общую
/// память ради двух чисел не стоит.
pub const wm_overlay_move = c.WM_APP + 42;

/// `HWND_TOPMOST` — это -1, а не адрес: подставить его в поле-указатель нельзя,
/// Zig падает на проверке выравнивания. Объявляем `SetWindowPos` с целым
/// вторым параметром, как оно и есть на уровне вызова Windows.
const setWindowPosZ = @extern(
    *const fn (c.HWND, usize, i32, i32, i32, i32, c.UINT) callconv(.winapi) c.BOOL,
    .{ .name = "SetWindowPos" },
);
const hwnd_topmost: usize = @bitCast(@as(isize, -1));

/// Номера курсоров Windows; `MAKEINTRESOURCE` переводит не всякий транслятор.
const idc_sizeall = 32646;
/// Дескриптор курсора — номер в таблице ядра, а не адрес: приводить
/// к указателю Zig нельзя. Объявляем функции с целым параметром.
const loadCursorById = @extern(
    *const fn (?*anyopaque, usize) callconv(.winapi) ?*anyopaque,
    .{ .name = "LoadCursorW" },
);
const setCursorRaw = @extern(
    *const fn (?*anyopaque) callconv(.winapi) ?*anyopaque,
    .{ .name = "SetCursor" },
);

fn setCursor(id: usize) void {
    _ = setCursorRaw(loadCursorById(null, id));
}

/// Сдвиг пунктира и яркость на текущем шаге.
pub const Animation = struct {
    phase: i32 = 0,
    tick: u32 = 0,

    /// Шаг анимации: пунктир едет, яркость плавно дышит.
    pub fn step(self: *Animation) void {
        self.tick +%= 1;
        self.phase = @mod(self.phase + 2, dash_on + dash_off);
    }

    /// Прозрачность рамки от 140 до 255 по синусоиде.
    ///
    /// Не мигание «включено-выключено»: резкое мигание раздражает и мешает
    /// смотреть на то, что под рамкой. Плавная волна заметна боковым зрением
    /// и не отвлекает.
    pub fn alpha(self: Animation) u8 {
        const period: f32 = 40; // шагов на полный цикл
        const t = @as(f32, @floatFromInt(self.tick % @as(u32, @intFromFloat(period))));
        const wave = (1 + @sin(t / period * std.math.tau)) / 2; // 0…1
        return @intFromFloat(140 + wave * 115);
    }
};

var animation: Animation = .{};
var overlay: c.HWND = null;
var corners: c.HWND = null;
var overlay_area: Rect = .{ .width = 0, .height = 0 };
/// Кому ручки докладывают о перетаскивании. Пусто — тянуть нечего: ручки
/// прячутся, рамка показывает, но мышь не берёт, так метят запись окна.
var owner: c.HWND = null;
/// Куда ручки просят переставить область. Кладут они, читает окно записи.
pub var pending_x: i32 = 0;
pub var pending_y: i32 = 0;
/// С чего началось перетаскивание: место области и точка курсора в тот миг.
/// Движение считаем разностью — так область не «прыгает» под курсор.
var drag: Drag = .{ .area = .{ .width = 0, .height = 0 }, .from_x = 0, .from_y = 0 };

/// Какой угол области. Квадрат-ручка стоит снаружи именно этого угла.
pub const Corner = enum { tl, tr, bl, br };

/// Прямоугольник ручки одного угла — в координатах рабочего стола.
///
/// Квадрат прижат к углу области снаружи: его внутренний угол совпадает
/// с углом области, а сам он лежит за пределами кадра.
pub fn cornerRect(which: Corner, area: Rect) Rect {
    const s: u32 = @intCast(pad_size);
    const right = area.x + @as(i32, @intCast(area.width));
    const bottom = area.y + @as(i32, @intCast(area.height));
    return switch (which) {
        .tl => .{ .x = area.x - pad_size, .y = area.y - pad_size, .width = s, .height = s },
        .tr => .{ .x = right, .y = area.y - pad_size, .width = s, .height = s },
        .bl => .{ .x = area.x - pad_size, .y = bottom, .width = s, .height = s },
        .br => .{ .x = right, .y = bottom, .width = s, .height = s },
    };
}

/// Окно ручек: область плюс квадрат со всех сторон — чтобы все четыре ручки
/// поместились одним окном.
fn cornerWindowRect(area: Rect) Rect {
    const pad: u32 = @intCast(pad_size * 2);
    return .{
        .x = area.x - pad_size,
        .y = area.y - pad_size,
        .width = area.width + pad,
        .height = area.height + pad,
    };
}

fn overlayProc(hwnd: c.HWND, msg: c.UINT, wp: c.WPARAM, lp: c.LPARAM) callconv(.winapi) c.LRESULT {
    switch (msg) {
        c.WM_PAINT => {
            var ps: c.PAINTSTRUCT = undefined;
            const dc = c.BeginPaint(hwnd, &ps);
            paint(hwnd, dc);
            _ = c.EndPaint(hwnd, &ps);
            return 0;
        },
        // Ни мыши, ни фокуса: рамка только показывает, но ничего не ловит.
        c.WM_NCHITTEST => return -1, // HTTRANSPARENT
        c.WM_ERASEBKGND => return 1,
        else => {},
    }
    return c.DefWindowProcW(hwnd, msg, wp, lp);
}

fn cornerProc(hwnd: c.HWND, msg: c.UINT, wp: c.WPARAM, lp: c.LPARAM) callconv(.winapi) c.LRESULT {
    switch (msg) {
        c.WM_PAINT => {
            var ps: c.PAINTSTRUCT = undefined;
            const dc = c.BeginPaint(hwnd, &ps);
            paintCorners(dc);
            _ = c.EndPaint(hwnd, &ps);
            return 0;
        },
        c.WM_ERASEBKGND => return 1,
        c.WM_LBUTTONDOWN => {
            if (owner == null) return 0;
            var at: c.POINT = undefined;
            if (c.GetCursorPos(&at) != 0) {
                drag = dragStart(overlay_area, at.x, at.y);
            } else {
                drag = dragStart(overlay_area, 0, 0);
            }
            _ = c.SetCapture(hwnd);
            return 0;
        },
        c.WM_MOUSEMOVE => {
            if (owner == null or corners == null) return 0;
            if (c.GetCapture() != hwnd) return 0;
            var at: c.POINT = undefined;
            if (c.GetCursorPos(&at) == 0) return 0;
            // На сколько ушёл курсор с начала захвата, на столько и область:
            // размер не меняется, ручки не отстают и не прыгают.
            const want = drag.place(at.x, at.y);
            pending_x = want.x;
            pending_y = want.y;
            _ = c.PostMessageW(owner, wm_overlay_move, 0, 0);
            return 0;
        },
        c.WM_LBUTTONUP => {
            if (c.GetCapture() == hwnd) _ = c.ReleaseCapture();
            return 0;
        },
        c.WM_SETCURSOR => {
            if (owner != null) {
                setCursor(idc_sizeall);
                return 1;
            }
        },
        else => {},
    }
    return c.DefWindowProcW(hwnd, msg, wp, lp);
}

/// Нарисовать бегущий пунктир по четырём сторонам — у самой области.
fn paint(hwnd: c.HWND, dc: c.HDC) void {
    var rc: c.RECT = undefined;
    _ = c.GetClientRect(hwnd, &rc);

    // Фон окна — цвет-ключ, он станет прозрачным (см. SetLayeredWindowAttributes).
    const back = c.CreateSolidBrush(key_color);
    _ = c.FillRect(dc, &rc, back);
    _ = c.DeleteObject(back);

    const ink = c.CreateSolidBrush(0x002E4CE8); // тёплый красный в BGR
    defer _ = c.DeleteObject(ink);

    const w = rc.right;
    const h = rc.bottom;
    const t = thickness;
    const step = dash_on + dash_off;

    // Верх и низ.
    var x: i32 = -animation.phase;
    while (x < w) : (x += step) {
        var seg = c.RECT{ .left = @max(x, 0), .top = 0, .right = @min(x + dash_on, w), .bottom = t };
        if (seg.right > seg.left) _ = c.FillRect(dc, &seg, ink);
        var seg2 = c.RECT{ .left = @max(x, 0), .top = h - t, .right = @min(x + dash_on, w), .bottom = h };
        if (seg2.right > seg2.left) _ = c.FillRect(dc, &seg2, ink);
    }
    // Бока: пунктир едет в другую сторону, чтобы рамка выглядела как единое кольцо.
    var y: i32 = -@mod(step - animation.phase, step);
    while (y < h) : (y += step) {
        var seg = c.RECT{ .left = 0, .top = @max(y, 0), .right = t, .bottom = @min(y + dash_on, h) };
        if (seg.bottom > seg.top) _ = c.FillRect(dc, &seg, ink);
        var seg2 = c.RECT{ .left = w - t, .top = @max(y, 0), .right = w, .bottom = @min(y + dash_on, h) };
        if (seg2.bottom > seg2.top) _ = c.FillRect(dc, &seg2, ink);
    }
}

/// Нарисовать четыре квадрата-ручки. Сплошные, с уголком-насечкой — чтобы
/// читались как ручки, а не как случайные красные пятна.
fn paintCorners(dc: c.HDC) void {
    var rc: c.RECT = undefined;
    _ = c.GetClientRect(corners, &rc);
    const back = c.CreateSolidBrush(key_color);
    _ = c.FillRect(dc, &rc, back);
    _ = c.DeleteObject(back);

    const s = pad_size;
    const right = pad_size + @as(i32, @intCast(overlay_area.width));
    const bottom = pad_size + @as(i32, @intCast(overlay_area.height));
    // Углы — в точках окна ручек (левый верх окна = угол области минус квадрат).
    const spots = [_][2]i32{
        .{ 0, 0 },
        .{ right, 0 },
        .{ 0, bottom },
        .{ right, bottom },
    };
    const fill = c.CreateSolidBrush(0x001824B8); // тот же красный, плотнее
    defer _ = c.DeleteObject(fill);
    const edge = c.CreateSolidBrush(0x00C8DCF8); // светлая кромка
    defer _ = c.DeleteObject(edge);

    for (spots) |at| {
        var box = c.RECT{ .left = at[0], .top = at[1], .right = at[0] + s, .bottom = at[1] + s };
        _ = c.FillRect(dc, &box, fill);
        _ = c.FrameRect(dc, &box, edge);
    }
}

/// Цвет, который становится прозрачным. Взят заведомо «неживой», чтобы
/// случайно не совпасть с цветом рамки.
const key_color: c.COLORREF = 0x00FF00FF;

/// Прямоугольник окна рамки: область плюс толщина линии со всех сторон.
fn outerRect(area: Rect) Rect {
    const pad: u32 = @intCast(thickness * 2);
    return .{
        .x = area.x - thickness,
        .y = area.y - thickness,
        .width = area.width + pad,
        .height = area.height + pad,
    };
}

/// Показать рамку и ручки вокруг области (координаты рабочего стола).
pub fn show(area: Rect) void {
    if (builtin.os.tag != .windows) return;
    hide();
    if (area.isEmpty()) return;

    const hinst: c.HINSTANCE = @ptrCast(c.GetModuleHandleW(null));

    var wc = std.mem.zeroes(c.WNDCLASSEXW);
    wc.cbSize = @sizeOf(c.WNDCLASSEXW);
    wc.lpfnWndProc = overlayProc;
    wc.hInstance = hinst;
    wc.lpszClassName = std.unicode.utf8ToUtf16LeStringLiteral(class_name);
    _ = c.RegisterClassExW(&wc);

    const outer = outerRect(area);
    overlay = c.CreateWindowExW(
        c.WS_EX_TOPMOST | c.WS_EX_LAYERED | c.WS_EX_TRANSPARENT | c.WS_EX_TOOLWINDOW | c.WS_EX_NOACTIVATE,
        std.unicode.utf8ToUtf16LeStringLiteral(class_name),
        std.unicode.utf8ToUtf16LeStringLiteral("ZigRec"),
        c.WS_POPUP,
        outer.x,
        outer.y,
        @intCast(outer.width),
        @intCast(outer.height),
        null,
        null,
        hinst,
        null,
    );
    if (overlay == null) return;
    overlay_area = area;
    _ = c.SetLayeredWindowAttributes(overlay, key_color, 255, c.LWA_COLORKEY | c.LWA_ALPHA);
    _ = c.ShowWindow(overlay, c.SW_SHOWNOACTIVATE);

    // Ручки — отдельным окном: рамка сквозная для мыши, и ловить её всю
    // значило бы не дать работать под областью. Ручки одни и только они
    // берут мышь. Середина окна — цвет-ключ, сквозь неё клики проходят.
    var cc = std.mem.zeroes(c.WNDCLASSEXW);
    cc.cbSize = @sizeOf(c.WNDCLASSEXW);
    cc.lpfnWndProc = cornerProc;
    cc.hInstance = hinst;
    cc.lpszClassName = std.unicode.utf8ToUtf16LeStringLiteral(corner_class_name);
    _ = c.RegisterClassExW(&cc);

    const cw = cornerWindowRect(area);
    corners = c.CreateWindowExW(
        c.WS_EX_TOPMOST | c.WS_EX_LAYERED | c.WS_EX_TOOLWINDOW | c.WS_EX_NOACTIVATE,
        std.unicode.utf8ToUtf16LeStringLiteral(corner_class_name),
        std.unicode.utf8ToUtf16LeStringLiteral("ZigRec"),
        c.WS_POPUP,
        cw.x,
        cw.y,
        @intCast(cw.width),
        @intCast(cw.height),
        null,
        null,
        hinst,
        null,
    );
    if (corners == null) return;
    _ = c.SetLayeredWindowAttributes(corners, key_color, 255, c.LWA_COLORKEY);
    // Ручки нужны только у области: у окна место диктует само окно.
    _ = c.ShowWindow(corners, if (owner != null) c.SW_SHOWNOACTIVATE else c.SW_HIDE);
    _ = setWindowPosZ(corners, hwnd_topmost, 0, 0, 0, 0, c.SWP_NOMOVE | c.SWP_NOSIZE | c.SWP_NOACTIVATE);
}

/// Переставить рамку и ручки под новую область, не пересоздавая окна.
///
/// Нужна тому, кто двигает область: пересоздание на каждой точке движения
/// мелькало бы. Размер области при перетаскивании не меняется.
pub fn moveFrame(area: Rect) void {
    if (builtin.os.tag != .windows or overlay == null) return;
    overlay_area = area;
    const outer = outerRect(area);
    _ = setWindowPosZ(
        overlay,
        hwnd_topmost,
        outer.x,
        outer.y,
        @intCast(outer.width),
        @intCast(outer.height),
        c.SWP_NOACTIVATE,
    );
    if (corners) |h| {
        const cw = cornerWindowRect(area);
        _ = setWindowPosZ(
            h,
            hwnd_topmost,
            cw.x,
            cw.y,
            @intCast(cw.width),
            @intCast(cw.height),
            c.SWP_NOACTIVATE,
        );
    }
}

/// Запомнить, кому докладывать о перетаскивании. Пусто — рамка не ловит мышь.
///
/// Так отделяют область от окна: у окна место диктует само окно, и тянуть
/// его ручками нельзя.
pub fn setOwner(to: c.HWND) void {
    owner = to;
    if (corners) |h| _ = c.ShowWindow(h, if (to != null) c.SW_SHOWNOACTIVATE else c.SW_HIDE);
}

/// Шаг анимации: вызывается по таймеру окна записи.
pub fn animate() void {
    if (builtin.os.tag != .windows or overlay == null) return;
    animation.step();
    _ = c.SetLayeredWindowAttributes(overlay, key_color, animation.alpha(), c.LWA_COLORKEY | c.LWA_ALPHA);
    _ = c.InvalidateRect(overlay, null, 0);
    // Рамка и ручки должны оставаться поверх, даже если сверху открыли окно.
    _ = setWindowPosZ(overlay, hwnd_topmost, 0, 0, 0, 0, c.SWP_NOMOVE | c.SWP_NOSIZE | c.SWP_NOACTIVATE);
    _ = setWindowPosZ(corners, hwnd_topmost, 0, 0, 0, 0, c.SWP_NOMOVE | c.SWP_NOSIZE | c.SWP_NOACTIVATE);
}

pub fn hide() void {
    if (builtin.os.tag != .windows) return;
    if (overlay) |h| {
        _ = c.DestroyWindow(h);
        overlay = null;
    }
    if (corners) |h| {
        _ = c.DestroyWindow(h);
        corners = null;
    }
    owner = null;
    animation = .{};
}

/// Текущая прозрачность рамки. Нужна кнопкам: их значок дышит в такт с рамкой.
pub fn currentAlpha() u8 {
    return animation.alpha();
}

pub fn isShown() bool {
    return overlay != null;
}

// ------------------------------------------------------- перетаскивание

/// С какого места области началось перетаскивание и где был курсор.
///
/// Отдельной чистой функцией, чтобы это правило проверялось без мыши: ошибка
/// здесь — область уезжает не туда, куда её тянут.
pub fn dragStart(area: Rect, cursor_x: i32, cursor_y: i32) Drag {
    return .{ .area = area, .from_x = cursor_x, .from_y = cursor_y };
}

pub const Drag = struct {
    area: Rect,
    from_x: i32,
    from_y: i32,

    /// Куда встать области, когда курсор ушёл в (`to_x`, `to_y`).
    /// Размер не трогаем — только место.
    pub fn place(self: Drag, to_x: i32, to_y: i32) Rect {
        return .{
            .x = self.area.x + (to_x - self.from_x),
            .y = self.area.y + (to_y - self.from_y),
            .width = self.area.width,
            .height = self.area.height,
        };
    }
};

// ---------------------------------------------------------------- тесты

test "пунктир едет по кругу и не убегает за период" {
    var a = Animation{};
    const period = dash_on + dash_off;
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        a.step();
        try std.testing.expect(a.phase >= 0 and a.phase < period);
    }
}

test "яркость дышит в заданных пределах" {
    var a = Animation{};
    var min: u8 = 255;
    var max: u8 = 0;
    var i: u32 = 0;
    while (i < 200) : (i += 1) {
        a.step();
        const v = a.alpha();
        min = @min(min, v);
        max = @max(max, v);
    }
    try std.testing.expect(min >= 140);
    try std.testing.expect(max <= 255);
    // Волна должна быть заметной, а не дрожанием на пару единиц.
    try std.testing.expect(max - min > 80);
}

test "яркость меняется плавно, без скачков" {
    var a = Animation{};
    var prev = a.alpha();
    var i: u32 = 0;
    while (i < 200) : (i += 1) {
        a.step();
        const now = a.alpha();
        const jump = if (now > prev) now - prev else prev - now;
        try std.testing.expect(jump < 25);
        prev = now;
    }
}

test "ручка каждого угла лежит снаружи области и прижата к её углу" {
    const area = Rect{ .x = 300, .y = 200, .width = 900, .height = 500 };
    const right = area.x + @as(i32, @intCast(area.width));
    const bottom = area.y + @as(i32, @intCast(area.height));
    const s: u32 = @intCast(pad_size);

    const tl = cornerRect(.tl, area);
    try std.testing.expectEqual(@as(i32, area.x - pad_size), tl.x);
    try std.testing.expectEqual(@as(i32, area.y - pad_size), tl.y);
    // Внутренний угол ручки совпадает с углом области.
    try std.testing.expectEqual(area.x, tl.x + @as(i32, @intCast(tl.width)));
    try std.testing.expectEqual(area.y, tl.y + @as(i32, @intCast(tl.height)));

    const tr = cornerRect(.tr, area);
    try std.testing.expectEqual(right, tr.x);
    try std.testing.expectEqual(@as(i32, area.y - pad_size), tr.y);

    const bl = cornerRect(.bl, area);
    try std.testing.expectEqual(@as(i32, area.x - pad_size), bl.x);
    try std.testing.expectEqual(bottom, bl.y);

    const br = cornerRect(.br, area);
    try std.testing.expectEqual(right, br.x);
    try std.testing.expectEqual(bottom, br.y);

    // Все одного размера и целиком снаружи кадра: ни одна точка не внутри области.
    for ([_]Rect{ tl, tr, bl, br }) |p| {
        try std.testing.expectEqual(s, p.width);
        try std.testing.expectEqual(s, p.height);
        const inside_x = p.x >= area.x and p.x + @as(i32, @intCast(p.width)) <= right;
        const inside_y = p.y >= area.y and p.y + @as(i32, @intCast(p.height)) <= bottom;
        try std.testing.expect(!(inside_x and inside_y));
        // Крупнее линии: в тонкую линию мышью не попасть.
        try std.testing.expect(pad_size > thickness);
    }
}

test "окно ручек вмещает все четыре и шире области на квадрат с обеих сторон" {
    const area = Rect{ .x = 300, .y = 200, .width = 900, .height = 500 };
    const cw = cornerWindowRect(area);
    try std.testing.expectEqual(area.x - pad_size, cw.x);
    try std.testing.expectEqual(area.y - pad_size, cw.y);
    try std.testing.expectEqual(area.width + @as(u32, @intCast(pad_size * 2)), cw.width);
    try std.testing.expectEqual(area.height + @as(u32, @intCast(pad_size * 2)), cw.height);
    // В точке-координатах окна каждая ручка лежит внутри него.
    const rx = cw.x + @as(i32, @intCast(cw.width));
    const ry = cw.y + @as(i32, @intCast(cw.height));
    for ([_]Corner{ .tl, .tr, .bl, .br }) |which| {
        const p = cornerRect(which, area);
        try std.testing.expect(p.x >= cw.x and p.y >= cw.y);
        try std.testing.expect(p.x + @as(i32, @intCast(p.width)) <= rx);
        try std.testing.expect(p.y + @as(i32, @intCast(p.height)) <= ry);
    }
}

test "перетаскивание сдвигает область ровно на ход курсора" {
    const area = Rect{ .x = 300, .y = 200, .width = 900, .height = 500 };
    const d = dragStart(area, 1000, 1000);
    // Курсор прошёл +40, -25 — область встала туда же, размер цел.
    const moved = d.place(1040, 975);
    try std.testing.expectEqual(@as(i32, 340), moved.x);
    try std.testing.expectEqual(@as(i32, 175), moved.y);
    try std.testing.expectEqual(area.width, moved.width);
    try std.testing.expectEqual(area.height, moved.height);
    // Курсор вернулся — вернулась и область.
    const back = d.place(1000, 1000);
    try std.testing.expectEqual(area.x, back.x);
    try std.testing.expectEqual(area.y, back.y);
}
