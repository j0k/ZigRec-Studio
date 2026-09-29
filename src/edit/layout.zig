//! Раскладка кадра: где в итоговом видео лежит каждый источник.
//!
//! Замысел владельца (29.09.2026, эпик #156): писать несколько областей и
//! окон сразу, а потом двигать их кусочки на результирующем видео.
//!
//! **Места считаются в долях кадра, а не в точках.** Записали на 4K, а
//! отдаём 1080p — доли переживут это без пересчёта, а точки пришлось бы
//! пересчитывать в каждом месте, где они встречаются, и однажды забыть.
//!
//! **Кусочек не может уехать за кадр целиком.** Уехавший за край кусочек
//! исчезает с экрана, и вернуть его нечем: ухватиться не за что. Поэтому
//! часть его всегда остаётся видимой — это не украшение, это единственный
//! способ не потерять источник насовсем.
//!
//! Здесь только правило: ни окна, ни кодировщика. Перетаскивание мышью
//! иначе не проверить — а проверять его надо, оно тут главное.
const std = @import("std");

/// Сколько источников имеет смысл сводить в один кадр.
///
/// Восемь — это уже больше, чем машина тянет кодировать одновременно
/// (#160), но правило не должно упираться раньше, чем железо.
pub const max_pieces: usize = 8;

/// Насколько кусочек обязан остаться в кадре: по четверти каждой стороны.
///
/// Не «хотя бы точка»: за одну точку не ухватишься мышью, и кусочек
/// считался бы видимым, оставаясь потерянным.
pub const keep_in: f32 = 0.25;

/// Один кусочек: источник и его место в кадре.
pub const Piece = struct {
    /// Номер источника в проекте.
    source: u16 = 0,
    /// Левый верхний угол в долях кадра. Ноль — левый верхний угол.
    x: f32 = 0,
    y: f32 = 0,
    /// Размер в долях кадра. Ноль значит «во весь кадр»: это умолчание
    /// одного источника, и оно же — нулевое умолчание модели.
    w: f32 = 0,
    h: f32 = 0,

    pub fn width(self: Piece) f32 {
        return if (self.w <= 0) 1 else self.w;
    }

    pub fn height(self: Piece) f32 {
        return if (self.h <= 0) 1 else self.h;
    }

    pub fn right(self: Piece) f32 {
        return self.x + self.width();
    }

    pub fn bottom(self: Piece) f32 {
        return self.y + self.height();
    }

    /// Лежит ли точка внутри кусочка. Доли, как и всё здесь.
    pub fn covers(self: Piece, px: f32, py: f32) bool {
        return px >= self.x and px < self.right() and py >= self.y and py < self.bottom();
    }

    /// Место в точках готового кадра.
    pub fn inFrame(self: Piece, frame_w: u32, frame_h: u32) Rect {
        const fw: f32 = @floatFromInt(frame_w);
        const fh: f32 = @floatFromInt(frame_h);
        // Сторона всегда чётная: кодировщик считает цветность по парам
        // точек — та же причина, что и в формате кадра.
        const w = even(@intFromFloat(@max(self.width() * fw, 2)));
        const h = even(@intFromFloat(@max(self.height() * fh, 2)));
        return .{
            .x = @intFromFloat(self.x * fw),
            .y = @intFromFloat(self.y * fh),
            .w = w,
            .h = h,
        };
    }
};

pub const Rect = struct { x: i32 = 0, y: i32 = 0, w: u32 = 0, h: u32 = 0 };

fn even(v: u32) u32 {
    return v & ~@as(u32, 1);
}

/// Прижать кусочек так, чтобы он не потерялся за кадром.
pub fn keep(piece: Piece) Piece {
    var out = piece;
    const w = out.width();
    const h = out.height();
    // Слева и сверху: за край можно уйти не больше, чем на три четверти.
    out.x = std.math.clamp(out.x, -(w * (1 - keep_in)), 1 - w * keep_in);
    out.y = std.math.clamp(out.y, -(h * (1 - keep_in)), 1 - h * keep_in);
    return out;
}

