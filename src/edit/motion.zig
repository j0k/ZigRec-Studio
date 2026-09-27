//! Волна движения по видеодорожке (#134): насколько каждый кадр отличается
//! от предыдущего.
//!
//! У звука в редакторе есть волна, и по ней сразу видно, где тишина, а где
//! хлопок. У картинки не было ничего: дёрганый кадр среди ровной езды глазом
//! не найти — его ищут, перематывая по кадру, и находят не всегда. Волна
//! движения делает ровно то же, что звуковая: столбик на кадр, только вместо
//! громкости — величина сдвига картинки.
//!
//! **Мера — средняя разность яркости** между соседними кадрами, приведённая
//! к единице. Не оптический поток: тот считает, куда сместилась картинка, и
//! стоит в сотни раз дороже, а для «кадр стоит или едет» разности хватает.
//! Проверено на дублях ролика СИТА: именно так нашлись стоящие кадры на
//! буксировке.
//!
//! **Что считается браком.** Стоящий кадр (разность около нуля) среди
//! движущихся и скачок больше чем вдвое против соседей — на них ставится
//! красная засечка, как на ключевых кадрах. Оба правила живут здесь и
//! проверены тестами: рисование только читает готовое.
const std = @import("std");

pub const Error = error{
    OutOfMemory,
    /// Кадр без точек или с обрывом строки.
    BadFrame,
};

/// Насколько кадр считается «стоящим»: разность ниже этой доли от среднего
/// по соседям — значит картинка не изменилась вовсе.
pub const still_share: f32 = 0.15;

/// Во сколько раз скачок должен превысить соседей, чтобы считаться рывком.
pub const jump_times: f32 = 2.0;

/// Сколько соседей с каждой стороны берём для сравнения.
pub const neighbours: usize = 4;

/// Готовая волна: по столбику на кадр.
pub const Wave = struct {
    /// Разность каждого кадра с предыдущим, 0..1. Первый кадр — ноль:
    /// сравнивать его не с чем.
    step: []f32 = &.{},
    /// Сколько наносекунд на столбик (длительность кадра источника).
    frame_ns: u64 = 0,
    /// Обычное движение этой записи — медиана столбиков.
    ///
    /// Мерило именно такое, а не «средний сдвиг соседей»: стоящий кадр редко
    /// бывает один. На буксировке камера замирала на десяток кадров подряд, и
    /// у кадров в середине такой остановки все соседи тоже стоят — по соседям
    /// выходило, что «всё нормально», и засечки ставились только по краям.
    /// Медиана знает, как эта запись двигается вообще, и потому находит
    /// остановку целиком.
    usual: f32 = 0,

    pub fn deinit(self: *Wave, allocator: std.mem.Allocator) void {
        if (self.step.len > 0) allocator.free(self.step);
        self.* = .{};
    }

    pub fn empty(self: *const Wave) bool {
        return self.step.len == 0;
    }

    /// Значение в этот момент времени. Вне волны — ноль.
    pub fn at(self: *const Wave, when_ns: u64) f32 {
        if (self.step.len == 0 or self.frame_ns == 0) return 0;
        const index = when_ns / self.frame_ns;
        if (index >= self.step.len) return 0;
        return self.step[@intCast(index)];
    }

    /// Средняя разность по соседям кадра (сам кадр не считается).
    pub fn around(self: *const Wave, index: usize) f32 {
        if (self.step.len == 0) return 0;
        const from = index -| neighbours;
        const to = @min(index + neighbours + 1, self.step.len);
        var sum: f32 = 0;
        var n: usize = 0;
        var i = from;
        while (i < to) : (i += 1) {
            if (i == index) continue;
            sum += self.step[i];
            n += 1;
        }
        return if (n == 0) 0 else sum / @as(f32, @floatFromInt(n));
    }

    /// Стоящий кадр там, где запись вообще-то двигается: вот он, рывок.
    ///
    /// Условие «запись двигается» обязательно: на неподвижном слайде стоят
    /// все кадры, и засечка на каждом не сказала бы ничего.
    pub fn isStill(self: *const Wave, index: usize) bool {
        if (index == 0 or index >= self.step.len) return false;
        if (self.usual < 0.01) return false;
        return self.step[index] < self.usual * still_share;
    }

    /// Скачок: кадр сдвинулся заметно сильнее, чем эта запись обычно.
    pub fn isJump(self: *const Wave, index: usize) bool {
        if (index == 0 or index >= self.step.len) return false;
        if (self.usual < 0.01) return false;
        return self.step[index] > self.usual * jump_times;
    }

    /// Сколько засечек наберётся — для строки состояния и для стенда.
    pub fn marks(self: *const Wave) struct { still: usize, jumps: usize } {
        var still: usize = 0;
        var jumps: usize = 0;
        var i: usize = 1;
        while (i < self.step.len) : (i += 1) {
            if (self.isStill(i)) still += 1;
            if (self.isJump(i)) jumps += 1;
        }
        return .{ .still = still, .jumps = jumps };
    }
};

