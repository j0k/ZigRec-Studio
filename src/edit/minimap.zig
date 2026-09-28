//! Минимапа проекта и приближение картинки.
//!
//! Просьба владельца (28.09.2026): «хочу приближать и удалять конкретный
//! регион и видеть минимапу для всего видео — какую область я сейчас вижу.
//! Колёсико приближает и удаляет экран, а не дорожку, если фокус на области
//! с видео».
//!
//! **Зачем минимапа.** На часовой записи в окно помещается десяток секунд.
//! Линейка говорит «23:00», но не говорит, это начало, середина или конец, —
//! и человек ездит вслепую. Минимапа отвечает на вопрос «где я во всём» одной
//! картинкой: весь проект полосой, и на ней рамка — вот что видно сейчас.
//!
//! **Зачем приближать картинку.** Кадр 4K в окне просмотра ужат в полтысячи
//! точек, и мелкий текст на нём не прочитать. Приближение нужно ровно там,
//! куда смотрят, — поэтому оно считается вокруг точки под курсором, а не
//! вокруг центра кадра.
//!
//! Здесь только правила: ни окна, ни Win32 — их можно проверить тестами.
const std = @import("std");

/// Полоска клипа на минимапе.
pub const Block = struct {
    left: i32 = 0,
    width: i32 = 0,
};

/// Куда попадает клип на полосе шириной `span_px`.
///
/// Полоска никогда не уже точки: короткий клип на часовом проекте занимает
/// доли точки, и без этого он исчез бы с минимапы совсем — а он там нужен
/// именно затем, чтобы его было видно и можно было к нему перейти.
pub fn blockFor(total_ns: u64, at_ns: u64, len_ns: u64, span_px: i32) Block {
    if (total_ns == 0 or span_px <= 0) return .{};
    const span: u64 = @intCast(span_px);
    const start = @min(at_ns, total_ns);
    const end = @min(at_ns + len_ns, total_ns);
    const left: i32 = @intCast(start * span / total_ns);
    const right: i32 = @intCast(end * span / total_ns);
    return .{ .left = left, .width = @max(right - left, 1) };
}

/// Какому времени отвечает точка на минимапе.
pub fn timeAt(total_ns: u64, span_px: i32, x_px: i32) u64 {
    if (span_px <= 0) return 0;
    const x = std.math.clamp(x_px, 0, span_px);
    return total_ns * @as(u64, @intCast(x)) / @as(u64, @intCast(span_px));
}

// ------------------------------------------------- приближение картинки

/// Ближе восьми крат смысла нет: кадр 4K, ужатый в полтысячи точек, уже на
/// восьми показывает свои настоящие точки, дальше растёт только размытие.
pub const max_scale: f32 = 8;

/// Насколько приближена картинка и куда смотрим.
///
/// Ноль в `scale` значит «как было», то есть единицу: умолчания всех полей
/// модели обязаны быть нулевыми, иначе они лягут в exe готовыми байтами.
pub const Picture = struct {
    scale: f32 = 0,
    /// Центр видимого куска в долях кадра. Ноль — тоже «как было»: при
    /// единичном масштабе виден весь кадр, и центр может быть любым.
    cx: f32 = 0,
    cy: f32 = 0,

    pub fn factor(self: Picture) f32 {
        if (self.scale <= 1) return 1;
        return @min(self.scale, max_scale);
    }

    pub fn zoomed(self: Picture) bool {
        return self.factor() > 1.001;
    }

    /// Какой кусок кадра показывать. Координаты — в точках исходного кадра.
    pub fn srcRect(self: Picture, w: u32, h: u32) struct { x: i32, y: i32, w: u32, h: u32 } {
        const f = self.factor();
        if (f <= 1.001 or w == 0 or h == 0) return .{ .x = 0, .y = 0, .w = w, .h = h };

        const fw: f32 = @floatFromInt(w);
        const fh: f32 = @floatFromInt(h);
        const vw = fw / f;
        const vh = fh / f;
        // Центр прижимаем так, чтобы кусок не вылез за кадр: показывать
        // пустоту рядом с картинкой незачем, и человек не поймёт, куда уехал.
        const cx = std.math.clamp(if (self.cx == 0) 0.5 else self.cx, vw / fw / 2, 1 - vw / fw / 2);
        const cy = std.math.clamp(if (self.cy == 0) 0.5 else self.cy, vh / fh / 2, 1 - vh / fh / 2);
        const x = cx * fw - vw / 2;
        const y = cy * fh - vh / 2;
        return .{
            .x = @intFromFloat(@max(x, 0)),
            .y = @intFromFloat(@max(y, 0)),
            .w = @intFromFloat(@max(vw, 1)),
            .h = @intFromFloat(@max(vh, 1)),
        };
    }

    /// Приблизить или отдалить, держа точку под курсором на месте.
    ///
    /// `ax`, `ay` — куда смотрит мышь, в долях кадра. Держать точку под
    /// курсором обязательно: иначе после каждого поворота колеса нужное
    /// место уезжает, и его приходится искать заново.
    pub fn zoomAt(self: Picture, ax: f32, ay: f32, closer: bool) Picture {
        const from = self.factor();
        const to = std.math.clamp(if (closer) from * 1.25 else from / 1.25, 1, max_scale);
        if (to <= 1.001) return .{};

        const here_x = if (self.cx == 0) 0.5 else self.cx;
        const here_y = if (self.cy == 0) 0.5 else self.cy;
        // Новый центр: точка под курсором остаётся там же, где была.
        const kx = here_x + (ax - here_x) * (1 - from / to);
        const ky = here_y + (ay - here_y) * (1 - from / to);
        return .{
            .scale = to,
            .cx = std.math.clamp(kx, 0, 1),
            .cy = std.math.clamp(ky, 0, 1),
        };
    }
};

