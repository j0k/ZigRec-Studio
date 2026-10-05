//! Шумоподавление: убрать фон, не тронув то, ради чего записывали.
//!
//! Просьба владельца (30.09.2026, эпик #167): «убрать шумы».
//!
//! **Что здесь делается и чего не делается.** Это ворота: всё, что тише
//! порога, приглушается, всё, что громче, проходит нетронутым. Так уходит
//! гул вентилятора и шипение в паузах — то, что слышно на готовом ролике
//! больше, чем на записи.
//!
//! Под голосом шум остаётся: ворота не умеют вычитать одно из другого,
//! они умеют только «тише здесь». Настоящее подавление вычитает спектр
//! шума из спектра сигнала, и это отдельная работа (#172) — она требует
//! быстрого спектрального разбора, которого у нас пока нет.
//!
//! **Порог берётся от самого шума, а не назначается.** Человек не знает,
//! сколько децибел у него шипит; он знает, что «шипит». Поэтому уровень
//! фона считается по записи, а человек задаёт только силу.
//!
//! **Ворота открываются и закрываются плавно.** Резкое переключение даёт
//! щелчок на каждом слове — он слышен отчётливее того шума, ради которого
//! всё затевалось.
const std = @import("std");

/// Сила подавления. Ноль — «не трогать»: правило нулевых умолчаний, и
/// заодно это означает выключенный эффект.
pub const Strength = enum(u8) {
    off = 0,
    /// Мягко: фон приглушается, но не пропадает — голос не «дышит».
    soft,
    /// Средне: обычный выбор для комнаты с вентилятором.
    normal,
    /// Сильно: фон уходит почти совсем, вместе с тихими хвостами слов.
    hard,

    /// Во сколько раз порог выше оценённого фона.
    ///
    /// Шум не ровный: он гуляет в пределах нескольких децибел, и порог
    /// вровень с оценкой резал бы то шум, то не шум — те самые «дышащие»
    /// ворота.
    pub fn overFloor(self: Strength) f32 {
        return switch (self) {
            .off => 0,
            .soft => 1.6,
            .normal => 2.5,
            .hard => 4.0,
        };
    }

    /// Насколько приглушаем то, что ниже порога.
    ///
    /// В ноль не глушим никогда: полная тишина между словами слышна как
    /// провал, будто запись оборвалась. Немного фона — это естественно.
    pub fn floorGain(self: Strength) f32 {
        return switch (self) {
            .off => 1,
            .soft => 0.45,
            .normal => 0.22,
            .hard => 0.08,
        };
    }

    pub fn label(self: Strength) []const u8 {
        return switch (self) {
            .off => "выключено",
            .soft => "мягко",
            .normal => "обычно",
            .hard => "сильно",
        };
    }
};

/// Оценка уровня фона.
///
/// Берём не среднее и не пик, а «типично тихое»: сортировать всё дорого,
/// поэтому считаем долю отсчётов ниже пробного уровня и подбираем уровень
/// так, чтобы под ним оказалась пятая часть записи. Пятая — потому что
/// пауз в речи обычно не меньше, а если говорят совсем без пауз, оценка
/// окажется завышенной, и ворота честно не сработают (лучше не тронуть,
/// чем срезать слова).
pub fn floorOf(samples: []const f32) f32 {
    if (samples.len == 0) return 0;
    var peak: f32 = 0;
    for (samples) |v| {
        const a = @abs(v);
        if (a > peak) peak = a;
    }
    if (peak <= 0) return 0;

    // Двоичный поиск по уровню: двадцать шагов дают точность в миллионную
    // долю от пика — больше, чем нужно кому-либо.
    var low: f32 = 0;
    var high: f32 = peak;
    var step: usize = 0;
    while (step < 20) : (step += 1) {
        const mid = (low + high) / 2;
        var below: usize = 0;
        for (samples) |v| {
            if (@abs(v) <= mid) below += 1;
        }
        const part = @as(f32, @floatFromInt(below)) / @as(f32, @floatFromInt(samples.len));
        if (part < 0.2) low = mid else high = mid;
    }
    return (low + high) / 2;
}

