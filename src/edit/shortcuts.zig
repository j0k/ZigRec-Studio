//! Сочетания клавиш редактора: один список на окно и на проверку.
//!
//! Список живёт здесь, а не в тексте окна, по двум причинам. Первая: его
//! видно тестам — и «все подписи переведены», и «клавиши не повторяются»
//! проверяются без окна. Вторая: сам список и то, что он описывает, должны
//! быть в одном месте, иначе через месяц клавишу переназначат, а справка
//! останется врать.
//!
//! Клавиши пишем значками (`Ctrl+Z`, `[`, `←`), а подписи — по-русски:
//! русская строка служит ключом перевода, ровно как везде в проекте.
const std = @import("std");
const lang = @import("../lang.zig");

/// Что нажать и что из этого выйдет.
pub const Item = struct { keys: []const u8, what: []const u8 };

/// Кучка сочетаний под общим заголовком.
pub const Group = struct { title: []const u8, items: []const Item };

/// Левый столбец окна: правка и ход по времени.
pub const left = [_]Group{
    .{ .title = "Правка", .items = &[_]Item{
        .{ .keys = "Ctrl+Z", .what = "отменить" },
        .{ .keys = "Ctrl+Y", .what = "вернуть отменённое" },
        .{ .keys = "Ctrl+O", .what = "открыть файл" },
        .{ .keys = "Ctrl+S", .what = "сохранить проект" },
        .{ .keys = "Ctrl+Shift+S", .what = "сохранить как..." },
        .{ .keys = "S", .what = "разрезать клип на указателе" },
        .{ .keys = "Delete", .what = "удалить выбранное" },
        .{ .keys = "F2", .what = "переименовать метку или дорожку" },
    } },
    .{ .title = "Ход по времени", .items = &[_]Item{
        .{ .keys = "Space", .what = "играть или пауза" },
        .{ .keys = "Home", .what = "в начало проекта" },
        .{ .keys = "← / →", .what = "кадр назад и вперёд" },
        .{ .keys = "Ctrl+← / →", .what = "секунду назад и вперёд" },
        .{ .keys = "PageUp / PageDown", .what = "страница вида назад и вперёд" },
        .{ .keys = "K", .what = "следующий ключевой кадр" },
        .{ .keys = "Shift+K", .what = "предыдущий ключевой кадр" },
    } },
};

/// Правый столбец окна: метки, границы экспорта, окна.
pub const right = [_]Group{
    .{ .title = "Метки", .items = &[_]Item{
        .{ .keys = "M", .what = "поставить метку на указателе" },
        .{ .keys = "Ctrl+M", .what = "окно меток" },
        .{ .keys = "Ctrl+[", .what = "к предыдущей метке" },
        .{ .keys = "Ctrl+]", .what = "к следующей метке" },
    } },
    .{ .title = "Границы экспорта", .items = &[_]Item{
        .{ .keys = "[", .what = "начало куска на указателе" },
        .{ .keys = "]", .what = "конец куска на указателе" },
        .{ .keys = "Ctrl+E", .what = "экспорт в mp4..." },
        .{ .keys = "Ctrl+Shift+E", .what = "снять границы: весь проект" },
        .{ .keys = "F12", .what = "снимок кадра" },
    } },
    .{ .title = "Окна", .items = &[_]Item{
        .{ .keys = "Ctrl+D", .what = "окно дублей" },
    } },
};

/// Сколько строк занимает столбец: по строке на заголовок и по строке
/// на сочетание. Нужна окну, чтобы заказать себе высоту, и тесту, чтобы
/// проверить, что столбцы примерно одной длины.
pub fn rowsOf(groups: []const Group) usize {
    var n: usize = 0;
    for (groups) |g| n += 1 + g.items.len;
    return n;
}

/// Все сочетания обоих столбцов одним списком. Нужен проверкам и замеру
/// ширины столбца; собирается на этапе компиляции, поэтому и размер, и
/// содержимое тут же сверяются с `left` и `right` — разойтись не могут.
pub const items = blk: {
    var total: usize = 0;
    for (left) |g| total += g.items.len;
    for (right) |g| total += g.items.len;
    var list: [total]Item = undefined;
    var n: usize = 0;
    for (left) |g| for (g.items) |it| {
        list[n] = it;
        n += 1;
    };
    for (right) |g| for (g.items) |it| {
        list[n] = it;
        n += 1;
    };
    break :blk list;
};

test "все сочетания и заголовки переведены" {
    for (left) |g| {
        try std.testing.expect(lang.known(g.title));
        for (g.items) |it| try std.testing.expect(lang.known(it.what));
    }
    for (right) |g| {
        try std.testing.expect(lang.known(g.title));
        for (g.items) |it| try std.testing.expect(lang.known(it.what));
    }
}

test "клавиши не повторяются и не пустуют" {
    for (items, 0..) |a, i| {
        try std.testing.expect(a.keys.len > 0);
        try std.testing.expect(a.what.len > 0);
        for (items[i + 1 ..]) |b| {
            try std.testing.expect(!std.mem.eql(u8, a.keys, b.keys));
        }
    }
}

test "столбцы идут в окно и примерно одной длины" {
    const rows = @max(rowsOf(&left), rowsOf(&right));
    // Не больше восемнадцати строк в столбце: выше окно уже не влезает
    // на ноутбучный экран, а справка, которую надо прокручивать, бесполезна.
    try std.testing.expect(rows <= 18);
    try std.testing.expect(left.len > 0 and right.len > 0);
}