/// Раскладка целиком: порядок в списке — порядок наложения, последний
/// сверху. Так же, как слои везде: «последний нарисованный виден».
pub const Layout = struct {
    pieces: [max_pieces]Piece = @splat(.{}),
    count: usize = 0,

    pub fn list(self: *const Layout) []const Piece {
        return self.pieces[0..self.count];
    }

    pub fn add(self: *Layout, piece: Piece) bool {
        if (self.count >= max_pieces) return false;
        self.pieces[self.count] = keep(piece);
        self.count += 1;
        return true;
    }

    /// Подвинуть кусочек. Уехать за кадр целиком не даст.
    pub fn move(self: *Layout, index: usize, dx: f32, dy: f32) void {
        if (index >= self.count) return;
        var p = self.pieces[index];
        p.x += dx;
        p.y += dy;
        self.pieces[index] = keep(p);
    }

    /// Изменить размер за угол. Меньше сотой доли кадра не делаем: такой
    /// кусочек не виден и не хватается мышью.
    pub fn resize(self: *Layout, index: usize, want_w: f32, want_h: f32) void {
        if (index >= self.count) return;
        var p = self.pieces[index];
        p.w = std.math.clamp(want_w, 0.01, 4);
        p.h = std.math.clamp(want_h, 0.01, 4);
        self.pieces[index] = keep(p);
    }

    /// В какой кусочек ткнули. Сверху вниз: верхний перехватывает щелчок,
    /// иначе нижний забирал бы нажатия у того, что видно.
    pub fn at(self: *const Layout, px: f32, py: f32) ?usize {
        if (self.count == 0) return null;
        var i: usize = self.count;
        while (i > 0) {
            i -= 1;
            if (self.pieces[i].covers(px, py)) return i;
        }
        return null;
    }

    /// Поднять кусочек наверх: его и двигают, значит на него и смотрят.
    pub fn raise(self: *Layout, index: usize) usize {
        if (index + 1 >= self.count) return index;
        const moved = self.pieces[index];
        var i = index;
        while (i + 1 < self.count) : (i += 1) self.pieces[i] = self.pieces[i + 1];
        self.pieces[self.count - 1] = moved;
        return self.count - 1;
    }

    pub fn remove(self: *Layout, index: usize) void {
        if (index >= self.count) return;
        var i = index;
        while (i + 1 < self.count) : (i += 1) self.pieces[i] = self.pieces[i + 1];
        self.count -= 1;
    }
};

// -------------------------------------------------- готовые раскладки

/// Разложить поровну: столбцами и строками, как ляжет.
///
/// Нужно затем, чтобы после записи сразу было видно всё: источники,
/// сваленные друг на друга в углу, человек разгребал бы руками.
pub fn grid(count: usize, out: *Layout) void {
    out.* = .{};
    if (count == 0) return;
    if (count == 1) {
        _ = out.add(.{ .source = 0 });
        return;
    }
    // Столбцов — корень из числа кусочков, округлённый вверх: так сетка
    // выходит ближе к квадрату, а не полосой.
    var cols: usize = 1;
    while (cols * cols < count) cols += 1;
    const rows = (count + cols - 1) / cols;
    const w = 1.0 / @as(f32, @floatFromInt(cols));
    const h = 1.0 / @as(f32, @floatFromInt(rows));
    for (0..@min(count, max_pieces)) |i| {
        _ = out.add(.{
            .source = @intCast(i),
            .x = @as(f32, @floatFromInt(i % cols)) * w,
            .y = @as(f32, @floatFromInt(i / cols)) * h,
            .w = w,
            .h = h,
        });
    }
}

/// Картинка в картинке: первый во весь кадр, остальные — уголком.
pub fn pictureInPicture(count: usize, out: *Layout) void {
    out.* = .{};
    if (count == 0) return;
    _ = out.add(.{ .source = 0 });
    const side: f32 = 0.25;
    const pad: f32 = 0.02;
    for (1..@min(count, max_pieces)) |i| {
        // Вторые и следующие идут вверх по правому краю, чтобы не залезать
        // друг на друга: сложенные в одну точку, они были бы бесполезны.
        const step = @as(f32, @floatFromInt(i - 1)) * (side + pad);
        _ = out.add(.{
            .source = @intCast(i),
            .x = 1 - side - pad,
            .y = 1 - side - pad - step,
            .w = side,
            .h = side,
        });
    }
}

// ---------------------------------------------------------------- тесты

const testing = std.testing;

test "умолчание — один кусочек во весь кадр" {
    const p = Piece{};
    try testing.expectEqual(@as(f32, 1), p.width());
    try testing.expectEqual(@as(f32, 1), p.height());
    const r = p.inFrame(1920, 1080);
    try testing.expectEqual(@as(u32, 1920), r.w);
    try testing.expectEqual(@as(u32, 1080), r.h);
    try testing.expectEqual(@as(i32, 0), r.x);
}

test "стороны в кадре всегда чётные" {
    const p = Piece{ .w = 0.3333, .h = 0.3333 };
    const r = p.inFrame(1921, 1081);
    try testing.expectEqual(@as(u32, 0), r.w % 2);
    try testing.expectEqual(@as(u32, 0), r.h % 2);
}

test "кусочек не теряется за краем кадра" {
    var l = Layout{};
    try testing.expect(l.add(.{ .source = 1, .x = 0.4, .y = 0.4, .w = 0.2, .h = 0.2 }));

    // Уводим далеко влево-вверх — четверть обязана остаться видимой.
    l.move(0, -10, -10);
    const p = l.pieces[0];
    // Ровно четверть и остаётся: правило прижимает точно к пределу, а не
    // «чуть больше». Первый заход теста требовал строгого «больше» и падал
    // на верном правиле.
    try testing.expectApproxEqAbs(@as(f32, 0.2 * keep_in), p.right(), 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.2 * keep_in), p.bottom(), 0.001);

    // И вправо-вниз — тоже.
    l.move(0, 10, 10);
    try testing.expect(l.pieces[0].x < 1);
    try testing.expect(l.pieces[0].y < 1);
}

