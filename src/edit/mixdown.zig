//! Сведение звука проекта в один поток отсчётов.
//!
//! Задачи #61 и #62. Нарисованная кривая громкости, которая ничего не меняет
//! в звуке, — это не кривая громкости, а картинка. Здесь она превращается
//! в числа: каждая звуковая дорожка читается, умножается на свою громкость
//! и складывается с остальными.
//!
//! **Здесь нет ни одного обращения к Windows.** Исходники приходят уже
//! раскодированными, отсчётами. Так всё сведение целиком проверяется
//! тестами на выдуманных исходниках: подали ровный тон, нарисовали спуск —
//! и проверили, что в готовой смеси он именно такой, а не «примерно такой».
//!
//! **Громкость считается не на каждом отсчёте.** Кривая на сорока восьми
//! тысячах отсчётов в секунду обходилась бы в миллиард сравнений на десять
//! минут записи. Считаем её на границах коротких блоков и тянем между ними
//! прямую: ступенька в громкости слышна щелчком, а прямая — нет.
const std = @import("std");
const timeline = @import("timeline.zig");
const volume = @import("../sound/volume.zig");
const denoise_mod = @import("../sound/denoise.zig");

/// Раскодированный исходник: моно, отсчёты от минус единицы до единицы.
///
/// Моно нарочно: сведение решает вопрос громкости, а не расположения звука
/// в пространстве. Стерео добавит второй столбец чисел и ни одного нового
/// решения, поэтому оно будет отдельной задачей, а не довеском к этой.
pub const SourceAudio = struct {
    rate: u32 = 48_000,
    samples: []const f32 = &.{},
};

/// Через сколько отсчётов пересчитывается громкость.
///
/// Двести пятьдесят шесть отсчётов — это пять миллисекунд на сорока восьми
/// килогерцах. Кривая громкости не успевает измениться за это время
/// настолько, чтобы прямая между границами блока отличалась от неё на слух.
pub const gain_block: usize = 256;

/// Сколько отсчётов обрабатываем шумоподавлением за раз.
///
/// Окно сведения бывает разным (проигрывание просит маленькими кусками,
/// экспорт — большими), и буфер должен покрывать разумный кусок вместе
/// с разбегом. Полсекунды при сорока восьми килогерцах — это и есть
/// двадцать четыре тысячи отсчётов.
pub const denoise_window: usize = 24_000;

/// Разбег перед окном: ворота приходят к его началу «прогретыми».
pub const lead_in: usize = 12_000;

/// Сколько отсчётов займёт весь проект.
pub fn totalSamples(project: *const timeline.Project, rate: u32) usize {
    return nsToSamples(project.durationNs(), rate);
}

pub fn nsToSamples(ns: u64, rate: u32) usize {
    return @intCast(ns * rate / std.time.ns_per_s);
}

pub fn samplesToNs(samples: usize, rate: u32) u64 {
    return @as(u64, samples) * std.time.ns_per_s / rate;
}

/// Свести звуковые дорожки проекта в `out`.
///
/// `out` заполняется целиком: то, что не покрыто клипами, становится
/// тишиной, а не остаётся мусором от прошлого вызова.
pub fn mix(
    project: *const timeline.Project,
    rate: u32,
    sources: []const SourceAudio,
    out: []i16,
) void {
    mixAt(project, rate, sources, 0, out);
}

