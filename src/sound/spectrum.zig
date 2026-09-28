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

/// Границы слышимого, которые нам интересны по умолчанию: ниже 60 Гц у
/// микрофона в основном гул стола, выше 12 кГц — воздух и шипение.
pub const low_hz: f32 = 60;
pub const high_hz: f32 = 12000;

/// Что показывать и насколько подробно (просьба владельца 28.09.2026).
///
/// Ноль во всех полях значит «как по умолчанию»: правило проекта требует
/// нулевых умолчаний, и заодно это отвечает на вопрос «что видно, пока
/// ничего не трогали» — то же, что и раньше.
pub const Setup = struct {
    /// Длина окна анализа. Ноль — `analysis_window`.
    ///
    /// Это и есть «подробность»: длиннее окно — тоньше различаются
    /// частоты, но столбик отвечает за более длинный кусок времени. Один
    /// ползунок меняет обе стороны сразу, потому что это одна и та же
    /// величина: короткое окно не может быть одновременно точным по
    /// времени и по частоте.
    window: usize = 0,
    /// Нижняя и верхняя показываемые частоты. Ноль — умолчание.
    low: f32 = 0,
    high: f32 = 0,

    pub fn windowLen(self: Setup) usize {
        return if (self.window == 0) analysis_window else self.window;
    }

    pub fn lowHz(self: Setup) f32 {
        return if (self.low <= 0) low_hz else self.low;
    }

    pub fn highHz(self: Setup) f32 {
        const top = if (self.high <= 0) high_hz else self.high;
        // Верх всегда выше низа хотя бы вдвое: иначе полосы схлопнулись бы
        // в одну точку и логарифм потерял бы смысл.
        return @max(top, self.lowHz() * 2);
    }
};

/// Нижняя частота полосы. Полосы идут в геометрической прогрессии.
pub fn bandLowIn(setup: Setup, index: usize) f32 {
    const lo = setup.lowHz();
    const step = std.math.pow(f32, setup.highHz() / lo, 1.0 / @as(f32, @floatFromInt(bands)));
    return lo * std.math.pow(f32, step, @floatFromInt(index));
}

pub fn bandLow(index: usize) f32 {
    return bandLowIn(.{}, index);
}

/// Середина полосы — по ней и считаем.
pub fn bandMidIn(setup: Setup, index: usize) f32 {
    return @sqrt(bandLowIn(setup, index) * bandLowIn(setup, index + 1));
}

pub fn bandMid(index: usize) f32 {
    return bandMidIn(.{}, index);
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

    // Сглаживаем края куска «колоколом» Ханна.
    //
    // Без него кусок обрывается посередине колебания, и этот обрыв
    // разлетается по всем полосам: чистый тон выглядит широкой кашей.
    // Именно это владелец и увидел на спектрограмме. Колокол стоит одного
    // косинуса на отсчёт и убирает почти всю кашу.
    var s_prev: f32 = 0;
    var s_prev2: f32 = 0;
    const last: f32 = @floatFromInt(@max(samples.len - 1, 1));
    for (samples, 0..) |v, i| {
        const t: f32 = @floatFromInt(i);
        const bell = 0.5 - 0.5 * @cos(2.0 * std.math.pi * t / last);
        const s = v * bell + coeff * s_prev - s_prev2;
        s_prev2 = s_prev;
        s_prev = s;
    }
    const power = s_prev2 * s_prev2 + s_prev * s_prev - coeff * s_prev * s_prev2;
    if (power <= 0) return 0;
    return @sqrt(power) / n;
}

/// Один столбик спектрограммы: сила каждой полосы для этого куска.
pub fn column(samples: []const f32, rate: u32, out: *[bands]f32) void {
    columnIn(.{}, samples, rate, out);
}

pub fn columnIn(setup: Setup, samples: []const f32, rate: u32, out: *[bands]f32) void {
    for (out, 0..) |*v, i| v.* = strength(samples, rate, bandMidIn(setup, i));
}

/// Сколько отсчётов нужно, чтобы отличить одну частоту от другой.
///
/// Разрешение по частоте — это частота дискретизации, делённая на длину
/// куска: 85 отсчётов при 48 кГц дают шаг в 565 Гц, и чистый тон в 440 Гц
/// на таком куске виден одинаково во всех полосах. Тысяча отсчётов даёт
/// около 47 Гц — тон становится узкой полоской, ради которой на
/// спектрограмму и смотрят.
pub const analysis_window: usize = 1024;

/// Спектрограмма целиком: куски слева направо, полосы снизу вверх.
///
/// **Окно анализа длиннее шага между столбиками, и они перекрываются.**
/// Первый заход резал отсчёты на столько кусков, сколько столбиков, —
/// и каждый кусок выходил слишком коротким, чтобы отличить частоту от
/// частоты. Владелец сразу это и увидел: «тяну один тон, а на
/// спектрограмме его не видно». Плата за перекрытие — столбик отвечает
/// не только за свой отрезок, но и за то, что было чуть раньше; это
/// честнее, чем показывать кашу.
///
/// Первый заход рассуждал наоборот («перекрытие сгладило бы картинку»), и
/// рассуждение было неверным: сглаживать там было нечего — не было и
/// самой картинки.
pub fn spectrogram(samples: []const f32, rate: u32, out: [][bands]f32) void {
    spectrogramIn(.{}, samples, rate, out);
}