/// Копилка: кадры кладут по одному, на выходе — волна.
pub const Builder = struct {
    allocator: std.mem.Allocator,
    step: std.ArrayList(f32) = .empty,
    /// Яркость предыдущего кадра, чтобы сравнивать с новым.
    prev: []u8 = &.{},
    frame_ns: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, frame_ns: u64) Builder {
        return .{ .allocator = allocator, .frame_ns = frame_ns };
    }

    pub fn deinit(self: *Builder) void {
        self.step.deinit(self.allocator);
        if (self.prev.len > 0) self.allocator.free(self.prev);
        self.* = undefined;
    }

    /// Добавить кадр: BGRA, `stride` байт на строку.
    pub fn add(self: *Builder, pixels: []const u8, stride: usize, width: u32, height: u32) Error!void {
        if (width == 0 or height == 0) return Error.BadFrame;
        const need = @as(usize, width) * height;
        if (self.prev.len != need) {
            if (self.prev.len > 0) self.allocator.free(self.prev);
            self.prev = self.allocator.alloc(u8, need) catch return Error.OutOfMemory;
            @memset(self.prev, 0);
            // Первый кадр сравнивать не с чем: ставим ноль и запоминаем его.
            try self.step.append(self.allocator, 0);
            grabLuma(self.prev, pixels, stride, width, height);
            return;
        }

        var sum: u64 = 0;
        var row: u32 = 0;
        while (row < height) : (row += 1) {
            const line = pixels[row * stride ..];
            const prev_line = self.prev[@as(usize, row) * width ..];
            var x: u32 = 0;
            while (x < width) : (x += 1) {
                const at = x * 4;
                if (at + 2 >= line.len) break;
                const now = luma(line[at], line[at + 1], line[at + 2]);
                const was = prev_line[x];
                sum += @abs(@as(i32, now) - @as(i32, was));
                prev_line[x] = now;
            }
        }
        const value = @as(f32, @floatFromInt(sum)) / @as(f32, @floatFromInt(need)) / 255.0;
        try self.step.append(self.allocator, value);
    }

    pub fn finish(self: *Builder) Wave {
        const made = self.step.toOwnedSlice(self.allocator) catch @as([]f32, &.{});
        return .{ .step = made, .frame_ns = self.frame_ns, .usual = medianOf(self.allocator, made) };
    }
};

/// Медиана столбиков (первый не считается: он всегда ноль).
///
/// Не среднее: одна долгая остановка или один всплеск сдвигают среднее так,
/// что мерило начинает врать. Не хватило памяти на копию — возвращаем ноль,
/// и тогда засечек просто не будет: лучше без них, чем наугад.
pub fn medianOf(allocator: std.mem.Allocator, step: []const f32) f32 {
    if (step.len < 2) return 0;
    const copy = allocator.dupe(f32, step[1..]) catch return 0;
    defer allocator.free(copy);
    std.mem.sort(f32, copy, {}, std.sort.asc(f32));
    return copy[copy.len / 2];
}

fn luma(b: u8, g: u8, r: u8) u8 {
    const value = (@as(u32, r) * 77 + @as(u32, g) * 150 + @as(u32, b) * 29) >> 8;
    return @intCast(@min(value, 255));
}

fn grabLuma(out: []u8, pixels: []const u8, stride: usize, width: u32, height: u32) void {
    var row: u32 = 0;
    while (row < height) : (row += 1) {
        const line = pixels[row * stride ..];
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            const at = x * 4;
            if (at + 2 >= line.len) break;
            out[@as(usize, row) * width + x] = luma(line[at], line[at + 1], line[at + 2]);
        }
    }
}