/// Свести только окно: отсчёты с `offset` по `offset + out.len`.
///
/// Плеер (#23) смешивает на ходу кусками, а не весь проект заранее:
/// часовой проект целиком — это сотни мегабайт и секунды ожидания перед
/// первым звуком. Окно из середины должно совпадать с тем же куском
/// полной смеси — это проверяет тест.
/// Перенести в играющий снимок только громкость — и ничего больше.
///
/// Проигрывание идёт по снимку проекта: звуковой поток читает его из своего
/// потока, пока человек правит настоящий проект, и копия существует именно
/// для того, чтобы резка во время игры не рвала звук на полуслове.
///
/// Но у копии была цена, и владелец на неё и наткнулся: ползунок громкости
/// двигается, надпись меняется на «-5.3 dB», а в колонках по-прежнему
/// старая громкость — правка ушла в проект, а играет снимок. Громкость —
/// единственное, что человек крутит именно на слух: её и переносим на ходу.
///
/// **Переносим только числа, не устройство дорожки.** Количество клипов,
/// их границы и список исходников остаются снимочными: изменить их под
/// читающим потоком — это щелчок или чтение мимо буфера. Громкость же —
/// отдельные числа, и худшее, что даёт гонка на них, — один блок в 256
/// отсчётов (около шести миллисекунд) со старым множителем.
pub fn copyLiveMix(dst: *timeline.Project, src: *const timeline.Project) void {
    const n = @min(dst.track_count, src.track_count);
    for (0..n) |i| {
        const from = &src.tracks[i];
        var to = &dst.tracks[i];
        if (from.kind != to.kind) continue;
        to.muted = from.muted;
        to.gain_db10 = from.gain_db10;
        to.curve_on = from.curve_on;
        // Кривую переносим точками, а потом длиной: читающий поток берёт
        // длину первой, и порядок «сначала данные, потом длина» не даёт ему
        // заглянуть в точку, которой ещё не записали.
        const pts = @min(from.curve.count, to.curve.points.len);
        @memcpy(to.curve.points[0..pts], from.curve.points[0..pts]);
        to.curve.count = pts;

        const clips = @min(from.count, to.count);
        for (0..clips) |k| to.clips[k].gain_db10 = from.clips[k].gain_db10;
    }
}

pub fn mixAt(
    project: *const timeline.Project,
    rate: u32,
    sources: []const SourceAudio,
    offset: usize,
    out: []i16,
) void {
    @memset(out, 0);
    if (rate == 0 or out.len == 0) return;
    const window_end = offset + out.len;

    for (project.trackList(), 0..) |track, track_index| {
        _ = track_index;
        if (track.kind != .audio) continue;
        // Заглушённая дорожка молчит. Проверяем здесь, а не множителем:
        // иначе она всё равно читалась бы и складывалась, только с нулём.
        if (track.muted) continue;

        for (track.list()) |clip| {
            if (clip.source >= sources.len) continue;
            const src = sources[clip.source];
            if (src.samples.len == 0 or src.rate == 0) continue;

            const from = std.math.clamp(nsToSamples(clip.at_ns, rate), offset, window_end);
            const to = std.math.clamp(nsToSamples(clip.endsAt(), rate), offset, window_end);

            // Шумоподавление считаем на весь кусок окна сразу, с разбегом.
            //
            // Ворота помнят прошлое: их состояние зависит от того, что было
            // перед этим отсчётом. Сведение же идёт блоками, и начинать
            // ворота заново в каждом блоке значило бы щёлкать на каждой
            // границе. Разбег в четверть секунды — это вдвое больше времени
            // закрытия ворот, то есть к началу окна они приходят ровно в
            // том же состоянии, в каком были бы при обработке целиком.
            var quiet = Quiet{ .clip = clip, .src = src, .rate = rate };

            var at = from;
            while (at < to) {
                const block_end = @min(at + gain_block, to);
                const g0 = volume.factor(dbAt(&track, clip, samplesToNs(at, rate)));
                const g1 = volume.factor(dbAt(&track, clip, samplesToNs(block_end, rate)));
                const span = block_end - at;

                var k = at;
                while (k < block_end) : (k += 1) {
                    const src_at = sourceIndex(clip, src, rate, k);
                    if (src_at >= src.samples.len) break;
                    // Прямая между границами блока: ступенька слышна щелчком.
                    const part = @as(f32, @floatFromInt(k - at)) / @as(f32, @floatFromInt(span));
                    const gain = g0 + (g1 - g0) * part;
                    // Шумоподавление берётся кусками по полсекунды и
                    // считается по требованию: окно сведения бывает и
                    // маленьким (проигрывание), и на всю запись (экспорт).
                    const value = if (clip.denoise != .off)
                        quiet.at(k)
                    else
                        src.samples[src_at];
                    out[k - offset] = addClamped(out[k - offset], value * gain);
                }
                at = block_end;
            }
        }
    }
}