/// Спектрограмма по настройкам человека.
pub fn spectrogramIn(setup: Setup, samples: []const f32, rate: u32, out: [][bands]f32) void {
    spectrogramWith2(setup, samples, rate, setup.windowLen(), out);
}

/// То же, но с заданной длиной окна: ею пользуются тесты, чтобы показать,
/// что короткое окно как раз и мажет.
pub fn spectrogramWith(samples: []const f32, rate: u32, window: usize, out: [][bands]f32) void {
    spectrogramWith2(.{}, samples, rate, window, out);
}

fn spectrogramWith2(setup: Setup, samples: []const f32, rate: u32, window: usize, out: [][bands]f32) void {
    if (out.len == 0) return;
    if (samples.len == 0 or window == 0) {
        for (out) |*col| col.* = @splat(0);
        return;
    }
    const hop = @max(samples.len / out.len, 1);
    for (out, 0..) |*col, i| {
        // Окно кончается там, где кончается отрезок этого столбика, и
        // тянется назад: так столбик отвечает за «к этому моменту», а не
        // за «после него».
        const end = @min((i + 1) * hop, samples.len);
        const want = @min(window, end);
        columnIn(setup, samples[end - want .. end], rate, col);
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

test "тон виден узкой полосой, а не кашей" {
    // Тот самый случай, на который пожаловался владелец: один тон,
    // а на спектрограмме его «не видно».
    var buf: [4096]f32 = undefined;
    sine(&buf, 440, 0.5);

    var cols: [48][bands]f32 = undefined;
    spectrogram(&buf, test_rate, &cols);

    var best: usize = 0;
    var sum: f32 = 0;
    for (cols[40], 0..) |v, i| {
        sum += v;
        if (v > cols[40][best]) best = i;
    }
    // Полоса с тоном забирает заметную долю всей силы: значит она видна
    // глазом, а не тонет среди соседей.
    try testing.expect(cols[40][best] > sum / 6);
    // И она рядом с 440 Гц. Не «содержит 440»: тон может лечь ровно на
    // границу двух полос и разделиться между ними поровну — первый заход
    // теста этого не учёл и падал на верном спектре.
    const mid = bandMid(best);
    try testing.expect(@abs(mid - 440) < 440 * 0.35);
}

test "короткое окно мажет тон по всем полосам" {
    // Почему окно анализа длинное: показываем, что на коротком его нет.
    var buf: [4096]f32 = undefined;
    sine(&buf, 440, 0.5);

    var cols: [48][bands]f32 = undefined;
    spectrogramWith(&buf, test_rate, 85, &cols);

    var best: usize = 0;
    var sum: f32 = 0;
    for (cols[40], 0..) |v, i| {
        sum += v;
        if (v > cols[40][best]) best = i;
    }
    // На коротком окне самая сильная полоса ничем не выделяется.
    try testing.expect(cols[40][best] < sum / 6);
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

test "настройки по умолчанию — те же, что были" {
    const zero = Setup{};
    try testing.expectEqual(analysis_window, zero.windowLen());
    try testing.expectEqual(low_hz, zero.lowHz());
    try testing.expectEqual(high_hz, zero.highHz());
    try testing.expectApproxEqAbs(bandMid(5), bandMidIn(zero, 5), 0.01);
}

test "диапазон частот сжимает полосы в заданные границы" {
    const voice = Setup{ .low = 200, .high = 4000 };
    try testing.expectApproxEqAbs(@as(f32, 200), bandLowIn(voice, 0), 0.01);
    try testing.expectApproxEqAbs(@as(f32, 4000), bandLowIn(voice, bands), 1.0);
    // И тон внутри этих границ по-прежнему находится.
    var buf: [4096]f32 = undefined;
    sine(&buf, 1000, 0.5);
    var cols: [8][bands]f32 = undefined;
    spectrogramIn(voice, &buf, test_rate, &cols);
    var best: usize = 0;
    for (cols[7], 0..) |v, i| {
        if (v > cols[7][best]) best = i;
    }
    try testing.expect(@abs(bandMidIn(voice, best) - 1000) < 1000 * 0.35);
}

test "перевёрнутый диапазон не ломает полосы" {
    // Верх ниже низа мог бы прийти только из ошибки, но делить на ноль
    // и брать логарифм от единицы нельзя.
    const upside = Setup{ .low = 4000, .high = 100 };
    try testing.expect(upside.highHz() > upside.lowHz());
    try testing.expect(bandLowIn(upside, bands) > bandLowIn(upside, 0));
}

test "подробность меняет длину окна, а не число полос" {
    const rough = Setup{ .window = 128 };
    try testing.expectEqual(@as(usize, 128), rough.windowLen());
    var buf: [4096]f32 = undefined;
    sine(&buf, 440, 0.5);
    var cols: [16][bands]f32 = undefined;
    spectrogramIn(rough, &buf, test_rate, &cols);
    // Полос столько же, но тон размазан сильнее, чем на длинном окне.
    var rough_best: f32 = 0;
    var rough_sum: f32 = 0;
    for (cols[15]) |v| {
        rough_sum += v;
        if (v > rough_best) rough_best = v;
    }
    spectrogramIn(.{}, &buf, test_rate, &cols);
    var fine_best: f32 = 0;
    var fine_sum: f32 = 0;
    for (cols[15]) |v| {
        fine_sum += v;
        if (v > fine_best) fine_best = v;
    }
    try testing.expect(fine_best / fine_sum > rough_best / rough_sum);
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
