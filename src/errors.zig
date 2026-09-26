//! Ошибки словами, одинаково для окна и для командной строки.
//!
//! Требование цели: ошибка объясняется словами, а не кодом. Текст один на обе
//! формы — иначе они начнут расходиться, и человек, прочитавший объяснение в
//! окне, не найдёт его в консоли.
const std = @import("std");
const builtin = @import("builtin");
const win32 = @import("win32.zig");
const lang = @import("lang.zig");
const c = win32.c;

/// Чем закончилась запись. Отсюда берётся код возврата командной строки.
pub const Outcome = enum {
    /// Файл записан, потерь нет.
    recorded,
    /// Файл записан, но часть кадров система показала мимо нас.
    recorded_with_drops,
    /// Файла нет.
    failed,
    /// Неверные ключи или их сочетание.
    bad_usage,
    /// Источник пропал посреди записи (сменились дисплеи, окно закрыли) —
    /// снятое до этого момента дописано и закрыто (#126).
    source_lost,

    pub fn exitCode(self: Outcome) u8 {
        return switch (self) {
            .recorded => 0,
            .failed => 1,
            .bad_usage => 2,
            .recorded_with_drops => 3,
            .source_lost => 4,
        };
    }

    pub fn label(self: Outcome) []const u8 {
        return switch (self) {
            .recorded => "записан",
            .recorded_with_drops => "записан с пропусками",
            .failed => "не записан",
            .bad_usage => "неверные ключи",
            .source_lost => "записан не целиком: источник пропал",
        };
    }
};

/// Сколько тишины от источника терпеть, прежде чем сказать о ней (#132).
///
/// Окно, закрытое целиком чужими, у части программ (Aurora, игры) не
/// рисуется: захват окна отдаёт один стартовый кадр и замолкает, а прежде
/// об этом говорил только NothingCaptured в конце — через пять минут пустой
/// записи. Живой источник отдаёт кадр за доли секунды; три секунды — с
/// запасом на запуск кодировщика и редкую перерисовку.
pub const silence_wait_ns: u64 = 3 * std.time.ns_per_s;

/// Источник молчит дольше `silence_wait_ns` с последнего кадра (или начала).
pub fn silentFor(last_frame_ns: u64, now_ns: u64) bool {
    return now_ns -| last_frame_ns >= silence_wait_ns;
}

test "silentFor: граница ожидания от последнего кадра (#132)" {
    const t0: u64 = 1_000;
    try std.testing.expect(!silentFor(t0, t0 + silence_wait_ns - 1));
    try std.testing.expect(silentFor(t0, t0 + silence_wait_ns));
    // Часы не пошли назад в минус.
    try std.testing.expect(!silentFor(t0, t0 - 1));
}

/// Доля потерянных кадров, начиная с которой запись — «с пропусками» (#123).
///
/// Прежде код 3 давала любая потеря: 24 кадра на 17 тысяч (0,14 %) для
/// скрипта выглядели так же, как брак. Процент — граница, за которой потери
/// начинают быть видны глазом на движении; меньше — это одиночные кадры,
/// которые кодировщик и так размазывает.
pub const max_drop_share: f64 = 0.01;

/// Насколько файл может быть короче времени записи, не считаясь неполным
/// (#115): первая секунда уходит на то, что захват отдаст первый кадр, а
/// длинная запись теряет доли процента на округлении длительностей.
pub const short_slack_ns: u64 = std.time.ns_per_s;
pub const short_slack_share: f64 = 0.02;

/// Что известно о записи к её концу — из этого и выносится итог.
pub const Facts = struct {
    frames: u64,
    dropped: u64,
    /// Сколько шла запись по часам.
    record_ns: u64,
    /// Сколько длится то, что оказалось в файле.
    file_ns: u64,
    /// Источник пропал посреди записи.
    source_lost: bool = false,

    pub fn dropShare(self: Facts) f64 {
        const total = self.frames + self.dropped;
        if (total == 0) return 0;
        return @as(f64, @floatFromInt(self.dropped)) / @as(f64, @floatFromInt(total));
    }

    /// Файл заметно короче записи — хвост потерян (#115: под нагрузкой
    /// 285 с записи легли в файл на 206 с при итоге «записан»).
    pub fn short(self: Facts) bool {
        const by_share: u64 = @intFromFloat(@as(f64, @floatFromInt(self.record_ns)) * short_slack_share);
        return self.file_ns + @max(short_slack_ns, by_share) < self.record_ns;
    }
};