/// Кусок клипа, пропущенный через шумоподавление.
///
/// Ворота помнят прошлое, а сведение идёт блоками — начинать их заново в
/// каждом блоке значило бы щёлкать на каждой границе. Поэтому кусок берём
/// крупный (полсекунды) и с разбегом: к началу куска ворота приходят в том
/// же состоянии, в каком были бы при обработке целиком.
///
/// Первый заход считал весь кусок окна разом и МОЛЧА пропускал эффект,
/// если окно оказывалось больше буфера, — а при экспорте оно именно такое.
/// Тест сведения это и поймал.
const Quiet = struct {
    clip: timeline.Clip,
    src: SourceAudio,
    rate: u32,
    from: usize = 0,
    len: usize = 0,
    data: [denoise_window]f32 = undefined,
    /// Уровень фона, посчитанный по ВСЕМУ клипу. Ноль — ещё не считали.
    ///
    /// По куску его считать нельзя: в куске, где звучит только шум, шум
    /// и окажется «сигналом» — ворота откроются и ничего не уберут.
    /// Первый заход так и сделал, и тест сведения это поймал.
    floor: f32 = 0,

    fn at(self: *Quiet, k: usize) f32 {
        if (self.len == 0 or k < self.from or k - self.from >= self.len) self.fill(k);
        if (self.len == 0) return 0;
        const i = k - self.from;
        return if (i < self.len) self.data[i] else 0;
    }

    /// Оценить фон по клипу целиком, но не читая его целиком.
    ///
    /// Берём восемь тысяч отсчётов, размазанных по всей длине: этого
    /// хватает, чтобы попасть и в паузы, и в речь, а стоит это одного
    /// прохода вместо часового файла на каждый кусок.
    fn floorOfClip(self: *Quiet) f32 {
        if (self.floor > 0) return self.floor;
        const total = nsToSamples(self.clip.len_ns, self.rate);
        if (total == 0) return 0;
        const want: usize = @min(total, 8192);
        var probe: [8192]f32 = undefined;
        var i: usize = 0;
        while (i < want) : (i += 1) {
            const step_at = i * total / want;
            const src_at = sourceIndex(self.clip, self.src, self.rate, nsToSamples(self.clip.at_ns, self.rate) + step_at);
            probe[i] = if (src_at < self.src.samples.len) self.src.samples[src_at] else 0;
        }
        self.floor = denoise_mod.floorOf(probe[0..want]);
        return self.floor;
    }

    fn fill(self: *Quiet, k: usize) void {
        const body = denoise_window - lead_in;
        const lead = @min(lead_in, k);
        self.from = k - lead;
        const want = @min(denoise_window, lead + body);

        var raw: [denoise_window]f32 = undefined;
        var i: usize = 0;
        while (i < want) : (i += 1) {
            const src_at = sourceIndex(self.clip, self.src, self.rate, self.from + i);
            raw[i] = if (src_at < self.src.samples.len) self.src.samples[src_at] else 0;
        }
        denoise_mod.apply(raw[0..want], self.data[0..want], self.rate, .{
            .strength = self.clip.denoise,
            .floor = self.floorOfClip(),
        });
        self.len = want;
    }
};

/// Какой отсчёт исходника приходится на этот отсчёт готовой смеси.
fn sourceIndex(clip: timeline.Clip, src: SourceAudio, rate: u32, out_at: usize) usize {
    const when_ns = samplesToNs(out_at, rate);
    // Клип мог начаться между отсчётами: считаем от его начала, а не
    // от начала дорожки, иначе накапливается сдвиг на длинном проекте.
    const inside_ns = when_ns -| clip.at_ns;
    return nsToSamples(clip.in_ns + inside_ns, src.rate);
}

/// Громкость дорожки вместе с кривой и громкостью клипа.
fn dbAt(track: *const timeline.Track, clip: timeline.Clip, at_ns: u64) volume.Db10 {
    var total = volume.sum(track.gain_db10, clip.gain_db10);
    if (track.curve_on and !track.curve.empty()) {
        total = volume.sum(total, track.curve.valueAt(at_ns));
    }
    return total;
}

/// Сложить с тем, что уже лежит, не дав сумме завернуться.
///
/// Без прижатия две громкие дорожки складываются в переполнение, и вместо
/// громкого звука выходит треск — причём ровно на тех местах, которые
/// человек и хотел услышать.
fn addClamped(already: i16, add: f32) i16 {
    const sum = @as(f32, @floatFromInt(already)) + add * 32767.0;
    return @intFromFloat(std.math.clamp(sum, -32768.0, 32767.0));
}

// ---------------------------------------------------------------- тесты

const testing = std.testing;
const sec = std.time.ns_per_s;
const test_rate: u32 = 48_000;