/// Настройка ворот: что считать шумом и как быстро открываться.
pub const Gate = struct {
    strength: Strength = .off,
    /// Уровень фона. Ноль — «посчитать по самой записи».
    floor: f32 = 0,
    /// За сколько миллисекунд ворота открываются и закрываются.
    ///
    /// Открываются быстро, закрываются медленно: быстрое открытие не
    /// съедает начало слова, медленное закрытие не рубит его хвост.
    attack_ms: f32 = 5,
    release_ms: f32 = 120,
};

/// Пропустить отсчёты через ворота.
///
/// `out` может совпадать с `samples`: обработка идёт слева направо и
/// прошлое не перечитывается.
pub fn apply(samples: []const f32, out: []f32, rate: u32, gate: Gate) void {
    const n = @min(samples.len, out.len);
    if (n == 0) return;
    if (gate.strength == .off or rate == 0) {
        if (out.ptr != samples.ptr) @memcpy(out[0..n], samples[0..n]);
        return;
    }

    const floor = if (gate.floor > 0) gate.floor else floorOf(samples[0..n]);
    const open_at = floor * gate.strength.overFloor();
    const quiet_gain = gate.strength.floorGain();

    // Совсем тихая запись: порог около нуля, и ворота нечему открывать.
    // Трогать такое незачем — отдаём как есть.
    if (open_at <= 0) {
        if (out.ptr != samples.ptr) @memcpy(out[0..n], samples[0..n]);
        return;
    }

    const rate_f: f32 = @floatFromInt(rate);
    const attack = perStep(gate.attack_ms, rate_f);
    const release = perStep(gate.release_ms, rate_f);

    // Следим за огибающей, а не за отдельным отсчётом: колебание проходит
    // через ноль дважды за период, и ворота по отсчёту закрывались бы
    // внутри каждого слова.
    var envelope: f32 = 0;
    var gain: f32 = quiet_gain;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const level = @abs(samples[i]);
        envelope = if (level > envelope)
            level
        else
            envelope + (level - envelope) * release;

        const want: f32 = if (envelope >= open_at) 1 else quiet_gain;
        const speed = if (want > gain) attack else release;
        gain += (want - gain) * speed;
        out[i] = samples[i] * gain;
    }
}

/// Доля пути за один отсчёт: за `ms` миллисекунд проходим почти весь путь.
fn perStep(ms: f32, rate: f32) f32 {
    if (ms <= 0) return 1;
    const steps = ms * rate / 1000.0;
    if (steps <= 1) return 1;
    // Четыре постоянные времени — это 98 % пути: на слух уже «дошло».
    return std.math.clamp(4.0 / steps, 0.0001, 1);
}

// ---------------------------------------------------------------- тесты

const testing = std.testing;
const test_rate: u32 = 48_000;

fn fillSine(buf: []f32, hz: f32, amplitude: f32) void {
    for (buf, 0..) |*v, i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(test_rate));
        v.* = amplitude * @sin(2.0 * std.math.pi * hz * t);
    }
}

fn fillNoise(buf: []f32, amplitude: f32, seed: u64) void {
    var rnd = std.Random.DefaultPrng.init(seed);
    const r = rnd.random();
    for (buf) |*v| v.* = (r.float(f32) * 2 - 1) * amplitude;
}

fn peakOf(buf: []const f32) f32 {
    var peak: f32 = 0;
    for (buf) |v| {
        const a = @abs(v);
        if (a > peak) peak = a;
    }
    return peak;
}

test "выключенные ворота ничего не меняют" {
    var buf: [1000]f32 = undefined;
    fillSine(&buf, 440, 0.5);
    var out: [1000]f32 = undefined;
    apply(&buf, &out, test_rate, .{});
    for (buf, out) |a, b| try testing.expectEqual(a, b);
}

test "тихий фон глохнет, громкий звук проходит" {
    // Полсекунды: первая четверть — шипение, дальше голос погромче.
    var buf: [24000]f32 = undefined;
    fillNoise(buf[0..6000], 0.02, 7);
    fillSine(buf[6000..], 440, 0.5);
    // К голосу подмешан тот же фон: так и бывает в комнате.
    var hiss: [18000]f32 = undefined;
    fillNoise(&hiss, 0.02, 9);
    for (buf[6000..], hiss[0..]) |*v, h| v.* += h;

    var out: [24000]f32 = undefined;
    apply(&buf, &out, test_rate, .{ .strength = .normal });

    // Фон в начале стал заметно тише.
    const hiss_before = peakOf(buf[0..5000]);
    const hiss_after = peakOf(out[0..5000]);
    try testing.expect(hiss_after < hiss_before * 0.5);

    // А голос остался собой: середину слова ворота не трогают.
    const voice_before = peakOf(buf[12000..18000]);
    const voice_after = peakOf(out[12000..18000]);
    try testing.expect(voice_after > voice_before * 0.95);
}