/// Итог записи по фактам. Порядок — от худшего: пропавший источник важнее
/// пропусков, пропуски и короткий файл — важнее «всё хорошо».
pub fn judge(f: Facts) Outcome {
    if (f.source_lost) return .source_lost;
    if (f.dropShare() > max_drop_share or f.short()) return .recorded_with_drops;
    return .recorded;
}

test "итог: немного потерь — записан; больше процента — с пропусками" {
    const s = std.time.ns_per_s;
    try std.testing.expectEqual(Outcome.recorded, judge(.{ .frames = 16555, .dropped = 24, .record_ns = 285 * s, .file_ns = 285 * s }));
    try std.testing.expectEqual(Outcome.recorded_with_drops, judge(.{ .frames = 990, .dropped = 11, .record_ns = 30 * s, .file_ns = 30 * s }));
    try std.testing.expectEqual(Outcome.recorded, judge(.{ .frames = 990, .dropped = 10, .record_ns = 30 * s, .file_ns = 30 * s }));
}

test "итог: файл короче записи — с пропусками (#115)" {
    const s = std.time.ns_per_s;
    try std.testing.expectEqual(Outcome.recorded_with_drops, judge(.{ .frames = 12062, .dropped = 0, .record_ns = 285 * s, .file_ns = 206 * s }));
    // Секунда на старт и 2 % на округление — в пределах нормы.
    try std.testing.expectEqual(Outcome.recorded, judge(.{ .frames = 400, .dropped = 0, .record_ns = 14 * s, .file_ns = 13 * s + s / 2 }));
    try std.testing.expectEqual(Outcome.recorded, judge(.{ .frames = 8000, .dropped = 0, .record_ns = 285 * s, .file_ns = 280 * s }));
    try std.testing.expectEqual(Outcome.recorded_with_drops, judge(.{ .frames = 8000, .dropped = 0, .record_ns = 285 * s, .file_ns = 278 * s }));
}

test "итог: пропавший источник важнее остального, код 4" {
    const s = std.time.ns_per_s;
    const o = judge(.{ .frames = 10, .dropped = 5, .record_ns = 60 * s, .file_ns = 10 * s, .source_lost = true });
    try std.testing.expectEqual(Outcome.source_lost, o);
    try std.testing.expectEqual(@as(u8, 4), o.exitCode());
}

/// Объяснение ошибки словами, на языке окон (#100). Возвращает предложение,
/// а не имя ошибки.
pub fn explain(err: anyerror) []const u8 {
    return switch (err) {
        error.AccessDenied => lang.t(
            \\захват экрана запрещён системой: открыт экран блокировки, окно
            \\с правами администратора или выход уже занят другой программой.
        ),
        error.NoDevice => lang.t(
            \\не создаётся устройство Direct3D: нет видеоадаптера или драйвера.
        ),
        error.NoOutput => lang.t(
            \\нет монитора с таким номером. Посмотреть список: zigrec monitors
        ),
        error.Lost => lang.t(
            \\захват экрана потерян и не восстановился: сменилось разрешение
            \\или другая программа заняла экран монопольно.
        ),
        error.Unsupported => lang.t(
            \\запись работает только в Windows.
        ),
        error.WindowNotFound => lang.t(
            \\окно с таким заголовком не найдено. Посмотреть список: zigrec windows
        ),
        error.WindowMinimized => lang.t(
            \\окно свёрнуто, снимать нечего. Разверните его и повторите.
        ),
        error.NothingCaptured => lang.t(
            \\на экране за всё время записи ничего не изменилось: кадров нет,
            \\и файл был бы пуст. Так бывает у неподвижного угла экрана.
        ),
        error.StartupFailed => lang.t(
            \\не поднимается Media Foundation: в системе нет кодировщика H.264.
        ),
        error.CreateFailed => lang.t(
            \\не получается создать файл: путь недоступен или файл занят другой
            \\программой. Закройте плеер, который его открыл, или выберите другое имя.
        ),
        error.FileBusy => lang.t(
            \\файл занят другой программой: он открыт в плеере или в проводнике.
            \\Закройте его или выберите другое имя.
        ),
        error.FormatRejected => lang.t(
            \\кодировщик не принял размер кадра: стороны должны быть чётными
            \\и не больше того, что умеет видеокарта.
        ),
        error.WriteFailed => lang.t(
            \\сбой при записи кадра: закончилось место на диске или отвалился кодировщик.
        ),
        error.FinalizeFailed => lang.t(
            \\файл не закрылся как надо и остался недоигранным.
        ),
        error.OutOfMemory => lang.t(
            \\не хватило памяти под кадр.
        ),
        error.NoMicrophone => lang.t(
            \\микрофон не найден: он отключён, не подключён или не выбран
            \\устройством записи по умолчанию. Проверьте «Параметры звука — Ввод».
        ),
        error.MicAccessDenied => lang.t(
            \\Windows не пускает к микрофону: доступ запрещён в настройках
            \\приватности. «Параметры — Конфиденциальность — Микрофон».
        ),
        error.MicBadFormat => lang.t(
            \\микрофон отдаёт формат, который мы не понимаем.
        ),
        error.NoSpeakers => lang.t(
            \\устройства вывода нет: системный звук брать неоткуда. Проверьте
            \\«Параметры звука — Вывод».
        ),
        error.AlreadyRecording => lang.t(
            \\запись уже идёт.
        ),
        error.PathTooLong => lang.t(
            \\слишком длинный путь к файлу.
        ),
        else => lang.t("неожиданный сбой"),
    };
}

