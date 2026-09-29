//! Формат кадра: классическое разрешение или фиксированное соотношение.
//!
//! Просьба владельца (28.09.2026): «чтобы я мог не только захватить область,
//! но и выставить классическое разрешение либо сделать соотношение сторон
//! фиксированным», выпадающим меню в самой кнопке «Записать область».
//!
//! **Зачем вообще.** Обведённая на глаз область почти никогда не выходит ни
//! 1920×1080, ни 16:9. Ролик потом кладут на YouTube, и тот дорисовывает
//! поля, а мелкий текст в записи размывается пересчётом. Проще не давать
//! промахнуться, чем чинить это после записи.
//!
//! **Сторона всегда чётная.** Кодировщик считает цветность по парам точек,
//! и нечётная сторона кончается либо отказом, либо тихим округлением не в
//! ту сторону. Об этом легко забыть здесь и потом долго искать причину
//! в кодировщике.
//!
//! Здесь только правило: во что превратить обведённое мышью. Ни окна, ни
//! Win32 — поэтому его можно проверить тестами, а не «обвести и посмотреть».
const std = @import("std");

pub const Rect = struct {
    x: i32 = 0,
    y: i32 = 0,
    w: u32 = 0,
    h: u32 = 0,
};

pub const Mode = enum {
    /// Как обвёл, так и будет.
    free,
    /// Точный размер: обведённое задаёт только угол и направление.
    fixed,
    /// Соотношение сторон держим, размер — какой обвёл.
    ratio,
};

/// Что выбрано в меню. Ноль во всех полях — «свободно», как и было: правило
/// проекта требует, чтобы умолчание всех полей было нулевым.
pub const Choice = struct {
    mode: Mode = .free,
    /// Для `fixed` — ширина в точках, для `ratio` — левое число отношения.
    w: u32 = 0,
    /// Для `fixed` — высота в точках, для `ratio` — правое число отношения.
    h: u32 = 0,

    /// Подпись для кнопки и меню: «1920×1080», «16:9», «свободно».
    pub fn label(self: Choice, buf: []u8) []const u8 {
        return switch (self.mode) {
            .free => "свободно",
            .fixed => std.fmt.bufPrint(buf, "{d}×{d}", .{ self.w, self.h }) catch "свободно",
            .ratio => std.fmt.bufPrint(buf, "{d}:{d}", .{ self.w, self.h }) catch "свободно",
        };
    }

    pub fn same(self: Choice, other: Choice) bool {
        return self.mode == other.mode and self.w == other.w and self.h == other.h;
    }
};

/// Влезает ли такой кадр на этот экран.
///
/// Владелец (29.09.2026): «я вижу эти разрешения для записи, но на компе с
/// другими разрешениями вижу то же самое». Список был записан намертво, и
/// на ноутбуке 1366×768 первые три пункта означали область больше экрана —
/// то есть неработающий выбор, о котором окно молчало.
pub fn fits(choice: Choice, screen_w: u32, screen_h: u32) bool {
    if (choice.mode != .fixed) return true;
    if (screen_w == 0 or screen_h == 0) return true;
    return choice.w <= screen_w and choice.h <= screen_h;
}

/// Размеры, посчитанные от самого экрана: целиком, половина, четверть.
///
/// Это то, что работает на любой машине, в отличие от списка чисел:
/// «половина экрана» одинаково осмысленна и на 4K, и на ноутбуке. Доли
/// берём по СТОРОНЕ, а не по площади: «половина» для человека — это
/// половина ширины и половина высоты, а не кадр в 0.7 от стороны.
pub fn screenSizes(screen_w: u32, screen_h: u32, out: *[3]Choice) usize {
    if (screen_w == 0 or screen_h == 0) return 0;
    const parts = [_]u32{ 1, 2, 4 };
    var n: usize = 0;
    for (parts) |part| {
        const w = screen_w / part;
        const h = screen_h / part;
        // Слишком мелкое в список не кладём: кадр в двести точек шириной
        // никто не пишет, а пункт меню занимает место.
        if (w < 320 or h < 240) continue;
        out[n] = .{ .mode = .fixed, .w = w & ~@as(u32, 1), .h = h & ~@as(u32, 1) };
        n += 1;
    }
    return n;
}

/// Классические разрешения — те, что ждёт всякий, кто потом смотрит ролик.
pub const sizes = [_]Choice{
    .{ .mode = .fixed, .w = 3840, .h = 2160 },
    .{ .mode = .fixed, .w = 2560, .h = 1440 },
    .{ .mode = .fixed, .w = 1920, .h = 1080 },
    .{ .mode = .fixed, .w = 1280, .h = 720 },
    .{ .mode = .fixed, .w = 854, .h = 480 },
};

/// Соотношения сторон. Вертикальное 9:16 — для телефона, и оно не редкость.
pub const ratios = [_]Choice{
    .{ .mode = .ratio, .w = 16, .h = 9 },
    .{ .mode = .ratio, .w = 4, .h = 3 },
    .{ .mode = .ratio, .w = 1, .h = 1 },
    .{ .mode = .ratio, .w = 9, .h = 16 },
};

