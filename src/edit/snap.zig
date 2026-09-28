//! Магнит: правка притягивается к ближайшему ориентиру.
//!
//! Просьба владельца (28.09.2026): «когда редактирую звук, чтобы притягивалось
//! к ближайшему — как в Xara Designer к ближайшей крупной фигуре».
//!
//! Ориентир — это место на времени, к которому человек и так целится: край
//! соседнего клипа, метка, указатель, начало проекта. Попасть в них мышью
//! точно нельзя: один пиксель при обычном масштабе — это десятки
//! миллисекунд, и «встык» на глаз всегда оказывается с щелью или с нахлёстом.
//!
//! **Допуск задаётся в пикселях, а не во времени.** Притяжение должно
//! ощущаться одинаково при любом масштабе: на мелком масштабе восемь пикселей
//! это секунды, на крупном — кадры, и в обоих случаях это «мышь рядом».
//!
//! Здесь только правило: что куда притянуть. Ни окна, ни проекта — поэтому
//! его можно проверить тестами, а не «подвигать мышью и посмотреть».
const std = @import("std");

/// Чем ориентир был: это видно в строке состояния, чтобы человек понимал,
/// к чему его притянуло, а не считал, что редактор промахнулся.
pub const Kind = enum {
    /// Начало или конец клипа — в том числе на соседних дорожках.
    clip_edge,
    /// Метка на линейке.
    mark,
    /// Указатель воспроизведения.
    playhead,
    /// Начало проекта.
    zero,
    /// Ключевой кадр видео.
    key_frame,
    /// Соседняя точка кривой громкости.
    ///
    /// При правке звука целятся в неё чаще всего: спад на одной дорожке
    /// ставят вровень с подъёмом на другой, а на глаз это не совпадает
    /// никогда.
    curve,

    pub fn label(self: Kind) []const u8 {
        return switch (self) {
            .clip_edge => "краю клипа",
            .mark => "метке",
            .playhead => "указателю",
            .zero => "началу",
            .key_frame => "ключевому кадру",
            .curve => "соседней точке",
        };
    }
};

pub const Point = struct {
    at_ns: u64,
    kind: Kind,
};

/// Сколько пикселей считается «рядом». Восемь — примерно половина ширины
/// пальца на ручке ползунка: ближе человек не целится, дальше начинает
/// мешать.
pub const grab_px: i32 = 8;

/// Допуск во времени: столько наносекунд укладывается в `grab_px` при этом
/// масштабе. `ns_per_px` берётся у вида.
pub fn toleranceNs(ns_per_px: u64) u64 {
    return ns_per_px * @as(u64, @intCast(grab_px));
}

/// Ближайший ориентир к `want_ns`, если он ближе допуска.
///
/// Ровно один ответ, а не «первый подходящий»: когда рядом и метка, и край
/// клипа, притягивать надо к тому, что ближе, иначе магнит начинает спорить
/// с глазами. При равном расстоянии берём тот, что раньше в списке — порядок
/// задаёт тот, кто собирал ориентиры, и он знает, что важнее.
pub fn nearest(want_ns: u64, points: []const Point, tolerance_ns: u64) ?Point {
    var best: ?Point = null;
    var best_gap: u64 = std.math.maxInt(u64);
    for (points) |p| {
        const gap = if (p.at_ns > want_ns) p.at_ns - want_ns else want_ns - p.at_ns;
        if (gap > tolerance_ns) continue;
        if (gap < best_gap) {
            best_gap = gap;
            best = p;
        }
    }
    return best;
}

/// Притянуть время, если рядом есть ориентир; иначе вернуть как было.
pub fn apply(want_ns: u64, points: []const Point, tolerance_ns: u64) u64 {
    const hit = nearest(want_ns, points, tolerance_ns) orelse return want_ns;
    return hit.at_ns;
}

/// Притянуть отрезок: смотрим на оба конца и двигаем весь отрезок на ту
/// поправку, которая меньше.
///
/// Клип тянут за середину, а встык он должен вставать любым краем: начало —
/// к концу соседа, конец — к началу следующего. Поэтому решение принимается
/// по обоим концам сразу, а не по тому, за который ухватились.
pub fn applySpan(at_ns: u64, len_ns: u64, points: []const Point, tolerance_ns: u64) u64 {
    const left = nearest(at_ns, points, tolerance_ns);
    const right = nearest(at_ns + len_ns, points, tolerance_ns);

    const left_gap: u64 = if (left) |p| gapOf(p.at_ns, at_ns) else std.math.maxInt(u64);
    const right_gap: u64 = if (right) |p| gapOf(p.at_ns, at_ns + len_ns) else std.math.maxInt(u64);

    if (left == null and right == null) return at_ns;
    if (left_gap <= right_gap) return left.?.at_ns;
    // Тянем за правый край: начало отрезка уезжает на ту же поправку.
    const want_end = right.?.at_ns;
    return if (want_end > len_ns) want_end - len_ns else 0;
}

fn gapOf(a: u64, b: u64) u64 {
    return if (a > b) a - b else b - a;
}

/// Сколько ориентиров разумно держать: столько их и собирают.
pub const max_points: usize = 256;