/// Короткое объяснение в одну строку — для мест, где нет места на абзац:
/// строка состояния, панель осциллографа, подсказка в трее.
pub fn short(err: anyerror) []const u8 {
    return switch (err) {
        error.NoMicrophone => lang.t("микрофон не найден или отключён"),
        error.MicAccessDenied => lang.t("доступ к микрофону запрещён в настройках"),
        error.MicBadFormat => lang.t("непонятный формат микрофона"),
        error.NoSpeakers => lang.t("нет устройства вывода: системный звук брать неоткуда"),
        error.AccessDenied => lang.t("захват экрана запрещён системой"),
        error.NoDevice => lang.t("нет устройства Direct3D"),
        error.NoOutput => lang.t("нет такого монитора"),
        error.Lost => lang.t("захват потерян"),
        error.FileBusy => lang.t("файл занят другой программой"),
        error.CreateFailed => lang.t("файл не создаётся"),
        error.StartupFailed => lang.t("нет кодировщика H.264"),
        error.WriteFailed => lang.t("сбой записи кадра"),
        error.FinalizeFailed => lang.t("файл не закрылся как надо"),
        error.Unsupported => lang.t("только для Windows"),
        else => lang.t("сбой"),
    };
}

pub const CheckError = error{
    /// Файл занят другой программой.
    FileBusy,
    /// Каталога нет или в него нельзя писать.
    CreateFailed,
};

/// Проверить, что файл можно создать, ДО того как поднимать захват и кодировщик.
///
/// Иначе человек нажимает «Записать», ждёт, и только в конце узнаёт, что файл
/// был занят плеером. Проверка стоит один вызов Windows.
pub fn ensureWritable(path: []const u8) CheckError!void {
    if (builtin.os.tag != .windows) return;
    var wide: [std.fs.max_path_bytes]u16 = undefined;
    const n = std.unicode.utf8ToUtf16Le(&wide, path) catch return CheckError.CreateFailed;
    wide[n] = 0;
    const handle = c.CreateFileW(
        @ptrCast(&wide),
        c.GENERIC_WRITE,
        0, // никому не даём доступ: так же откроет и кодировщик
        null,
        c.CREATE_ALWAYS,
        c.FILE_ATTRIBUTE_NORMAL,
        null,
    );
    if (handle == c.INVALID_HANDLE_VALUE) {
        return switch (c.GetLastError()) {
            c.ERROR_SHARING_VIOLATION, c.ERROR_ACCESS_DENIED, c.ERROR_LOCK_VIOLATION => CheckError.FileBusy,
            else => CheckError.CreateFailed,
        };
    }
    _ = c.CloseHandle(handle);
}