/// Прижать к чётному вниз: кодировщику нужны пары точек.
fn even(v: u32) u32 {
    return v & ~@as(u32, 1);
}

/// Во что превращается обведённое мышью.
///
/// `start` — где нажали, `cur` — где мышь сейчас. Точный размер отсчитывается
/// ОТ ТОЧКИ НАЖАТИЯ в ту сторону, куда ведут мышь: человек ставит угол, а не
/// центр, и прямоугольник, прыгающий центром под курсор, ощущается поломкой.
pub fn apply(start_x: i32, start_y: i32, cur_x: i32, cur_y: i32, choice: Choice) Rect {
    const left = @min(start_x, cur_x);
    const top = @min(start_y, cur_y);
    const drawn_w: u32 = @intCast(@abs(cur_x - start_x));
    const drawn_h: u32 = @intCast(@abs(cur_y - start_y));

    switch (choice.mode) {
        .free => return .{ .x = left, .y = top, .w = even(drawn_w), .h = even(drawn_h) },
        .fixed => {
            if (choice.w == 0 or choice.h == 0) {
                return .{ .x = left, .y = top, .w = even(drawn_w), .h = even(drawn_h) };
            }
            const w = even(choice.w);
            const h = even(choice.h);
            // Влево и вверх — тоже можно: тогда угол оказывается справа снизу.
            const x = if (cur_x < start_x) start_x - @as(i32, @intCast(w)) else start_x;
            const y = if (cur_y < start_y) start_y - @as(i32, @intCast(h)) else start_y;
            return .{ .x = x, .y = y, .w = w, .h = h };
        },
        .ratio => {
            if (choice.w == 0 or choice.h == 0 or drawn_w == 0 or drawn_h == 0) {
                return .{ .x = left, .y = top, .w = even(drawn_w), .h = even(drawn_h) };
            }
            // Вписываем в обведённое, а не описываем вокруг: выйти за границы
            // экрана нельзя, а не добрать десяток точек — можно.
            var w = drawn_w;
            var h = w * choice.h / choice.w;
            if (h > drawn_h) {
                h = drawn_h;
                w = h * choice.w / choice.h;
            }
            w = even(w);
            h = even(h);
            // Угол остаётся там, где нажали: уменьшилась та сторона, вдоль
            // которой места не хватило.
            const x = if (cur_x < start_x) start_x - @as(i32, @intCast(w)) else start_x;
            const y = if (cur_y < start_y) start_y - @as(i32, @intCast(h)) else start_y;
            return .{ .x = x, .y = y, .w = w, .h = h };
        },
    }
}

// ---------------------------------------------------------------- тесты

const testing = std.testing;

test "свободно — как обвели, только чётной стороной" {
    const r = apply(10, 20, 111, 141, .{});
    try testing.expectEqual(@as(i32, 10), r.x);
    try testing.expectEqual(@as(i32, 20), r.y);
    // 101 и 121 — нечётные: кодировщик их не возьмёт.
    try testing.expectEqual(@as(u32, 100), r.w);
    try testing.expectEqual(@as(u32, 120), r.h);
}

test "точный размер не зависит от того, сколько обвели" {
    const hd = Choice{ .mode = .fixed, .w = 1920, .h = 1080 };
    const small = apply(100, 100, 130, 110, hd);
    try testing.expectEqual(@as(u32, 1920), small.w);
    try testing.expectEqual(@as(u32, 1080), small.h);
    // Угол — там, где нажали.
    try testing.expectEqual(@as(i32, 100), small.x);
    try testing.expectEqual(@as(i32, 100), small.y);

    const big = apply(100, 100, 3000, 2000, hd);
    try testing.expectEqual(@as(u32, 1920), big.w);
    try testing.expectEqual(@as(i32, 100), big.x);
}

test "ведём мышь вверх и влево — угол оказывается справа снизу" {
    const hd = Choice{ .mode = .fixed, .w = 1920, .h = 1080 };
    const r = apply(2000, 1500, 1900, 1400, hd);
    // Прямоугольник кончается там, где нажали, а не начинается.
    try testing.expectEqual(@as(i32, 2000 - 1920), r.x);
    try testing.expectEqual(@as(i32, 1500 - 1080), r.y);
    try testing.expectEqual(@as(u32, 1920), r.w);
}

test "соотношение вписывается в обведённое, а не вылезает за него" {
    const wide = Choice{ .mode = .ratio, .w = 16, .h = 9 };
    // Обвели почти квадрат: по высоте места меньше, она и задаёт размер.
    const r = apply(0, 0, 1000, 1000, wide);
    try testing.expectEqual(@as(u32, 1000), r.w);
    try testing.expectEqual(@as(u32, 562), r.h); // 1000*9/16 = 562.5 → чётное вниз
    try testing.expect(r.w <= 1000 and r.h <= 1000);

    // Обвели длинную полосу: теперь не хватает ширины.
    const flat = apply(0, 0, 1000, 200, wide);
    try testing.expectEqual(@as(u32, 354), flat.w); // 200*16/9 = 355.5 → 354
    try testing.expectEqual(@as(u32, 200), flat.h);
    try testing.expect(flat.w <= 1000 and flat.h <= 200);
}