/// Ровный тон на всю длину: по нему видно, что сделала громкость.
fn steady(allocator: std.mem.Allocator, seconds: f32, level: f32) ![]f32 {
    const n: usize = @intFromFloat(seconds * @as(f32, @floatFromInt(test_rate)));
    const out = try allocator.alloc(f32, n);
    for (out, 0..) |*v, i| {
        const phase = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(test_rate)) * 440.0 * 2 * std.math.pi;
        v.* = @sin(phase) * level;
    }
    return out;
}

/// Пик готовой смеси на отрезке — в долях единицы.
///
/// Каждая сторона меряется своим пределом: вниз шкала уходит на один шаг
/// дальше, чем вверх, и деление отрицательного края на положительный предел
/// даёт «пик больше единицы» на совершенно исправном звуке.
fn peakBetween(out: []const i16, from_s: f32, to_s: f32) f32 {
    const from: usize = @intFromFloat(from_s * @as(f32, @floatFromInt(test_rate)));
    const to: usize = @min(@as(usize, @intFromFloat(to_s * @as(f32, @floatFromInt(test_rate)))), out.len);
    var peak: f32 = 0;
    var i = from;
    while (i < to) : (i += 1) {
        const s = @as(f32, @floatFromInt(out[i]));
        const v = if (s < 0) -s / 32768.0 else s / 32767.0;
        if (v > peak) peak = v;
    }
    return peak;
}

fn project1() !*timeline.Project {
    const p = try testing.allocator.create(timeline.Project);
    p.* = .{};
    _ = try p.addSource("тон.wav", 10 * sec);
    _ = try p.addTrack(.audio, "Звук");
    try p.place(0, 0, 0, 10 * sec);
    return p;
}

test "без правок смесь повторяет исходник" {
    const p = try project1();
    defer testing.allocator.destroy(p);

    const tone = try steady(testing.allocator, 10, 0.5);
    defer testing.allocator.free(tone);
    const out = try testing.allocator.alloc(i16, totalSamples(p, test_rate));
    defer testing.allocator.free(out);

    mix(p, test_rate, &.{.{ .rate = test_rate, .samples = tone }}, out);
    try testing.expectApproxEqAbs(@as(f32, 0.5), peakBetween(out, 1, 9), 0.01);
}

test "громкость дорожки слышна в готовой смеси" {
    const p = try project1();
    defer testing.allocator.destroy(p);
    try p.setTrackGain(0, -60); // вдвое тише

    const tone = try steady(testing.allocator, 10, 0.5);
    defer testing.allocator.free(tone);
    const out = try testing.allocator.alloc(i16, totalSamples(p, test_rate));
    defer testing.allocator.free(out);

    mix(p, test_rate, &.{.{ .rate = test_rate, .samples = tone }}, out);
    try testing.expectApproxEqAbs(@as(f32, 0.25), peakBetween(out, 1, 9), 0.01);
}

test "кривая громкости слышна там, где нарисована" {
    // Это главная проверка обеих задач: нарисованная линия, которая ничего
    // не меняет в звуке, — это картинка, а не громкость.
    const p = try project1();
    defer testing.allocator.destroy(p);
    _ = try p.addCurvePoint(0, 0, 0); // в начале как записано
    _ = try p.addCurvePoint(0, 10 * sec, -200); // к концу на двадцать децибел тише

    const tone = try steady(testing.allocator, 10, 0.5);
    defer testing.allocator.free(tone);
    const out = try testing.allocator.alloc(i16, totalSamples(p, test_rate));
    defer testing.allocator.free(out);

    mix(p, test_rate, &.{.{ .rate = test_rate, .samples = tone }}, out);

    // В начале — как записано.
    try testing.expectApproxEqAbs(@as(f32, 0.5), peakBetween(out, 0, 0.2), 0.02);
    // На середине — минус десять децибел, это примерно втрое тише.
    try testing.expectApproxEqAbs(@as(f32, 0.158), peakBetween(out, 4.9, 5.1), 0.02);
    // В конце — минус двадцать, вдесятеро тише.
    try testing.expectApproxEqAbs(@as(f32, 0.05), peakBetween(out, 9.8, 10), 0.02);
}