/// Удалить файл, если он пуст. Нужен после `ensureWritable`: та создаёт файл,
/// и не начавшаяся запись оставила бы в папке пустой mp4, который выглядит
/// как испорченная запись.
pub fn removeIfEmpty(path: []const u8) void {
    if (builtin.os.tag != .windows) return;
    var wide: [std.fs.max_path_bytes]u16 = undefined;
    const n = std.unicode.utf8ToUtf16Le(&wide, path) catch return;
    wide[n] = 0;
    var data: c.WIN32_FILE_ATTRIBUTE_DATA = undefined;
    if (c.GetFileAttributesExW(@ptrCast(&wide), c.GetFileExInfoStandard, &data) == 0) return;
    if (data.nFileSizeHigh != 0 or data.nFileSizeLow != 0) return;
    _ = c.DeleteFileW(@ptrCast(&wide));
}

// ---------------------------------------------------------------- тесты

test "коды возврата различают три исхода" {
    try std.testing.expectEqual(@as(u8, 0), Outcome.recorded.exitCode());
    try std.testing.expectEqual(@as(u8, 3), Outcome.recorded_with_drops.exitCode());
    try std.testing.expectEqual(@as(u8, 1), Outcome.failed.exitCode());
    try std.testing.expectEqual(@as(u8, 2), Outcome.bad_usage.exitCode());
}

test "у каждого исхода своя подпись" {
    var seen: [4][]const u8 = undefined;
    for ([_]Outcome{ .recorded, .recorded_with_drops, .failed, .bad_usage }, 0..) |o, i| {
        seen[i] = o.label();
        try std.testing.expect(seen[i].len > 0);
    }
    try std.testing.expect(!std.mem.eql(u8, seen[0], seen[1]));
}

test "ошибки объясняются предложением, а не именем" {
    for ([_]anyerror{
        error.AccessDenied,
        error.NoDevice,
        error.FileBusy,
        error.WindowNotFound,
        error.StartupFailed,
    }) |e| {
        const text = explain(e);
        try std.testing.expect(text.len > 20);
        // В объяснении не должно быть латинского имени ошибки.
        try std.testing.expect(std.mem.indexOf(u8, text, @errorName(e)) == null);
    }
}

test "неизвестная ошибка тоже объясняется" {
    try std.testing.expect(explain(error.SomethingOdd).len > 0);
}

test "короткое объяснение помещается в строку" {
    for ([_]anyerror{
        error.NoMicrophone,
        error.MicAccessDenied,
        error.AccessDenied,
        error.FileBusy,
        error.SomethingOdd,
    }) |e| {
        const text = short(e);
        try std.testing.expect(text.len > 0);
        // Для панели и строки состояния: одна короткая строка, без переносов.
        // Считаем буквы, а не байты: в UTF-8 русская буква занимает два байта,
        // и ограничение в байтах молча запретило бы вдвое более короткий текст.
        const letters = try std.unicode.utf8CountCodepoints(text);
        try std.testing.expect(letters <= 44);
        try std.testing.expect(std.mem.indexOfScalar(u8, text, '\n') == null);
    }
}

test "короткое и полное объяснение — про одно и то же" {
    // Оба должны существовать и различаться длиной: длинное объясняет, короткое называет.
    try std.testing.expect(short(error.NoMicrophone).len < explain(error.NoMicrophone).len);
}

test "на английском короткое объяснение тоже помещается в строку" {
    // Место под короткое объяснение одно на оба языка (#100).
    lang.set(.en);
    defer lang.set(.ru);
    for ([_]anyerror{
        error.NoMicrophone,
        error.MicAccessDenied,
        error.NoSpeakers,
        error.AccessDenied,
        error.FileBusy,
        error.FinalizeFailed,
        error.SomethingOdd,
    }) |e| {
        const text = short(e);
        try std.testing.expect(text.len > 0);
        try std.testing.expect(try std.unicode.utf8CountCodepoints(text) <= 44);
        try std.testing.expect(std.mem.indexOfScalar(u8, text, '\n') == null);
        // И объяснение остаётся предложением, а не именем ошибки.
        try std.testing.expect(std.mem.indexOf(u8, explain(e), @errorName(e)) == null);
    }
    try std.testing.expect(!std.mem.eql(u8, short(error.FileBusy), "файл занят другой программой"));
}