test "тишина остаётся тишиной, а не становится шумом" {
    const quiet: [4000]f32 = @splat(0);
    var out: [4000]f32 = undefined;
    apply(&quiet, &out, test_rate, .{ .strength = .hard });
    for (out) |v| try testing.expectEqual(@as(f32, 0), v);
}

test "на открытии ворот нет щелчка" {
    // Щелчок — это скачок между соседними отсчётами. Ворота обязаны
    // открываться плавно, иначе каждое слово начинается с треска.
    var buf: [12000]f32 = undefined;
    fillNoise(buf[0..6000], 0.01, 3);
    fillSine(buf[6000..], 300, 0.6);

    var out: [12000]f32 = undefined;
    apply(&buf, &out, test_rate, .{ .strength = .hard });

    var worst: f32 = 0;
    var i: usize = 1;
    while (i < out.len) : (i += 1) {
        const jump = @abs(out[i] - out[i - 1]);
        if (jump > worst) worst = jump;
    }
    // Самый большой скачок в исходнике — это шаг самой синусоиды.
    var natural: f32 = 0;
    i = 1;
    while (i < buf.len) : (i += 1) {
        const jump = @abs(buf[i] - buf[i - 1]);
        if (jump > natural) natural = jump;
    }
    try testing.expect(worst <= natural * 1.2);
}

test "оценка фона не зависит от редких всплесков" {
    // Ровный тихий фон и один громкий щелчок посередине.
    var buf: [10000]f32 = undefined;
    fillNoise(&buf, 0.05, 11);
    buf[5000] = 1.0;

    const floor = floorOf(&buf);
    // Оценка около уровня фона, а не около щелчка.
    try testing.expect(floor > 0.001);
    try testing.expect(floor < 0.05);
}

test "сила подавления меняет результат, а не только надпись" {
    var buf: [12000]f32 = undefined;
    fillNoise(&buf, 0.03, 5);

    // Уровень фона задаём сами и заведомо выше самого громкого отсчёта:
    // иначе ворота открываются на всплесках шума, и все силы дают один и
    // тот же пик — первый заход теста на этом и попался, хотя правило
    // работало верно.
    var soft: [12000]f32 = undefined;
    var hard: [12000]f32 = undefined;
    apply(&buf, &soft, test_rate, .{ .strength = .soft, .floor = 0.05 });
    apply(&buf, &hard, test_rate, .{ .strength = .hard, .floor = 0.05 });

    try testing.expect(peakOf(&hard) < peakOf(&soft));
    try testing.expect(peakOf(&soft) < peakOf(&buf));
    // И ни одна из сил не глушит в ноль: пустота между словами слышна
    // как обрыв записи.
    try testing.expect(peakOf(&hard) > 0);
}

test "обработка на месте даёт то же, что и в отдельный буфер" {
    var a: [8000]f32 = undefined;
    fillNoise(a[0..4000], 0.02, 21);
    fillSine(a[4000..], 500, 0.4);
    var b: [8000]f32 = a;

    var out: [8000]f32 = undefined;
    apply(&a, &out, test_rate, .{ .strength = .normal });
    apply(&b, &b, test_rate, .{ .strength = .normal });
    for (out, b) |x, y| try testing.expectApproxEqAbs(x, y, 0.0001);
}

test "пустой запрос и негодная частота не роняют правило" {
    var out: [4]f32 = @splat(0);
    apply(&.{}, &out, test_rate, .{ .strength = .normal });
    var buf: [4]f32 = .{ 0.5, -0.5, 0.5, -0.5 };
    apply(&buf, &out, 0, .{ .strength = .normal });
    for (buf, out) |a, b| try testing.expectEqual(a, b);
    try testing.expectEqual(@as(f32, 0), floorOf(&.{}));
}

test "названия сил — для меню" {
    try testing.expectEqualStrings("обычно", Strength.normal.label());
    try testing.expectEqualStrings("выключено", Strength.off.label());
    // Ноль — это «выключено»: умолчание модели нулевое.
    try testing.expectEqual(Strength.off, @as(Strength, @enumFromInt(0)));
}