test "выключенная кривая на звук не влияет" {
    const p = try project1();
    defer testing.allocator.destroy(p);
    _ = try p.addCurvePoint(0, 0, -400);
    try p.setCurveOn(0, false);

    const tone = try steady(testing.allocator, 10, 0.5);
    defer testing.allocator.free(tone);
    const out = try testing.allocator.alloc(i16, totalSamples(p, test_rate));
    defer testing.allocator.free(out);

    mix(p, test_rate, &.{.{ .rate = test_rate, .samples = tone }}, out);
    try testing.expectApproxEqAbs(@as(f32, 0.5), peakBetween(out, 1, 9), 0.01);
}

test "заглушённая дорожка молчит" {
    const p = try project1();
    defer testing.allocator.destroy(p);
    try p.setMuted(0, true);

    const tone = try steady(testing.allocator, 10, 0.5);
    defer testing.allocator.free(tone);
    const out = try testing.allocator.alloc(i16, totalSamples(p, test_rate));
    defer testing.allocator.free(out);

    mix(p, test_rate, &.{.{ .rate = test_rate, .samples = tone }}, out);
    try testing.expectEqual(@as(f32, 0), peakBetween(out, 0, 10));
}

test "тишина там, где клипа нет" {
    const p = try testing.allocator.create(timeline.Project);
    defer testing.allocator.destroy(p);
    p.* = .{};
    _ = try p.addSource("тон.wav", 10 * sec);
    _ = try p.addTrack(.audio, "Звук");
    // Клип стоит со второй по четвёртую секунду.
    try p.place(0, 0, 2 * sec, 2 * sec);

    const tone = try steady(testing.allocator, 10, 0.5);
    defer testing.allocator.free(tone);
    const out = try testing.allocator.alloc(i16, totalSamples(p, test_rate));
    defer testing.allocator.free(out);

    mix(p, test_rate, &.{.{ .rate = test_rate, .samples = tone }}, out);
    try testing.expectEqual(@as(f32, 0), peakBetween(out, 0, 1.9));
    try testing.expectApproxEqAbs(@as(f32, 0.5), peakBetween(out, 2.1, 3.9), 0.01);
}

test "две дорожки складываются и не переполняются" {
    const p = try testing.allocator.create(timeline.Project);
    defer testing.allocator.destroy(p);
    p.* = .{};
    _ = try p.addSource("тон.wav", 4 * sec);
    _ = try p.addTrack(.audio, "Раз");
    _ = try p.addTrack(.audio, "Два");
    try p.place(0, 0, 0, 4 * sec);
    try p.place(1, 0, 0, 4 * sec);

    // Два громких тона в сумме дали бы больше единицы.
    const tone = try steady(testing.allocator, 4, 0.8);
    defer testing.allocator.free(tone);
    const out = try testing.allocator.alloc(i16, totalSamples(p, test_rate));
    defer testing.allocator.free(out);

    mix(p, test_rate, &.{.{ .rate = test_rate, .samples = tone }}, out);
    // Сумма упёрлась в предел, а не завернулась в треск.
    try testing.expect(peakBetween(out, 1, 3) > 0.99);
    try testing.expect(peakBetween(out, 1, 3) <= 1.0);
}

test "видеодорожка в звук не попадает" {
    const p = try testing.allocator.create(timeline.Project);
    defer testing.allocator.destroy(p);
    p.* = .{};
    _ = try p.addSource("видео.mp4", 4 * sec);
    _ = try p.addTrack(.video, "Видео");
    try p.place(0, 0, 0, 4 * sec);

    const tone = try steady(testing.allocator, 4, 0.5);
    defer testing.allocator.free(tone);
    const out = try testing.allocator.alloc(i16, totalSamples(p, test_rate));
    defer testing.allocator.free(out);

    mix(p, test_rate, &.{.{ .rate = test_rate, .samples = tone }}, out);
    try testing.expectEqual(@as(f32, 0), peakBetween(out, 0, 4));
}