test "квадрат и вертикаль считаются тем же правилом" {
    const square = apply(0, 0, 800, 600, .{ .mode = .ratio, .w = 1, .h = 1 });
    try testing.expectEqual(@as(u32, 600), square.w);
    try testing.expectEqual(@as(u32, 600), square.h);

    const phone = apply(0, 0, 800, 600, .{ .mode = .ratio, .w = 9, .h = 16 });
    try testing.expectEqual(@as(u32, 336), phone.w); // 600*9/16 = 337.5 → 336
    try testing.expectEqual(@as(u32, 600), phone.h);
}

test "пустое обведение не ломает ни одно правило" {
    // Щелчок без протяжки: ноль на ноль и никакого деления на ноль.
    try testing.expectEqual(@as(u32, 0), apply(5, 5, 5, 5, .{}).w);
    try testing.expectEqual(@as(u32, 0), apply(5, 5, 5, 5, .{ .mode = .ratio, .w = 16, .h = 9 }).w);
    // А точный размер ставится и от щелчка: обводить для него незачем.
    const hd = apply(5, 5, 5, 5, .{ .mode = .fixed, .w = 1280, .h = 720 });
    try testing.expectEqual(@as(u32, 1280), hd.w);
}

test "кривой выбор не роняет правило" {
    // Ноль в отношении пришёл бы только из ошибки, но делить на него нельзя.
    const r = apply(0, 0, 100, 50, .{ .mode = .ratio, .w = 0, .h = 9 });
    try testing.expectEqual(@as(u32, 100), r.w);
    const f = apply(0, 0, 100, 50, .{ .mode = .fixed, .w = 0, .h = 0 });
    try testing.expectEqual(@as(u32, 100), f.w);
}

test "что не влезает на экран, то видно сразу" {
    const uhd = Choice{ .mode = .fixed, .w = 3840, .h = 2160 };
    const hd = Choice{ .mode = .fixed, .w = 1280, .h = 720 };
    // Ноутбук 1366×768: 4K на него не ложится, 720p ложится.
    try testing.expect(!fits(uhd, 1366, 768));
    try testing.expect(fits(hd, 1366, 768));
    // Соотношение сторон влезает всегда: оно не задаёт размера.
    try testing.expect(fits(.{ .mode = .ratio, .w = 16, .h = 9 }, 1366, 768));
    // Про экран ничего не известно — не мешаем.
    try testing.expect(fits(uhd, 0, 0));
}

test "размеры от экрана считаются по стороне" {
    var got: [3]Choice = undefined;
    const n = screenSizes(1920, 1080, &got);
    try testing.expectEqual(@as(usize, 3), n);
    try testing.expectEqual(@as(u32, 1920), got[0].w);
    try testing.expectEqual(@as(u32, 960), got[1].w);
    try testing.expectEqual(@as(u32, 540), got[1].h);
    try testing.expectEqual(@as(u32, 480), got[2].w);
    // Все стороны чётные: этого требует кодировщик.
    for (got[0..n]) |item| {
        try testing.expectEqual(@as(u32, 0), item.w % 2);
        try testing.expectEqual(@as(u32, 0), item.h % 2);
    }
}

test "мелкие доли в список не попадают" {
    var got: [3]Choice = undefined;
    // На маленьком экране четверть — это меньше трёхсот точек: не нужна.
    const n = screenSizes(1024, 768, &got);
    try testing.expectEqual(@as(usize, 2), n);
    try testing.expectEqual(@as(u32, 1024), got[0].w);
    try testing.expectEqual(@as(u32, 512), got[1].w);

    // Экран неизвестен — списка нет вовсе, а не список из нулей.
    try testing.expectEqual(@as(usize, 0), screenSizes(0, 0, &got));
}

test "нечётный экран даёт чётные стороны" {
    var got: [3]Choice = undefined;
    _ = screenSizes(1365, 767, &got);
    try testing.expectEqual(@as(u32, 1364), got[0].w);
    try testing.expectEqual(@as(u32, 766), got[0].h);
}

test "подписи — то, что человек увидит в меню" {
    var buf: [32]u8 = undefined;
    try testing.expectEqualStrings("1920×1080", (Choice{ .mode = .fixed, .w = 1920, .h = 1080 }).label(&buf));
    try testing.expectEqualStrings("16:9", (Choice{ .mode = .ratio, .w = 16, .h = 9 }).label(&buf));
    try testing.expectEqualStrings("свободно", (Choice{}).label(&buf));
}

test "умолчание — свободно, все поля нулевые" {
    const zero = Choice{};
    try testing.expectEqual(Mode.free, zero.mode);
    try testing.expectEqual(@as(u32, 0), zero.w);
    try testing.expectEqual(@as(u32, 0), zero.h);
    try testing.expect(zero.same(.{}));
    try testing.expect(!zero.same(.{ .mode = .ratio, .w = 16, .h = 9 }));
}