test "щелчок берёт верхний кусочек, а не нижний" {
    var l = Layout{};
    _ = l.add(.{ .source = 0 }); // во весь кадр
    _ = l.add(.{ .source = 1, .x = 0.1, .y = 0.1, .w = 0.2, .h = 0.2 });

    // В точке, где оба, берём тот, что сверху, — второй.
    try testing.expectEqual(@as(usize, 1), l.at(0.15, 0.15).?);
    // Там, где только нижний, — нижний.
    try testing.expectEqual(@as(usize, 0), l.at(0.8, 0.8).?);
    // Мимо всего — ничего. Пустая раскладка тоже не роняет.
    var empty = Layout{};
    try testing.expect(empty.at(0.5, 0.5) == null);
}

test "поднятый кусочек оказывается сверху и остаётся собой" {
    var l = Layout{};
    _ = l.add(.{ .source = 7, .x = 0.1, .y = 0.1, .w = 0.2, .h = 0.2 });
    _ = l.add(.{ .source = 8 });
    const now = l.raise(0);
    try testing.expectEqual(@as(usize, 1), now);
    try testing.expectEqual(@as(u16, 7), l.pieces[1].source);
    try testing.expectEqual(@as(u16, 8), l.pieces[0].source);
    // Теперь щелчок в его области берёт его.
    try testing.expectEqual(@as(usize, 1), l.at(0.15, 0.15).?);
}

test "размер держится в разумных пределах" {
    var l = Layout{};
    _ = l.add(.{ .source = 0, .x = 0.2, .y = 0.2, .w = 0.3, .h = 0.3 });
    l.resize(0, 0.0001, 0.0001);
    try testing.expect(l.pieces[0].width() >= 0.01);
    l.resize(0, 100, 100);
    try testing.expect(l.pieces[0].width() <= 4);
}

test "сетка раскладывает поровну и никого не теряет" {
    var l = Layout{};
    grid(4, &l);
    try testing.expectEqual(@as(usize, 4), l.count);
    // Четыре кусочка — это два на два.
    try testing.expectApproxEqAbs(@as(f32, 0.5), l.pieces[0].width(), 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0), l.pieces[0].x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.5), l.pieces[3].x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.5), l.pieces[3].y, 0.001);
    // Все на своих местах и никто не наложился.
    for (l.list(), 0..) |a, i| {
        for (l.list(), 0..) |b, j| {
            if (i == j) continue;
            const apart = a.right() <= b.x + 0.001 or b.right() <= a.x + 0.001 or
                a.bottom() <= b.y + 0.001 or b.bottom() <= a.y + 0.001;
            try testing.expect(apart);
        }
    }
}

test "сетка для одного — это весь кадр" {
    var l = Layout{};
    grid(1, &l);
    try testing.expectEqual(@as(usize, 1), l.count);
    try testing.expectEqual(@as(f32, 1), l.pieces[0].width());

    // И ноль источников не даёт ни одного кусочка, а не один пустой.
    grid(0, &l);
    try testing.expectEqual(@as(usize, 0), l.count);
}

test "картинка в картинке не складывает уголки в одну точку" {
    var l = Layout{};
    pictureInPicture(3, &l);
    try testing.expectEqual(@as(usize, 3), l.count);
    try testing.expectEqual(@as(f32, 1), l.pieces[0].width());
    // Два уголка стоят в разных местах.
    try testing.expect(@abs(l.pieces[1].y - l.pieces[2].y) > 0.2);
    // И оба внутри кадра.
    for (l.list()[1..]) |p| {
        try testing.expect(p.x >= 0 and p.right() <= 1.001);
        try testing.expect(p.y >= 0 and p.bottom() <= 1.001);
    }
}

test "больше восьми кусочков не берём" {
    var l = Layout{};
    var i: usize = 0;
    while (i < max_pieces + 5) : (i += 1) {
        const ok = l.add(.{ .source = @intCast(i % 8) });
        if (i < max_pieces) try testing.expect(ok) else try testing.expect(!ok);
    }
    try testing.expectEqual(max_pieces, l.count);
}

test "убранный кусочек не оставляет дырки" {
    var l = Layout{};
    _ = l.add(.{ .source = 1 });
    _ = l.add(.{ .source = 2 });
    _ = l.add(.{ .source = 3 });
    l.remove(1);
    try testing.expectEqual(@as(usize, 2), l.count);
    try testing.expectEqual(@as(u16, 1), l.pieces[0].source);
    try testing.expectEqual(@as(u16, 3), l.pieces[1].source);
    // Убрать несуществующий — ничего не меняет.
    l.remove(99);
    try testing.expectEqual(@as(usize, 2), l.count);
}