test "клип берёт свой кусок исходника, а не его начало" {
    const p = try testing.allocator.create(timeline.Project);
    defer testing.allocator.destroy(p);
    p.* = .{};
    _ = try p.addSource("тон.wav", 10 * sec);
    _ = try p.addTrack(.audio, "Звук");
    try p.place(0, 0, 0, 10 * sec);
    // Отрезаем первые пять секунд: клип должен показывать вторую половину.
    try p.trim(0, 0, true, 5 * sec);

    // Исходник: первые пять секунд тихие, вторые — громкие.
    const tone = try testing.allocator.alloc(f32, 10 * test_rate);
    defer testing.allocator.free(tone);
    for (tone, 0..) |*v, i| {
        const loud = i >= 5 * test_rate;
        const phase = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(test_rate)) * 440.0 * 2 * std.math.pi;
        v.* = @sin(phase) * (if (loud) @as(f32, 0.8) else @as(f32, 0.1));
    }

    const out = try testing.allocator.alloc(i16, totalSamples(p, test_rate));
    defer testing.allocator.free(out);
    mix(p, test_rate, &.{.{ .rate = test_rate, .samples = tone }}, out);

    // Клип стоит с пятой секунды и показывает громкую половину.
    try testing.expectApproxEqAbs(@as(f32, 0.8), peakBetween(out, 6, 9), 0.02);
}

test "исходник с другой частотой не ломает сведение" {
    const p = try project1();
    defer testing.allocator.destroy(p);

    // Исходник на 24 кГц: вдвое меньше отсчётов на ту же длину.
    const half: u32 = 24_000;
    const n = 10 * half;
    const tone = try testing.allocator.alloc(f32, n);
    defer testing.allocator.free(tone);
    for (tone, 0..) |*v, i| {
        const phase = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(half)) * 440.0 * 2 * std.math.pi;
        v.* = @sin(phase) * 0.5;
    }

    const out = try testing.allocator.alloc(i16, totalSamples(p, test_rate));
    defer testing.allocator.free(out);
    mix(p, test_rate, &.{.{ .rate = half, .samples = tone }}, out);
    try testing.expectApproxEqAbs(@as(f32, 0.5), peakBetween(out, 1, 9), 0.02);
}

test "чужой номер исходника не роняет сведение" {
    const p = try testing.allocator.create(timeline.Project);
    defer testing.allocator.destroy(p);
    p.* = .{};
    _ = try p.addSource("нет.wav", 4 * sec);
    _ = try p.addTrack(.audio, "Звук");
    try p.place(0, 0, 0, 4 * sec);

    const out = try testing.allocator.alloc(i16, totalSamples(p, test_rate));
    defer testing.allocator.free(out);
    // Исходников не передали вовсе.
    mix(p, test_rate, &.{}, out);
    try testing.expectEqual(@as(f32, 0), peakBetween(out, 0, 4));
}

test "окно из середины совпадает с тем же куском полной смеси" {
    const tone_a = try steady(testing.allocator, 2.0, 0.5);
    defer testing.allocator.free(tone_a);
    var project = timeline.Project{};
    _ = try project.addTrack(.audio, "Звук");
    const src = try project.addSource("a.wav", 2 * sec);
    try project.place(0, src, sec / 2, 2 * sec);
    // Громкость с кривой: окно должно взять гейн по тому же времени.
    try project.setTrackGain(0, -60);
    const sources = [_]SourceAudio{.{ .rate = test_rate, .samples = tone_a }};

    const total = totalSamples(&project, test_rate);
    const full = try testing.allocator.alloc(i16, total);
    defer testing.allocator.free(full);
    mix(&project, test_rate, &sources, full);

    const offset: usize = 30_000;
    var window: [7000]i16 = undefined;
    mixAt(&project, test_rate, &sources, offset, &window);
    try testing.expectEqualSlices(i16, full[offset .. offset + window.len], &window);

    // Окно за концом проекта — тишина, а не чтение за краем.
    var beyond: [100]i16 = undefined;
    mixAt(&project, test_rate, &sources, total + 10, &beyond);
    for (beyond) |v| try testing.expectEqual(@as(i16, 0), v);
}

test "живая громкость доезжает до играющего снимка" {
    const allocator = std.testing.allocator;
    const live = try allocator.create(timeline.Project);
    defer allocator.destroy(live);
    live.* = .{};
    const snapshot = try allocator.create(timeline.Project);
    defer allocator.destroy(snapshot);

    const ti = try live.addTrack(.audio, "звук");
    try live.place(ti, 0, 0, std.time.ns_per_s);
    snapshot.* = live.*;

    // Человек двигает ползунок во время игры.
    try live.setTrackGain(ti, -53);
    try live.setClipGain(ti, 0, -70);
    live.tracks[ti].muted = true;
    try std.testing.expectEqual(@as(i16, 0), snapshot.tracks[ti].gain_db10);

    copyLiveMix(snapshot, live);
    try std.testing.expectEqual(@as(i16, -53), snapshot.tracks[ti].gain_db10);
    try std.testing.expectEqual(@as(i16, -70), snapshot.tracks[ti].clips[0].gain_db10);
    try std.testing.expect(snapshot.tracks[ti].muted);
}