/// Посчитать волну по видеофайлу (#134).
///
/// Кадры читаются подряд и в уменьшенном виде: для «стоит или едет» хватает
/// картинки шириной в несколько сотен точек, а полноразмерная стоила бы
/// в двадцать раз дороже. `max_frames` — предел на всякий случай (ноль —
/// без предела): волна считается в стороне от окна, но и там не место
/// бесконечности.
pub fn compute(allocator: std.mem.Allocator, path: []const u8, max_frames: usize) !Wave {
    const player = @import("../file/player.zig");
    var p = try player.Player.openScaled(allocator, path, small_width, small_height);
    defer p.close();

    // Длительность кадра плеер не хранит: считаем её по числу кадров, когда
    // волна готова, а пока берём тридцать в секунду — обычный скринкаст.
    const frame_ns: u64 = std.time.ns_per_s / 30;
    var b = Builder.init(allocator, frame_ns);
    defer b.deinit();

    // Первый кадр уже раскодирован открытием.
    if (p.width > 0 and p.height > 0) try b.add(p.pixels, p.stride, p.width, p.height);
    var seen: usize = 1;
    while (max_frames == 0 or seen < max_frames) {
        const got = p.nextFrame() catch break;
        if (!got) break;
        try b.add(p.pixels, p.stride, p.width, p.height);
        seen += 1;
    }
    var made = b.finish();
    // Теперь кадров известно точно: шаг столбика — длительность файла на них.
    if (p.duration_ns > 0 and made.step.len > 1) {
        made.frame_ns = p.duration_ns / made.step.len;
    }
    return made;
}

/// Размер, до которого уменьшаем кадр для подсчёта.
pub const small_width: u32 = 480;
pub const small_height: u32 = 270;

// ---------------------------------------------------------------- тесты

const testing = std.testing;

/// Кадр одного цвета — для тестов: движение задаём разницей яркости.
fn flatFrame(buf: []u8, value: u8) void {
    var i: usize = 0;
    while (i + 3 < buf.len) : (i += 4) {
        buf[i] = value;
        buf[i + 1] = value;
        buf[i + 2] = value;
        buf[i + 3] = 255;
    }
}

test "ровная езда — ровная волна, стоящий кадр — провал до нуля" {
    const w: u32 = 8;
    const h: u32 = 4;
    var frame: [8 * 4 * 4]u8 = undefined;
    var b = Builder.init(testing.allocator, 33 * std.time.ns_per_ms);
    defer b.deinit();

    // Десять кадров, каждый на двадцать светлее — ровное движение.
    var i: u32 = 0;
    var value: u8 = 0;
    while (i < 10) : (i += 1) {
        flatFrame(&frame, value);
        try b.add(&frame, w * 4, w, h);
        value +%= 20;
    }
    // Одиннадцатый — такой же, как десятый: кадр стоит.
    try b.add(&frame, w * 4, w, h);
    // И снова движение.
    i = 0;
    while (i < 6) : (i += 1) {
        value +%= 20;
        flatFrame(&frame, value);
        try b.add(&frame, w * 4, w, h);
    }

    var wave = b.finish();
    defer wave.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 17), wave.step.len);
    // Первый столбик — ноль: сравнивать не с чем.
    try testing.expectEqual(@as(f32, 0), wave.step[0]);
    // Ровное движение: около двадцати из двухсот пятидесяти пяти.
    try testing.expect(wave.step[5] > 0.05 and wave.step[5] < 0.12);
    // Стоящий кадр — ровно ноль и засечка на нём.
    try testing.expectEqual(@as(f32, 0), wave.step[10]);
    try testing.expect(wave.isStill(10));
    // Двигавшиеся кадры стоящими не считаются.
    try testing.expect(!wave.isStill(9));
    try testing.expect(!wave.isStill(11));
    const counted = wave.marks();
    try testing.expectEqual(@as(usize, 1), counted.still);
    // Мерило — обычное движение записи, а оно тут около двадцати из 255.
    try testing.expect(wave.usual > 0.05 and wave.usual < 0.12);
}

test "скачок вдвое против соседей — засечка" {
    const w: u32 = 8;
    const h: u32 = 4;
    var frame: [8 * 4 * 4]u8 = undefined;
    var b = Builder.init(testing.allocator, 33 * std.time.ns_per_ms);
    defer b.deinit();

    var value: u8 = 0;
    var i: u32 = 0;
    while (i < 12) : (i += 1) {
        // На седьмом кадре — рывок: разом на сто вместо десяти.
        value +%= if (i == 7) 100 else 10;
        flatFrame(&frame, value);
        try b.add(&frame, w * 4, w, h);
    }
    var wave = b.finish();
    defer wave.deinit(testing.allocator);

    try testing.expect(wave.isJump(7));
    try testing.expect(!wave.isJump(6));
    try testing.expect(!wave.isJump(8));
    try testing.expectEqual(@as(usize, 1), wave.marks().jumps);
}

