//! Темп записи: сколько кадров в секунду брать из захвата (#104).
//!
//! Захват отдаёт кадры так часто, как меняется экран: на шестидесятигерцевом
//! столе это шестьдесят кадров в секунду, даже когда попросили тридцать.
//! Лишние кадры стоят дорого дважды — копией из видеопамяти и кодированием, —
//! а в файле от них ничего не прибавляется: частота там всё равно заказанная.
//!
//! Правило простое: кадр, пришедший раньше своего слота, не берём. Но
//! «догонять» пропущенное нельзя: после паузы или простоя расписание сдвигается
//! на текущий момент, иначе накопившийся долг вылился бы пачкой кадров подряд.
const std = @import("std");

pub const Pacer = struct {
    /// Сколько наносекунд между кадрами. Ноль — не ограничивать.
    step_ns: u64 = 0,
    /// Когда откроется следующий слот.
    next_ns: u64 = 0,
    /// Сколько кадров отброшено как лишние.
    skipped: u64 = 0,

    pub fn forFps(fps: u32) Pacer {
        if (fps == 0) return .{};
        return .{ .step_ns = std.time.ns_per_s / fps };
    }

    /// Брать ли кадр со временем `at_ns`.
    ///
    /// Первый кадр берём всегда: с него и начинается расписание.
    pub fn accept(self: *Pacer, at_ns: u64) bool {
        if (self.step_ns == 0) return true;
        if (self.next_ns == 0) {
            self.next_ns = at_ns + self.step_ns;
            return true;
        }
        // Допуск — четверть шага. Без него выходил перекос: кадры идут через
        // двадцать миллисекунд, слот — через тридцать три, и «строго не раньше
        // слота» давало двадцать пять кадров в секунду вместо тридцати
        // (каждый второй кадр приходил на двенадцать миллисекунд раньше срока).
        if (at_ns + self.step_ns / 4 < self.next_ns) {
            self.skipped += 1;
            return false;
        }
        // Отстали больше, чем на слот (простой, пауза, машина не успевала) —
        // считаем от текущего кадра, а не от просроченного расписания.
        if (at_ns > self.next_ns + self.step_ns) {
            self.next_ns = at_ns + self.step_ns;
        } else {
            self.next_ns += self.step_ns;
        }
        return true;
    }

    /// Начать расписание заново — после паузы записи.
    pub fn restart(self: *Pacer) void {
        self.next_ns = 0;
    }
};

// ---------------------------------------------------------------- тесты

const testing = std.testing;
const ms = std.time.ns_per_ms;

test "тридцать из шестидесяти: берём каждый второй" {
    var p = Pacer.forFps(30);
    var at: u64 = 1_000_000_000;
    var taken: u32 = 0;
    var i: u32 = 0;
    // Секунда кадров по шестидесятигерцевому столу.
    while (i < 60) : (i += 1) {
        if (p.accept(at)) taken += 1;
        at += std.time.ns_per_s / 60;
    }
    // Около половины: точное число зависит от того, что 1/60 и 1/30 в
    // наносекундах делятся с остатком, и слот иногда приходится на кадр
    // на наносекунду раньше. Проверяем свойство, а не арифметику округления.
    try testing.expect(taken >= 28 and taken <= 32);
    try testing.expectEqual(@as(u64, 60), taken + p.skipped);
}

test "ноль означает «не ограничивать»" {
    var p = Pacer.forFps(0);
    var at: u64 = 0;
    var taken: u32 = 0;
    while (at < 100 * ms) : (at += ms) {
        if (p.accept(at)) taken += 1;
    }
    try testing.expectEqual(@as(u32, 100), taken);
    try testing.expectEqual(@as(u64, 0), p.skipped);
}

test "после простоя расписание не мстит пачкой кадров" {
    var p = Pacer.forFps(30);
    try testing.expect(p.accept(0));
    // Экран стоял две секунды: долг в шестьдесят кадров накопиться не должен.
    const after_gap: u64 = 2 * std.time.ns_per_s;
    try testing.expect(p.accept(after_gap));
    // Следующий кадр через миллисекунду — лишний, как и положено.
    try testing.expect(!p.accept(after_gap + ms));
    // А через слот — берём.
    try testing.expect(p.accept(after_gap + std.time.ns_per_s / 30));
}

test "кадр в слот берётся, заметно раньше — нет" {
    var p = Pacer.forFps(25);
    const step = std.time.ns_per_s / 25;
    try testing.expect(p.accept(0));
    // Полшага раньше — рано.
    try testing.expect(!p.accept(step / 2));
    // Четверть шага раньше — уже наш: иначе выходит перекос по частоте.
    try testing.expect(p.accept(step - step / 4));
    // Сразу следом — рано.
    try testing.expect(!p.accept(step));
    // Расписание считается от слота, а не от пришедшего кадра.
    try testing.expect(p.accept(2 * step));
}

test "источник чаще слота: частота выходит заказанная, а не с перекосом" {
    // Пятьдесят кадров в секунду от источника, просим тридцать.
    var p = Pacer.forFps(30);
    var at: u64 = 0;
    var taken: u32 = 0;
    const source_step = std.time.ns_per_s / 50;
    var i: u32 = 0;
    while (i < 100) : (i += 1) { // две секунды
        if (p.accept(at)) taken += 1;
        at += source_step;
    }
    // Тридцать в секунду, то есть шестьдесят за две — с допуском на округление.
    try testing.expect(taken >= 56 and taken <= 62);
}

test "после паузы расписание начинается заново" {
    var p = Pacer.forFps(30);
    try testing.expect(p.accept(0));
    try testing.expect(!p.accept(ms));
    p.restart();
    // Пауза кончилась: первый кадр после неё берём, каким бы близким он ни был.
    try testing.expect(p.accept(2 * ms));
}

test "шестьдесят из шестидесяти: ничего не лишнее" {
    var p = Pacer.forFps(60);
    var at: u64 = 0;
    var taken: u32 = 0;
    var i: u32 = 0;
    while (i < 60) : (i += 1) {
        if (p.accept(at)) taken += 1;
        at += std.time.ns_per_s / 60;
    }
    try testing.expectEqual(@as(u32, 60), taken);
    try testing.expectEqual(@as(u64, 0), p.skipped);
}