test "живая громкость не трогает устройство дорожки" {
    const allocator = std.testing.allocator;
    const live = try allocator.create(timeline.Project);
    defer allocator.destroy(live);
    live.* = .{};
    const snapshot = try allocator.create(timeline.Project);
    defer allocator.destroy(snapshot);

    const ti = try live.addTrack(.audio, "звук");
    try live.place(ti, 0, 0, std.time.ns_per_s);
    snapshot.* = live.*;

    // Во время игры человек ещё и режет: это переноситься НЕ должно —
    // читающий поток идёт по клипам снимка.
    try live.place(ti, 0, 2 * std.time.ns_per_s, std.time.ns_per_s);
    try live.setTrackGain(ti, -120);

    copyLiveMix(snapshot, live);
    try std.testing.expectEqual(@as(usize, 1), snapshot.tracks[ti].count);
    // А громкость всё равно доехала.
    try std.testing.expectEqual(@as(i16, -120), snapshot.tracks[ti].gain_db10);
}

test "живая громкость переносит кривую вместе с длиной" {
    const allocator = std.testing.allocator;
    const live = try allocator.create(timeline.Project);
    defer allocator.destroy(live);
    live.* = .{};
    const snapshot = try allocator.create(timeline.Project);
    defer allocator.destroy(snapshot);

    const ti = try live.addTrack(.audio, "звук");
    snapshot.* = live.*;
    live.tracks[ti].curve_on = true;
    _ = try live.addCurvePoint(ti, std.time.ns_per_s, -60);

    copyLiveMix(snapshot, live);
    try std.testing.expect(snapshot.tracks[ti].curve_on);
    try std.testing.expectEqual(@as(usize, 1), snapshot.tracks[ti].curve.count);
    try std.testing.expectEqual(@as(i16, -60), snapshot.tracks[ti].curve.points[0].db10);
}

test "шумоподавление слышно в сведении" {
    const allocator = std.testing.allocator;
    const project = try allocator.create(timeline.Project);
    defer allocator.destroy(project);
    project.* = .{};

    const ti = try project.addTrack(.audio, "звук");
    const seconds = 1;
    const total = test_rate * seconds;
    try project.place(ti, 0, 0, std.time.ns_per_s * seconds);

    // Полсекунды шипения, потом громкий тон.
    var src = try allocator.alloc(f32, total);
    defer allocator.free(src);
    var rnd = std.Random.DefaultPrng.init(3);
    const r = rnd.random();
    for (src[0 .. total / 2]) |*v| v.* = (r.float(f32) * 2 - 1) * 0.02;
    for (src[total / 2 ..], 0..) |*v, i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(test_rate));
        v.* = 0.5 * @sin(2.0 * std.math.pi * 440.0 * t);
    }

    const sources = [_]SourceAudio{.{ .rate = test_rate, .samples = src }};
    var plain = try allocator.alloc(i16, total);
    defer allocator.free(plain);
    var quiet = try allocator.alloc(i16, total);
    defer allocator.free(quiet);

    mixAt(project, test_rate, &sources, 0, plain);
    try project.setClipDenoise(ti, 0, .hard);
    mixAt(project, test_rate, &sources, 0, quiet);

    // В шипящей половине стало заметно тише.
    var loud_before: i32 = 0;
    var loud_after: i32 = 0;
    for (plain[1000 .. total / 2 - 1000]) |v| loud_before = @max(loud_before, @as(i32, @intCast(@abs(v))));
    for (quiet[1000 .. total / 2 - 1000]) |v| loud_after = @max(loud_after, @as(i32, @intCast(@abs(v))));
    try std.testing.expect(loud_after * 2 < loud_before);

    // А тон остался собой.
    var tone_before: i32 = 0;
    var tone_after: i32 = 0;
    for (plain[total / 2 + 2000 ..]) |v| tone_before = @max(tone_before, @as(i32, @intCast(@abs(v))));
    for (quiet[total / 2 + 2000 ..]) |v| tone_after = @max(tone_after, @as(i32, @intCast(@abs(v))));
    try std.testing.expect(tone_after > @divTrunc(tone_before * 9, 10));
}
