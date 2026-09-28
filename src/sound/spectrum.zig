//! Спектр и огибающая: два других взгляда на тот же звук.
//!
//! Просьба владельца (28.09.2026): «хочу кликнуть по волне и перейти к
//! спектрограмме, ещё раз кликнуть — к огибающей».
//!
//! Три представления отвечают на три разных вопроса, и потому нужны все три:
//! осциллограмма — «какой формы сигнал», спектрограмма — «из каких частот он
//! состоит» (шум вентилятора и голос выглядят на ней по-разному, а на
//! осциллограмме одинаково), огибающая — «где громко, а где тихо» на целом
//! куске, без мельтешения отдельных колебаний.
//!
//! **Считаем Гёрцелем, а не быстрым преобразованием.** Нам нужны два десятка
//! полос, а не все частоты: Гёрцель даёт ровно запрошенную полосу и занимает
//! двадцать строк, которые можно прочитать и проверить. Полное преобразование
//! ради того же ответа пришлось бы писать, отлаживать и объяснять.
//!
//! **Полосы растут в геометрии, а не равномерно.** Слух устроен так, что
//! расстояние от 100 до 200 Гц он слышит так же, как от 1000 до 2000. На
//! равномерной шкале весь голос собрался бы в левую четверть картинки.
const std = @import("std");

/// Сколько полос по высоте. Двадцать четыре — столько различимых полосок
/// помещается в поле высотой около шестидесяти точек.
pub const bands: usize = 24;

/// Границы слышимого, которые нам интересны: ниже 60 Гц у микрофона
/// в основном гул стола, выше 12 кГц — воздух и шипение.
pub const low_hz: f32 = 60;
pub const high_hz: f32 = 12000;

/// Нижняя частота полосы. Полосы идут в геометрической прогрессии.
pub fn bandLow(index: usize) f32 {
    const step = std.math.pow(f32, high_hz / low_hz, 1.0 / @as(f32, @floatFromInt(bands)));
    return low_hz * std.math.pow(f32, step, @floatFromInt(index));
}

/// Середина полосы — по ней и считаем.
pub fn bandMid(index: usize) f32 {
    return @sqrt(bandLow(index) * bandLow(index + 1));
}

/// Сила одной частоты в куске отсчётов, алгоритмом Гёрцеля.
///
/// Возвращает величину, а не децибелы: переводом в децибелы занимается тот,
/// кто рисует, — ему же решать, что считать «тишиной».
pub fn strength(samples: []const f32, rate: u32, freq_hz: f32) f32 {
    if (samples.len == 0 or rate == 0 or freq_hz <= 0) return 0;
    const n: f32 = @floatFromInt(samples.len);
    const k = freq_hz * n / @as(f32, @floatFromInt(rate));
    const omega = 2.0 * std.math.pi * k / n;
    const coeff = 2.0 * @cos(omega);

    var s_prev: f32 = 0;
    var s_prev2: f32 = 0;
    for (samples) |v| {
        const s = v + coeff * s_prev - s_prev2;
        s_prev2 = s_prev;
        s_prev = s;
    }
    const power = s_prev2 * s_prev2 + s_prev * s_prev - coeff * s_prev * s_prev2;
    if (power <= 0) return 0;
    return @sqrt(power) / n;
}

/// Один столбик спектрограммы: сила каждой полосы для этого куска.
pub fn column(samples: []const f32, rate: u32, out: *[bands]f32) void {
    for (out, 0..) |*v, i| v.* = strength(samples, rate, bandMid(i));
}

/// Спектрограмма целиком: куски слева направо, полосы снизу вверх.
///
/// Куски НЕ перекрываются: перекрытие сгладило бы картинку, но столбик
/// перестал бы отвечать за свой отрезок времени, а именно это на
/// спектрограмме и читают — «когда» и «что».
pub fn spectrogram(samples: []const f32, rate: u32, out: [][bands]f32) void {
    if (out.len == 0) return;
    const per = samples.len / out.len;
    for (out, 0..) |*col, i| {
        if (per == 0) {
            col.* = @splat(0);
            continue;
        }
        column(samples[i * per ..][0..per], rate, col);
    }
}

/// Огибающая: пик по каждой корзине отсчётов.
///
/// Именно пик, а не среднее: среднее у звука около нуля (колебание ходит в
/// обе стороны), и огибающая по среднему всегда выглядела бы тишиной.
pub fn envelope(samples: []const f32, out: []f32) void {
    if (out.len == 0) return;
    if (samples.len == 0) {
        @memset(out, 0);
        return;
    }
    const per = @max(samples.len / out.len, 1);
    for (out, 0..) |*v, i| {
        const from = @min(i * per, samples.len);
        const to = @min(from + per, samples.len);
        var peak: f32 = 0;
        for (samples[from..to]) |s| {
            const a = @abs(s);
            if (a > peak) peak = a;
        }
        v.* = peak;
    }
}

/// Какой взгляд на звук показан сейчас.
pub const View = enum {
    /// Осциллограмма: сами отсчёты. Ноль — умолчание, как и было до просьбы.
    wave,
    /// Спектрограмма: время слева направо, частота снизу вверх.
    spectrogram,
    /// Огибающая: где громко, где тихо.
    envelope,

    /// Следующий по кругу: щелчок переключает, четвёртый щелчок возвращает
    /// к началу — иначе пришлось бы помнить, куда идти назад.
    pub fn next(self: View) View {
        return switch (self) {
            .wave => .spectrogram,
            .spectrogram => .envelope,
            .envelope => .wave,
        };
    }

    pub fn label(self: View) []const u8 {
        return switch (self) {
            .wave => "осциллограмма",
            .spectrogram => "спектрограмма",
            .envelope => "огибающая",
        };
    }
};