/// Копилка ориентиров: собрать, не заводя памяти.
pub const Gather = struct {
    buf: [max_points]Point = undefined,
    count: usize = 0,

    pub fn add(self: *Gather, at_ns: u64, kind: Kind) void {
        if (self.count >= self.buf.len) return;
        // Одно и то же место дважды не нужно: список короче — ответ тот же.
        for (self.buf[0..self.count]) |p| {
            if (p.at_ns == at_ns and p.kind == kind) return;
        }
        self.buf[self.count] = .{ .at_ns = at_ns, .kind = kind };
        self.count += 1;
    }

    pub fn list(self: *const Gather) []const Point {
        return self.buf[0..self.count];
    }
};

// ---------------------------------------------------------------- тесты

const testing = std.testing;
const ms = std.time.ns_per_ms;

test "притягивает к ближайшему, а не к первому попавшемуся" {
    const points = [_]Point{
        .{ .at_ns = 1000 * ms, .kind = .mark },
        .{ .at_ns = 1050 * ms, .kind = .clip_edge },
    };
    // Ближе край клипа — к нему и притянет, хотя метка в списке первая.
    const hit = nearest(1045 * ms, &points, 100 * ms).?;
    try testing.expectEqual(Kind.clip_edge, hit.kind);
    try testing.expectEqual(@as(u64, 1050 * ms), hit.at_ns);

    // Ближе метка — к ней.
    try testing.expectEqual(Kind.mark, nearest(1005 * ms, &points, 100 * ms).?.kind);
}

test "дальше допуска — не притягивает вовсе" {
    const points = [_]Point{.{ .at_ns = 1000 * ms, .kind = .mark }};
    try testing.expect(nearest(1200 * ms, &points, 100 * ms) == null);
    // И время остаётся как было.
    try testing.expectEqual(@as(u64, 1200 * ms), apply(1200 * ms, &points, 100 * ms));
    // А внутри допуска — становится ориентиром.
    try testing.expectEqual(@as(u64, 1000 * ms), apply(1080 * ms, &points, 100 * ms));
}

test "пустой список ориентиров ничего не меняет" {
    try testing.expect(nearest(500 * ms, &.{}, 100 * ms) == null);
    try testing.expectEqual(@as(u64, 500 * ms), apply(500 * ms, &.{}, 100 * ms));
}

test "допуск считается в пикселях: на разных масштабах он разный во времени" {
    // Мелкий масштаб: в пикселе секунда — допуск восемь секунд.
    try testing.expectEqual(@as(u64, 8 * std.time.ns_per_s), toleranceNs(std.time.ns_per_s));
    // Крупный: в пикселе миллисекунда — восемь миллисекунд.
    try testing.expectEqual(@as(u64, 8 * ms), toleranceNs(ms));
}

test "клип встаёт встык любым краем" {
    const len: u64 = 500 * ms;
    const points = [_]Point{
        .{ .at_ns = 1000 * ms, .kind = .clip_edge },
        .{ .at_ns = 2000 * ms, .kind = .clip_edge },
    };
    // Начало рядом с первым краем — клип встаёт на него.
    try testing.expectEqual(@as(u64, 1000 * ms), applySpan(1020 * ms, len, &points, 100 * ms));
    // Конец рядом со вторым краем — клип подъезжает концом.
    try testing.expectEqual(@as(u64, 1500 * ms), applySpan(1520 * ms, len, &points, 100 * ms));
    // Оба края далеко — клип остаётся где был.
    try testing.expectEqual(@as(u64, 1300 * ms), applySpan(1300 * ms, len, &points, 100 * ms));
}

test "клип у самого начала не уезжает за ноль" {
    const len: u64 = 500 * ms;
    const points = [_]Point{.{ .at_ns = 450 * ms, .kind = .clip_edge }};
    // Конец (510 мс) притягивается к 450 мс, и начало ушло бы в минус —
    // остаётся ноль. Первый заход теста брал ориентир вне допуска и ничего
    // на самом деле не проверял.
    try testing.expectEqual(@as(u64, 0), applySpan(10 * ms, len, &points, 100 * ms));
}

test "копилка не держит одно место дважды и не переполняется" {
    var g = Gather{};
    g.add(1000 * ms, .mark);
    g.add(1000 * ms, .mark);
    try testing.expectEqual(@as(usize, 1), g.count);
    // Другой вид в том же месте — это другой ориентир: в строке состояния
    // человеку говорят, к чему притянуло.
    g.add(1000 * ms, .clip_edge);
    try testing.expectEqual(@as(usize, 2), g.count);

    var i: usize = 0;
    while (i < max_points * 2) : (i += 1) g.add(@as(u64, i + 5) * ms, .clip_edge);
    try testing.expectEqual(max_points, g.count);
    try testing.expectEqual(max_points, g.list().len);
}

test "равное расстояние — берём того, кто раньше в списке" {
    const points = [_]Point{
        .{ .at_ns = 900 * ms, .kind = .playhead },
        .{ .at_ns = 1100 * ms, .kind = .mark },
    };
    // Ровно посередине: порядок задаёт тот, кто собирал.
    try testing.expectEqual(Kind.playhead, nearest(1000 * ms, &points, 500 * ms).?.kind);
}

test "названия ориентиров — для строки состояния" {
    try testing.expectEqualStrings("краю клипа", Kind.clip_edge.label());
    try testing.expectEqualStrings("метке", Kind.mark.label());
    try testing.expectEqualStrings("началу", Kind.zero.label());
    try testing.expectEqualStrings("соседней точке", Kind.curve.label());
}