test "неподвижная запись: засечек нет — стоят все, и это не рывок" {
    const w: u32 = 8;
    const h: u32 = 4;
    var frame: [8 * 4 * 4]u8 = undefined;
    flatFrame(&frame, 128);
    var b = Builder.init(testing.allocator, 33 * std.time.ns_per_ms);
    defer b.deinit();
    var i: u32 = 0;
    while (i < 20) : (i += 1) try b.add(&frame, w * 4, w, h);

    var wave = b.finish();
    defer wave.deinit(testing.allocator);
    const counted = wave.marks();
    try testing.expectEqual(@as(usize, 0), counted.still);
    try testing.expectEqual(@as(usize, 0), counted.jumps);
}

test "волна отвечает по времени, а за концом — ноль" {
    var wave = Wave{
        .step = try testing.allocator.dupe(f32, &[_]f32{ 0, 0.5, 0.25 }),
        .frame_ns = 100 * std.time.ns_per_ms,
    };
    defer wave.deinit(testing.allocator);
    try testing.expectEqual(@as(f32, 0), wave.at(0));
    try testing.expectEqual(@as(f32, 0.5), wave.at(150 * std.time.ns_per_ms));
    try testing.expectEqual(@as(f32, 0.25), wave.at(250 * std.time.ns_per_ms));
    try testing.expectEqual(@as(f32, 0), wave.at(10 * std.time.ns_per_s));
}

test "пустая волна ничего не обещает" {
    var wave = Wave{};
    try testing.expect(wave.empty());
    try testing.expectEqual(@as(f32, 0), wave.at(1000));
    try testing.expect(!wave.isStill(1));
    try testing.expect(!wave.isJump(1));
    const counted = wave.marks();
    try testing.expectEqual(@as(usize, 0), counted.still);
    wave.deinit(testing.allocator);
}

test "кадр без точек — не кадр" {
    var b = Builder.init(testing.allocator, 1);
    defer b.deinit();
    var frame: [16]u8 = @splat(0);
    try testing.expectError(Error.BadFrame, b.add(&frame, 4, 0, 4));
    try testing.expectError(Error.BadFrame, b.add(&frame, 4, 4, 0));
}

test "длинная остановка находится целиком, а не только по краям" {
    const w: u32 = 8;
    const h: u32 = 4;
    var frame: [8 * 4 * 4]u8 = undefined;
    var b = Builder.init(testing.allocator, 33 * std.time.ns_per_ms);
    defer b.deinit();

    var value: u8 = 0;
    var i: u32 = 0;
    // Двадцать кадров движения.
    while (i < 20) : (i += 1) {
        value +%= 20;
        flatFrame(&frame, value);
        try b.add(&frame, w * 4, w, h);
    }
    // Десять одинаковых: камера замерла — ровно тот случай с буксировки.
    i = 0;
    while (i < 10) : (i += 1) try b.add(&frame, w * 4, w, h);
    // И снова движение.
    i = 0;
    while (i < 20) : (i += 1) {
        value +%= 20;
        flatFrame(&frame, value);
        try b.add(&frame, w * 4, w, h);
    }

    var wave = b.finish();
    defer wave.deinit(testing.allocator);
    const counted = wave.marks();
    // Все десять стоящих кадров, а не два края.
    try testing.expectEqual(@as(usize, 10), counted.still);
    var k: usize = 20;
    while (k < 30) : (k += 1) try testing.expect(wave.isStill(k));
    try testing.expect(!wave.isStill(19));
    try testing.expect(!wave.isStill(30));
}

test "медиана не ведётся на один всплеск" {
    const step = [_]f32{ 0, 0.1, 0.1, 0.1, 0.1, 9.0, 0.1, 0.1 };
    const usual = medianOf(testing.allocator, &step);
    try testing.expectApproxEqAbs(@as(f32, 0.1), usual, 0.001);
    // Меньше двух столбиков — мерила нет.
    try testing.expectEqual(@as(f32, 0), medianOf(testing.allocator, &[_]f32{0}));
    try testing.expectEqual(@as(f32, 0), medianOf(testing.allocator, &.{}));
}