// ---------------------------------------------------------------- тесты

const testing = std.testing;
const test_rate: u32 = 48_000;

fn sine(buf: []f32, hz: f32, amplitude: f32) void {
    for (buf, 0..) |*v, i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(test_rate));
        v.* = amplitude * @sin(2.0 * std.math.pi * hz * t);
    }
}

test "полосы растут в геометрии и покрывают слышимое" {
    try testing.expectApproxEqAbs(low_hz, bandLow(0), 0.01);
    try testing.expectApproxEqAbs(high_hz, bandLow(bands), 1.0);
    // Каждая следующая шире предыдущей — это и значит «в геометрии».
    const first = bandLow(1) - bandLow(0);
    const last = bandLow(bands) - bandLow(bands - 1);
    try testing.expect(last > first * 10);
}

test "спектр находит частоту, которая в сигнале есть" {
    var buf: [4096]f32 = undefined;
    sine(&buf, 1000, 0.5);

    var cols: [1][bands]f32 = undefined;
    spectrogram(&buf, test_rate, &cols);

    var best: usize = 0;
    for (cols[0], 0..) |v, i| {
        if (v > cols[0][best]) best = i;
    }
    // Самая сильная полоса — та, в которую попадает 1000 Гц.
    try testing.expect(bandLow(best) <= 1000 and bandLow(best + 1) >= 1000);
    // И она заметно сильнее дальней: иначе «нашли» было бы случайностью.
    try testing.expect(cols[0][best] > cols[0][0] * 5);
}

test "две частоты видны обе" {
    var buf: [4096]f32 = undefined;
    for (&buf, 0..) |*v, i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(test_rate));
        v.* = 0.4 * @sin(2.0 * std.math.pi * 300.0 * t) + 0.4 * @sin(2.0 * std.math.pi * 4000.0 * t);
    }
    var cols: [1][bands]f32 = undefined;
    spectrogram(&buf, test_rate, &cols);

    var low_band: usize = 0;
    var high_band: usize = 0;
    for (0..bands) |i| {
        if (bandLow(i) <= 300 and bandLow(i + 1) >= 300) low_band = i;
        if (bandLow(i) <= 4000 and bandLow(i + 1) >= 4000) high_band = i;
    }
    // Обе полосы сильнее середины между ними.
    const middle = @divTrunc(low_band + high_band, 2);
    try testing.expect(cols[0][low_band] > cols[0][middle]);
    try testing.expect(cols[0][high_band] > cols[0][middle]);
}

test "тишина не рисует ничего" {
    const quiet: [2048]f32 = @splat(0);
    var cols: [4][bands]f32 = undefined;
    spectrogram(&quiet, test_rate, &cols);
    for (cols) |col| {
        for (col) |v| try testing.expectApproxEqAbs(@as(f32, 0), v, 0.0001);
    }

    var env: [16]f32 = undefined;
    envelope(&quiet, &env);
    for (env) |v| try testing.expectEqual(@as(f32, 0), v);
}

test "огибающая идёт за громкостью, а не за формой" {
    var buf: [1024]f32 = undefined;
    // Первая половина тихая, вторая громкая.
    sine(buf[0..512], 440, 0.1);
    sine(buf[512..], 440, 0.8);

    var env: [8]f32 = undefined;
    envelope(&buf, &env);
    // Слева тихо, справа громко — и это видно без разглядывания колебаний.
    try testing.expect(env[0] < 0.2);
    try testing.expect(env[7] > 0.6);
}

test "спектрограмма показывает, КОГДА была частота" {
    var buf: [4096]f32 = undefined;
    @memset(&buf, 0);
    sine(buf[2048..], 2000, 0.6);

    var cols: [4][bands]f32 = undefined;
    spectrogram(&buf, test_rate, &cols);

    var band_2k: usize = 0;
    for (0..bands) |i| {
        if (bandLow(i) <= 2000 and bandLow(i + 1) >= 2000) band_2k = i;
    }
    // В первой половине этой частоты нет, во второй есть.
    try testing.expect(cols[0][band_2k] < cols[3][band_2k] / 5);
}

test "пустой запрос не роняет ни одно правило" {
    var cols: [0][bands]f32 = undefined;
    spectrogram(&.{}, test_rate, &cols);
    var one: [1][bands]f32 = undefined;
    spectrogram(&.{}, test_rate, &one);
    envelope(&.{}, &.{});
    try testing.expectEqual(@as(f32, 0), strength(&.{}, test_rate, 1000));
    // Частота ноль и частота дискретизации ноль — тоже не беда.
    var buf: [64]f32 = undefined;
    sine(&buf, 440, 0.5);
    try testing.expectEqual(@as(f32, 0), strength(&buf, 0, 440));
    try testing.expectEqual(@as(f32, 0), strength(&buf, test_rate, 0));
}

test "щелчок ведёт по кругу и возвращает к началу" {
    try testing.expectEqual(View.spectrogram, View.wave.next());
    try testing.expectEqual(View.envelope, View.spectrogram.next());
    try testing.expectEqual(View.wave, View.envelope.next());
    // Умолчание — осциллограмма: как было до просьбы.
    const zero: View = @enumFromInt(0);
    try testing.expectEqual(View.wave, zero);
    try testing.expectEqualStrings("спектрограмма", View.spectrogram.label());
}