// ---------------------------------------------------------------- тесты

const testing = std.testing;
const sec = std.time.ns_per_s;

test "клип ложится на минимапу там, где он во времени" {
    const total: u64 = 100 * sec;
    // Клип со второй половины занимает правую половину полосы.
    const b = blockFor(total, 50 * sec, 50 * sec, 400);
    try testing.expectEqual(@as(i32, 200), b.left);
    try testing.expectEqual(@as(i32, 200), b.width);
}

test "короткий клип не исчезает с минимапы" {
    // Сотая доля секунды на часовом проекте — тысячные точки.
    const b = blockFor(3600 * sec, 60 * sec, sec / 100, 400);
    try testing.expectEqual(@as(i32, 1), b.width);
}

test "клип за концом проекта не вылезает за полосу" {
    const total: u64 = 10 * sec;
    const b = blockFor(total, 8 * sec, 100 * sec, 200);
    try testing.expect(b.left + b.width <= 200);
}

test "пустой проект не роняет минимапу" {
    try testing.expectEqual(@as(i32, 0), blockFor(0, 0, 0, 400).width);
    try testing.expectEqual(@as(i32, 0), blockFor(10 * sec, 0, sec, 0).width);
    try testing.expectEqual(@as(u64, 0), timeAt(0, 400, 10));
}

test "щелчок по минимапе отвечает времени под ним" {
    const total: u64 = 100 * sec;
    try testing.expectEqual(@as(u64, 0), timeAt(total, 400, 0));
    try testing.expectEqual(@as(u64, 50 * sec), timeAt(total, 400, 200));
    // За краями — края, а не мусор.
    try testing.expectEqual(@as(u64, total), timeAt(total, 400, 1000));
    try testing.expectEqual(@as(u64, 0), timeAt(total, 400, -50));
}

test "умолчание — картинка целиком" {
    const p = Picture{};
    try testing.expectEqual(@as(f32, 1), p.factor());
    try testing.expect(!p.zoomed());
    const r = p.srcRect(1920, 1080);
    try testing.expectEqual(@as(u32, 1920), r.w);
    try testing.expectEqual(@as(i32, 0), r.x);
}

test "приближение показывает меньший кусок кадра" {
    var p = Picture{};
    p = p.zoomAt(0.5, 0.5, true);
    try testing.expect(p.zoomed());
    const r = p.srcRect(1920, 1080);
    try testing.expect(r.w < 1920 and r.h < 1080);
    // Кусок остаётся внутри кадра.
    try testing.expect(r.x >= 0 and r.y >= 0);
    try testing.expect(r.x + @as(i32, @intCast(r.w)) <= 1920);
}

test "точка под курсором остаётся на месте" {
    var p = Picture{};
    // Смотрим в левый верхний угол и приближаем несколько раз.
    var i: usize = 0;
    while (i < 5) : (i += 1) p = p.zoomAt(0.2, 0.2, true);
    const r = p.srcRect(1000, 1000);
    // Видимый кусок должен накрывать ту самую точку 0.2 (то есть 200).
    try testing.expect(r.x <= 200 and r.x + @as(i32, @intCast(r.w)) >= 200);
    try testing.expect(r.y <= 200 and r.y + @as(i32, @intCast(r.h)) >= 200);
}

test "дальше предела не приближается и не отдаляется" {
    var p = Picture{};
    var i: usize = 0;
    while (i < 100) : (i += 1) p = p.zoomAt(0.5, 0.5, true);
    try testing.expectEqual(max_scale, p.factor());

    i = 0;
    while (i < 100) : (i += 1) p = p.zoomAt(0.5, 0.5, false);
    // Отдалили до конца — вернулись к «как было», со всеми нулями.
    try testing.expectEqual(@as(f32, 1), p.factor());
    try testing.expectEqual(@as(f32, 0), p.scale);
    try testing.expect(!p.zoomed());
}

test "кусок не вылезает за край, даже если смотреть в угол" {
    var p = Picture{ .scale = 4, .cx = 0.99, .cy = 0.01 };
    const r = p.srcRect(800, 600);
    try testing.expect(r.x >= 0 and r.y >= 0);
    try testing.expect(r.x + @as(i32, @intCast(r.w)) <= 800);
    try testing.expect(r.y + @as(i32, @intCast(r.h)) <= 600);
}
