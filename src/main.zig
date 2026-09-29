//! Точка входа zigrec. Пока командная строка: окно записи появится в задаче #18.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const zigrec = @import("zigrec");
/// Есть ли в этой сборке самопроверки и стенды. Выключаются ключом
/// `-Dbenches=false` — для exe, который отдаётся людям: стенды нужны
/// `check.cmd`, а не тому, кто пишет экран. Условие времени компиляции:
/// при `false` ветка не разбирается, и код стендов в exe не попадает.
const benches = @import("build_options").benches;

const usage =
    \\zigrec — рекордер экрана и редактор
    \\
    \\  zigrec                            открыть окно программы (то же, что двойной клик)
    \\  zigrec --version                  версия и дата выпуска
    \\  zigrec --help                     эта справка
    \\        --en | --ru                 язык справки и окон
    \\
    \\  zigrec record ФАЙЛ [ключи]        записать экран в mp4 или GIF
    \\        имя, кончающееся на .gif, даёт петлю вместо видео
    \\        --sec N          сколько секунд писать (по умолчанию 5)
    \\        --fps N          частота кадров (по умолчанию 30)
    \\        --monitor N      номер монитора (по умолчанию 0)
    \\        --area x,y,ш,в   прямоугольник рабочего стола
    \\        --window ТЕКСТ   окно, найденное по части заголовка; область едет за окном
    \\        --follow         область едет за курсором (только с --area)
    \\        --backend auto|dxgi|gdi|wgc  путь захвата; авто — DXGI, а если он молчит
    \\                         полторы секунды, GDI
    \\        --sound          писать звук с микрофона в ту же дорожку
    \\        --system         писать и то, что идёт в колонки (сводится с микрофоном)
    \\        --separate       микрофон и колонки — двумя дорожками, а не одной
    \\        --stop-file ПУТЬ закончить запись, как только появится этот файл;
    \\                         Ctrl+C и закрытие консоли тоже заканчивают запись, не портя файл
    \\        --json           последней строкой — итог в JSON: путь, код, кадры, потери, длительности
    \\  zigrec monitors                   какие есть мониторы
    \\  zigrec windows                    какие есть видимые окна
    \\  zigrec edit [ФАЙЛ]                окно редактора: дорожки, резка, перестановка
    \\  zigrec info ФАЙЛ                  что внутри файла: формат, дорожки, кодеки
    \\        понимает mp4, mov, avi, wav, mp3, ogg, flac, midi
    \\  zigrec verify-mp4 ФАЙЛ            разобрать mp4: боксы, быстрый старт, данные
    \\
    \\  zigrec capture-smoke [N] [dxgi|gdi]
    \\        самопроверка захвата: показать N кадров и прочитать их обратно с экрана
    \\  zigrec encode-smoke ФАЙЛ [N] [--audio]
    \\        самопроверка кодирования: N кадров стенда в mp4 и разбор файла;
    \\        с --audio в файл идёт ещё и звуковая дорожка с известным рисунком
    \\  zigrec mcp [ПОРТ]
    \\        сервер MCP для Claude Code; передаёт просьбы в открытое окно
    \\  zigrec listen-smoke [ПОРТ]
    \\        самопроверка адресов: каждый адрес из списка настроек слушает и отвечает
    \\  zigrec nav-smoke ФАЙЛ [ПРОСЬБ]
    \\        самопроверка навигации: окно не ждёт декодер
    \\  zigrec open-smoke ФАЙЛ
    \\        самопроверка открытия: быстрый путь и медленный дают одно
    \\  zigrec ui-smoke
    \\        самопроверка окна: всё ли поместилось в его рабочую часть
    \\  zigrec mix-smoke ИСХОДНИК.wav СМЕСЬ.wav
    \\        самопроверка громкости: свести с кривой и проверить, что она слышна
    \\  zigrec events-smoke ФАЙЛ.events
    \\        самопроверка слоя событий: записать известный путь курсора и прочитать обратно
    \\  zigrec pan-smoke
    \\        самопроверка автопанорамы: область едет за курсором плавно и не за край
    \\  zigrec export-smoke ИСХОДНИК.mp4 ВЫХОД.mp4 [--offkey|--burn]
    \\        самопроверка экспорта: клип с ключевого кадра — без перекодирования,
    \\        с --offkey — с перекодированием, с --burn — курсор из слоя в кадр;
    \\        длина и кадры сверяются нашим читателем
    \\  zigrec pixel-check ФАЙЛ.bgra Ш В X Y
    \\        есть ли в 5x5 вокруг точки цвета курсора (белый и чёрный) — для кадра от ffmpeg
    \\  zigrec pixel-color ФАЙЛ.bgra Ш В X Y R G B
    \\        того ли цвета точка кадра от ffmpeg (с допуском на сжатие)
    \\  zigrec bench-run [СЕК] [FPS] [ФАЙЛ.mp4] [ШИРИНА ВЫСОТА] [--strict]
    \\        замер себя для сравнения с CamStudio и OBS: процессор, потери,
    \\        размер, резкость; строка таблицы рядом с файлом (.md)
    \\  zigrec capture-rate [СЕК] [dxgi|gdi]
    \\        чистая частота захвата без кодирования при движении на экране
    \\  zigrec stimulus [СЕК]
    \\        окно с бегущей полосой: под ним меряют чужие программы записи
    \\  zigrec keyframes-smoke ФАЙЛ.mp4 СПИСОК.txt
    \\        самопроверка ключевых кадров: наш список против I-кадров ffmpeg
    \\  zigrec clock-smoke
    \\        самопроверка часов плеера: время идёт по отданным в колонки отсчётам
    \\  zigrec devices-smoke
    \\        самопроверка микрофонов: список устройств ввода с именами
    \\  zigrec probe-smoke [СЕК]
    \\        самопроверка пробы: записать СЕК секунд с микрофона и сыграть
    \\  zigrec loopback-smoke
    \\        самопроверка системного звука: сыграть в колонки и поймать через loopback
    \\  zigrec loopback-record ФАЙЛ.mp4 [--separate]
    \\        то же, но сквозь подачу и кодировщик — в настоящий mp4; --separate — микрофон
    \\        и колонки двумя дорожками
    \\  zigrec tracks-check ФАЙЛ N
    \\        сколько в файле звуковых дорожек нашим читателем: должно быть N
    \\  zigrec onset-spacing ФАЙЛ.wav МС
    \\        интервал между двумя всплесками в WAV: сходится ли с ожиданием
    \\  zigrec icons-smoke ЗНАЧКИ.png
    \\        самопроверка значков: все нарисованы, все разные, все в одной картинке
    \\  zigrec window-smoke
    \\        самопроверка захвата окна: окно находится и съёмка едет за ним
    \\  zigrec pause-smoke ФАЙЛ.mp4
    \\        самопроверка паузы записи: на паузе кадры не идут, после неё идут,
    \\        время кадров не уходит назад, пауза не попадает в звук
    \\  zigrec title-smoke
    \\        самопроверка: поток записи читает заголовок окна, не дожидаясь потока окна
    \\  zigrec still-smoke ФАЙЛ.mp4
    \\        самопроверка звука поверх неподвижного экрана: звук не теряется
    \\  zigrec remote-smoke
    \\        самопроверка пульта: подписи влезают, пульт не в кадре
    \\  zigrec hotkey-smoke [СОЧЕТАНИЕ]
    \\        самопроверка сочетания: Windows его принимает
    \\  zigrec gif-write-smoke ФАЙЛ.gif [N]
    \\        самопроверка записи GIF: N эталонных кадров в петлю
    \\  zigrec gif-smoke ФАЙЛ.gif [КАДР.png]
    \\        самопроверка чтения GIF: кадры, выдержки, первый кадр в png
    \\  zigrec recent-smoke ПАПКА
    \\        самопроверка списков недавних: запись, чтение, порядок
    \\  zigrec home-smoke
    \\        самопроверка хранения: Portable и Classic
    \\  zigrec shot-smoke ФАЙЛ.png [НОМЕР]
    \\        самопроверка снимка: эталонный кадр записывается картинкой
    \\  zigrec frame-smoke ФАЙЛ [СЕКУНДЫ] [МАКС_ШИРИНА]
    \\        самопроверка кадра: размер, шаг строки, длина буфера
    \\  zigrec pack-smoke ФАЙЛ.zigrec
    \\        самопроверка архива проекта: собрать, прочитать, сверить
    \\  zigrec project-smoke ФАЙЛ.zrs
    \\        самопроверка файла проекта: записать, прочитать, сверить
    \\  zigrec mcp-smoke [ПОРТ]
    \\        самопроверка сервера: настоящий разговор с окном и сверка ответов
    \\  zigrec motion-smoke [ФАЙЛ.mp4]
    \\        самопроверка волны движения: стенд сам снимает клип с известной
    \\        неподвижной серединой и проверяет, что волна её нашла
    \\  zigrec readme-shot ФАЙЛ.png
    \\        снять главное окно со звуковой волной: стенд сам включает звук,
    \\        играет тон и проверяет, что волна на снимке видна
    \\  zigrec menu-shot ФАЙЛ.png
    \\        снять открытое меню формата: строку соотношений видно только глазами
    \\  zigrec editor-shot ФАЙЛ.png [ВИДЕО]
    \\        снять окно редактора: минимапа, дорожки, кадр — для глаз
    \\  zigrec usage-smoke
    \\        самопроверка справки: русская и английская описывают одни и те же
    \\        команды, ни одна не забыта
    \\  zigrec console-smoke
    \\        самопроверка кодовой страницы: консоль слушает UTF-8 и русские
    \\        буквы выходят целыми
    \\  zigrec seek-time ФАЙЛ [СЕК]
    \\        сколько стоит прыжок указателя на СЕК и чтение звука целиком:
    \\        стенд валится, если окно от такого прыжка замрёт надолго
    \\  zigrec gui-smoke
    \\        самопроверка ярлыка: zigrec-gui.exe открывает окно и НЕ заводит
    \\        консоли — той самой, что мигала чёрным при запуске с рабочего стола
    \\  zigrec click-smoke
    \\        самопроверка двойного клика: запуск без ключей открывает окно,
    \\        консоль не мигает справкой
    \\  zigrec stop-smoke [ПОРТ]
    \\        окно живо, пока «Стоп» закрывает файл (#102): под
    \\        ZIGREC_SLOW_FINISH_MS стучим в окно WM_NULL с таймаутом
    \\  zigrec audio-sync ФАЙЛ.wav
    \\        сверить вынутую дорожку со стендом: уровень и рассинхрон
    \\  zigrec verify-raw ФАЙЛ Ш В
    \\        прочитать таймкоды из распакованного BGRA-потока и сверить порядок
    \\
    \\Коды возврата: 0 — записан, 3 — записан с пропусками (потерь больше 1 %
    \\или файл короче записи), 4 — записан не целиком: источник пропал,
    \\1 — не записан, 2 — неверные ключи.
    \\
    \\
;

/// То же по-английски.
///
/// Двумя текстами, а не парами строк: справка — это один связный лист с
/// колонками и отступами, и собранный из полутора сотен отдельных пар он
/// разъехался бы по ширине на первой же правке. Плата за это — их надо
/// править парой, и за этим следит стенд `usage-smoke`: он сверяет число
/// строк с командами.
const usage_en =
    \\zigrec — screen recorder and editor
    \\
    \\  zigrec                            open the program window (same as a double click)
    \\  zigrec --version                  version and release date
    \\  zigrec --help                     this help
    \\        --en | --ru                 language of this help and of the windows
    \\
    \\  zigrec record FILE [keys]         record the screen into mp4 or GIF
    \\        a name ending in .gif gives a loop instead of video
    \\        --sec N          how many seconds to record (5 by default)
    \\        --fps N          frame rate (30 by default)
    \\        --monitor N      monitor number (0 by default)
    \\        --area x,y,w,h   rectangle of the desktop
    \\        --window TEXT    window found by part of its title; the area follows it
    \\        --follow         the area follows the cursor (only with --area)
    \\        --backend auto|dxgi|gdi|wgc  capture path; auto is DXGI, and GDI if it
    \\                         stays silent
    \\        --sound          record the microphone into the same track
    \\        --system         record what goes to the speakers too (mixed with the mic)
    \\        --separate       microphone and speakers as two tracks, not one
    \\        --stop-file PATH stop recording as soon as this file appears;
    \\                         Ctrl+C and closing the console also finish the file cleanly
    \\        --json           last line is the result as JSON: path, code, frames, drops, durations
    \\  zigrec monitors                   which monitors are there
    \\  zigrec windows                    which visible windows are there
    \\  zigrec edit [FILE]                editor window: tracks, cutting, reordering
    \\  zigrec info FILE                  what is inside the file: format, tracks, codecs
    \\        understands mp4, mov, avi, wav, mp3, ogg, flac, midi
    \\  zigrec verify-mp4 FILE            take an mp4 apart: boxes, fast start, data
    \\
    \\  zigrec capture-smoke [N] [dxgi|gdi]
    \\        capture self-check: show N frames and read them back from the screen
    \\  zigrec encode-smoke FILE [N] [--audio]
    \\        encoding self-check: N bench frames into mp4 and the file taken apart;
    \\        with --audio an audio track with a known shape goes in as well
    \\  zigrec mcp [PORT]
    \\        MCP server for Claude Code; passes requests to the open window
    \\  zigrec listen-smoke [PORT]
    \\        address self-check: every address from the settings listens and answers
    \\  zigrec nav-smoke FILE [REQUESTS]
    \\        navigation self-check: the window does not wait for the decoder
    \\  zigrec open-smoke FILE
    \\        opening self-check: the fast path and the slow one agree
    \\  zigrec ui-smoke
    \\        window self-check: does everything fit into its client area
    \\  zigrec mix-smoke SOURCE.wav MIX.wav
    \\        volume self-check: mix with a curve and check the curve is audible
    \\  zigrec events-smoke FILE.events
    \\        event layer self-check: write a known cursor path and read it back
    \\  zigrec pan-smoke
    \\        auto-pan self-check: the area follows the cursor smoothly and not off the edge
    \\  zigrec export-smoke SOURCE.mp4 OUT.mp4 [--offkey|--burn]
    \\        export self-check: a clip from a key frame goes without re-encoding,
    \\        with --offkey it is re-encoded, with --burn the cursor is burned in;
    \\        length and frames are checked by our own reader
    \\  zigrec pixel-check FILE.bgra W H X Y
    \\        is the cursor colour (white and black) within 5x5 of the point — for an ffmpeg frame
    \\  zigrec pixel-color FILE.bgra W H X Y R G B
    \\        is the frame point of the right colour (with an allowance for compression)
    \\  zigrec bench-run [SEC] [FPS] [FILE.mp4] [WIDTH HEIGHT] [--strict]
    \\        measure ourselves against CamStudio and OBS: processor, drops,
    \\        size, sharpness; a table row next to the file (.md)
    \\  zigrec capture-rate [SEC] [dxgi|gdi]
    \\        pure capture rate without encoding while the screen moves
    \\  zigrec stimulus [SEC]
    \\        a window with a running bar: other recorders are measured under it
    \\  zigrec keyframes-smoke FILE.mp4 LIST.txt
    \\        key frame self-check: our list against the I-frames of ffmpeg
    \\  zigrec clock-smoke
    \\        player clock self-check: time follows the samples given to the speakers
    \\  zigrec devices-smoke
    \\        microphone self-check: the list of input devices with names
    \\  zigrec probe-smoke [SEC]
    \\        probe self-check: record SEC seconds from the microphone and play them
    \\  zigrec loopback-smoke
    \\        system sound self-check: play to the speakers and catch it through loopback
    \\  zigrec loopback-record FILE.mp4 [--separate]
    \\        the same, but through the feed and the encoder — into a real mp4;
    \\        --separate puts microphone and speakers into two tracks
    \\  zigrec tracks-check FILE N
    \\        how many audio tracks our reader finds in the file: it must be N
    \\  zigrec onset-spacing FILE.wav MS
    \\        the gap between two bursts in a WAV: does it match what is expected
    \\  zigrec icons-smoke ICONS.png
    \\        icon self-check: all drawn, all different, all in one picture
    \\  zigrec window-smoke
    \\        window capture self-check: the window is found and the shot follows it
    \\  zigrec pause-smoke FILE.mp4
    \\        recording pause self-check: no frames while paused, frames after it,
    \\        frame time never goes back, the pause does not land in the sound
    \\  zigrec title-smoke
    \\        self-check: the recording thread reads the window title without waiting for the window thread
    \\  zigrec still-smoke FILE.mp4
    \\        self-check of sound over a motionless screen: the sound is not lost
    \\  zigrec remote-smoke
    \\        remote self-check: the labels fit, the remote stays out of frame
    \\  zigrec hotkey-smoke [COMBINATION]
    \\        hotkey self-check: Windows accepts it
    \\  zigrec gif-write-smoke FILE.gif [N]
    \\        GIF writing self-check: N bench frames into a loop
    \\  zigrec gif-smoke FILE.gif [FRAME.png]
    \\        GIF reading self-check: frames, delays, the first frame as png
    \\  zigrec recent-smoke FOLDER
    \\        recent lists self-check: writing, reading, order
    \\  zigrec home-smoke
    \\        storage self-check: Portable and Classic
    \\  zigrec shot-smoke FILE.png [NUMBER]
    \\        snapshot self-check: a bench frame is written out as a picture
    \\  zigrec frame-smoke FILE [SECONDS] [MAX_WIDTH]
    \\        frame self-check: size, row stride, buffer length
    \\  zigrec pack-smoke FILE.zigrec
    \\        project archive self-check: pack it, read it, compare
    \\  zigrec project-smoke FILE.zrs
    \\        project file self-check: write it, read it, compare
    \\  zigrec mcp-smoke [PORT]
    \\        server self-check: a real conversation with the window and its answers checked
    \\  zigrec motion-smoke [FILE.mp4]
    \\        motion wave self-check: the bench films a clip with a known still
    \\        middle and checks that the wave found it
    \\  zigrec readme-shot FILE.png
    \\        shoot the main window with the sound wave: the bench turns sound on,
    \\        plays a tone and checks the wave is visible in the picture
    \\  zigrec menu-shot FILE.png
    \\        shoot the open format menu: the ratio row can only be judged by eye
    \\  zigrec editor-shot FILE.png [VIDEO]
    \\        shoot the editor window: minimap, tracks, picture — for the eyes
    \\  zigrec usage-smoke
    \\        help self-check: the Russian and the English one describe the same
    \\        commands, none forgotten
    \\  zigrec console-smoke
    \\        code page self-check: the console listens in UTF-8 and Russian letters
    \\        come out whole
    \\  zigrec seek-time FILE [SEC]
    \\        what a playhead jump to SEC costs and reading the sound whole:
    \\        the bench fails if such a jump would freeze the window for long
    \\  zigrec gui-smoke
    \\        shortcut self-check: zigrec-gui.exe opens the window and creates NO
    \\        console — the one that used to flash black when started from the desktop
    \\  zigrec click-smoke
    \\        double click self-check: starting with no keys opens the window,
    \\        the console does not flash the help
    \\  zigrec stop-smoke [PORT]
    \\        the window stays alive while «Stop» closes the file (#102): under
    \\        ZIGREC_SLOW_FINISH_MS we knock at the window with WM_NULL and a timeout
    \\  zigrec audio-sync FILE.wav
    \\        check the extracted track against the bench: level and drift
    \\  zigrec verify-raw FILE W H
    \\        read timecodes from a raw BGRA stream and check their order
    \\
    \\Exit codes: 0 — recorded, 3 — recorded with drops (more than 1 % lost
    \\or the file is shorter than the recording), 4 — not recorded in full: the
    \\source disappeared, 1 — not recorded, 2 — bad keys.
    \\
    \\
;

/// Справка на языке, который выбрали.
fn usageText() []const u8 {
    return if (zigrec.lang.get() == .en) usage_en else usage;
}

pub fn main(init: std.process.Init) !void {
    // Консоли надо СКАЗАТЬ, что мы пишем в UTF-8. Русская консоль Windows
    // по умолчанию живёт в cp866, и наши буквы она читает как попало:
    // владелец увидел «╤А╨╡╨║╨╛╤А╨┤╨╡╤А» вместо «рекордер». Ни один байт
    // при этом не портился — их просто разбирали не той таблицей.
    setConsoleUtf8();

    const arena = init.arena.allocator();
    // `--lang ru|en` годится к любой команде и до разбора снимается: язык —
    // дело окон, а не команд, и знать о нём каждой незачем (#100).
    const args = try takeLang(arena, try init.minimal.args.toSlice(arena));

    var buf: [8192]u8 = undefined;
    var file_writer: Io.File.Writer = .init(.stdout(), init.io, &buf);
    const w = &file_writer.interface;

    const cmd: []const u8 = if (args.len > 1) args[1] else "";
    var code: u8 = 0;

    if (args.len <= 1) {
        // Двойной клик по zigrec.exe — это «открой программу», а не «покажи
        // справку»: мигнувшая и закрывшаяся консоль выглядит поломкой.
        // Справка остаётся за `--help`.
        if (ownConsoleAlone()) hideConsole();
        zigrec.ui.runFull(arena, false, false) catch |err| {
            try w.print("окно не открылось: {s}\n", .{@errorName(err)});
            try w.writeAll(usageText());
            code = 1;
        };
    } else if (eq(cmd, "--help") or eq(cmd, "-h")) {
        try w.writeAll(usageText());
    } else if (eq(cmd, "--version") or eq(cmd, "-v")) {
        try w.print("zigrec {s} ({s})\n", .{ zigrec.version.VERSION, zigrec.version.VERSION_DATE });
    } else if (benches and eq(cmd, "capture-smoke")) {
        const frames = argInt(args, 2, 240);
        const backend: zigrec.capture.Backend = if (args.len > 3) blk: {
            if (eq(args[3], "dxgi")) break :blk .dxgi;
            if (eq(args[3], "gdi")) break :blk .gdi;
            break :blk .auto;
        } else .auto;
        code = try captureSmoke(arena, w, frames, backend);
    } else if (benches and eq(cmd, "encode-smoke")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к файлу\n");
            code = 2;
        } else {
            var with_audio = false;
            for (args[2..]) |a| {
                if (eq(a, "--audio")) with_audio = true;
            }
            code = try encodeSmoke(init.io, arena, w, args[2], argInt(args, 3, 120), with_audio);
        }
    } else if (eq(cmd, "edit") or eq(cmd, "редактор")) {
        const path: ?[]const u8 = if (args.len > 2) args[2] else null;
        zigrec.editor.run(arena, path) catch |err| {
            try w.print("редактор не открылся: {s}\n", .{@errorName(err)});
            code = 1;
        };
    } else if (eq(cmd, "info")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к файлу\n");
            code = 2;
        } else {
            code = try fileInfo(init.io, arena, w, args[2]);
        }
    } else if (benches and eq(cmd, "verify-mp4")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к файлу\n");
            code = 2;
        } else {
            code = try verifyMp4(init.io, arena, w, args[2]);
        }
    } else if (benches and eq(cmd, "verify-raw")) {
        if (args.len < 5) {
            try w.writeAll("нужны файл, ширина и высота\n");
            code = 2;
        } else {
            code = try verifyRaw(init.io, arena, w, args[2], argInt(args, 3, 0), argInt(args, 4, 0));
        }
    } else if (eq(cmd, "record")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к файлу\n");
            code = 2;
        } else if (parseRecordArgs(args[3..])) |opt| {
            code = try record(init.io, arena, w, args[2], opt);
        } else |err| {
            try w.print("не разобрать ключи: {s}\n\n", .{explainArgs(err)});
            try w.writeAll(usageText());
            code = zigrec.errors.Outcome.bad_usage.exitCode();
        }
    } else if (eq(cmd, "ui") or eq(cmd, "окно")) {
        var hidden = false;
        var serve = false;
        for (args[2..]) |a| {
            if (eq(a, "--tray")) hidden = true;
            if (eq(a, "--server")) serve = true;
        }
        zigrec.ui.runFull(arena, hidden, serve) catch |err| {
            try w.print("окно не открылось: {s}\n", .{@errorName(err)});
            code = 1;
        };
    } else if (benches and eq(cmd, "animate")) {
        const secs = argInt(args, 2, 10);
        const width = argInt(args, 3, 640);
        const height = argInt(args, 4, 360);
        try w.print("[anim] рисую {d} с в окне {d}x{d} — источник изменений для замера захвата\n", .{ secs, width, height });
        try w.flush();
        const painted = zigrec.smoke.animateOnly(arena, secs, width, height) catch |err| {
            try w.print("[anim] ПРОВАЛ: {s}\n", .{explain(err)});
            return;
        };
        try w.print("[anim] нарисовано кадров {d} ({d:.1} в секунду)\n", .{
            painted,
            @as(f64, @floatFromInt(painted)) / @as(f64, @floatFromInt(@max(secs, 1))),
        });
    } else if (benches and eq(cmd, "audio-check")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к WAV\n");
            code = 2;
        } else {
            const expect: ?f32 = if (args.len > 3) std.fmt.parseFloat(f32, args[3]) catch null else null;
            code = try audioCheck(init.io, arena, w, args[2], expect);
        }
    } else if (eq(cmd, "mcp")) {
        code = try mcpBridge(init.io, arena, argInt(args, 2, zigrec.control.default_port));
    } else if (benches and eq(cmd, "listen-smoke")) {
        code = try listenSmoke(init.io, w, @intCast(argInt(args, 2, 15690)));
    } else if (benches and eq(cmd, "nav-smoke")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к файлу\n");
            code = 2;
        } else {
            code = try navSmoke(init.io, arena, w, args[2], argInt(args, 3, 40));
        }
    } else if (benches and eq(cmd, "open-smoke")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к файлу\n");
            code = 2;
        } else {
            code = try openSmoke(init.io, arena, w, args[2]);
        }
    } else if (benches and eq(cmd, "ui-smoke")) {
        code = try uiSmoke(arena, w);
    } else if (benches and eq(cmd, "mix-smoke")) {
        if (args.len < 4) {
            try w.writeAll("нужны исходник и куда писать смесь\n");
            code = 2;
        } else {
            code = try mixSmoke(init.io, arena, w, args[2], args[3]);
        }
    } else if (benches and eq(cmd, "loopback-smoke")) {
        code = try loopbackSmoke(arena, w);
    } else if (benches and eq(cmd, "loopback-record")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к mp4\n");
            code = 2;
        } else {
            const separate = args.len > 3 and eq(args[3], "--separate");
            code = try loopbackRecord(init.io, arena, w, args[2], separate);
        }
    } else if (benches and eq(cmd, "tracks-check")) {
        if (args.len < 4) {
            try w.writeAll("нужны путь к файлу и сколько ждём звуковых дорожек\n");
            code = 2;
        } else {
            code = try tracksCheck(init.io, arena, w, args[2], argInt(args, 3, 1));
        }
    } else if (benches and eq(cmd, "onset-spacing")) {
        if (args.len < 4) {
            try w.writeAll("нужны путь к WAV и ожидаемый интервал в мс\n");
            code = 2;
        } else {
            code = try onsetSpacing(init.io, arena, w, args[2], argInt(args, 3, 1000));
        }
    } else if (benches and eq(cmd, "icons-smoke")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к PNG\n");
            code = 2;
        } else {
            code = try iconsSmoke(init.io, arena, w, args[2]);
        }
    } else if (benches and eq(cmd, "window-smoke")) {
        code = try windowSmoke(init.io, w);
    } else if (benches and eq(cmd, "pause-smoke")) {
        code = try pauseSmoke(arena, w, if (args.len > 2) args[2] else ".check\\pause.mp4");
    } else if (benches and eq(cmd, "title-smoke")) {
        code = try titleSmoke(w);
    } else if (benches and eq(cmd, "still-smoke")) {
        code = try stillSmoke(arena, w, if (args.len > 2) args[2] else ".check\\still.mp4");
    } else if (benches and eq(cmd, "remote-smoke")) {
        code = try remoteSmoke(w);
    } else if (benches and eq(cmd, "hotkey-smoke")) {
        code = try hotkeySmoke(w, if (args.len > 2) args[2] else zigrec.hotkey.default_text);
    } else if (benches and eq(cmd, "gif-write-smoke")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к GIF\n");
            code = 2;
        } else {
            code = try gifWriteSmoke(init.io, arena, w, args[2], argInt(args, 3, 12));
        }
    } else if (benches and eq(cmd, "gif-smoke")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к GIF\n");
            code = 2;
        } else {
            code = try gifSmoke(init.io, arena, w, args[2], if (args.len > 3) args[3] else null);
        }
    } else if (benches and eq(cmd, "recent-smoke")) {
        if (args.len < 3) {
            try w.writeAll("нужна папка\n");
            code = 2;
        } else {
            code = try recentSmoke(init.io, arena, w, args[2]);
        }
    } else if (benches and eq(cmd, "home-smoke")) {
        code = try homeSmoke(w);
    } else if (benches and eq(cmd, "shot-smoke")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к картинке\n");
            code = 2;
        } else {
            code = try shotSmoke(init.io, arena, w, args[2], argInt(args, 3, 7));
        }
    } else if (benches and eq(cmd, "frame-smoke")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к файлу\n");
            code = 2;
        } else {
            code = try frameSmoke(arena, w, args[2], argInt(args, 3, 1), argInt(args, 4, 0));
        }
    } else if (benches and eq(cmd, "pack-smoke")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к архиву\n");
            code = 2;
        } else {
            code = try packSmoke(init.io, arena, w, args[2]);
        }
    } else if (benches and eq(cmd, "project-smoke")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к файлу проекта\n");
            code = 2;
        } else {
            code = try projectSmoke(init.io, arena, w, args[2]);
        }
    } else if (benches and eq(cmd, "motion-smoke")) {
        code = try motionSmoke(init.io, arena, w, if (args.len > 2) args[2] else ".check\\motion.mp4");
    } else if (benches and eq(cmd, "readme-shot")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к png\n");
            code = 2;
        } else {
            code = try readmeShot(arena, w, args[2], argInt(args, 3, 0));
        }
    } else if (benches and eq(cmd, "menu-shot")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к png\n");
            code = 2;
        } else {
            code = try menuShot(arena, w, args[2], argInt(args, 3, 99));
        }
    } else if (benches and eq(cmd, "editor-shot")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к png\n");
            code = 2;
        } else {
            code = try editorShot(arena, w, args[2], if (args.len > 3) args[3] else null, argInt(args, 4, 0));
        }
    } else if (benches and eq(cmd, "usage-smoke")) {
        code = try usageSmoke(w);
    } else if (benches and eq(cmd, "console-smoke")) {
        code = try consoleSmoke(w);
    } else if (benches and eq(cmd, "seek-time")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к файлу\n");
            code = 2;
        } else {
            code = try seekTime(arena, w, args[2], argInt(args, 3, 240));
        }
    } else if (benches and eq(cmd, "gui-smoke")) {
        code = try guiSmoke(w);
    } else if (benches and eq(cmd, "click-smoke")) {
        code = try clickSmoke(init.io, arena, w);
    } else if (benches and eq(cmd, "stop-smoke")) {
        code = try stopSmoke(arena, w, argInt(args, 2, zigrec.control.default_port));
    } else if (benches and eq(cmd, "mcp-smoke")) {
        code = try mcpSmoke(arena, w, argInt(args, 2, zigrec.control.default_port));
    } else if (benches and eq(cmd, "audio-sync")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к WAV\n");
            code = 2;
        } else {
            code = try audioSync(init.io, arena, w, args[2]);
        }
    } else if (eq(cmd, "mic")) {
        code = try micCheck(w, argInt(args, 2, 5));
    } else if (benches and eq(cmd, "stimulus")) {
        // Раздражитель сам по себе — под ним меряют чужие программы записи.
        const seconds = argInt(args, 2, 30);
        var stim = zigrec.stimulus.Stimulus{};
        if (stim.start(.{})) |_| {
            try w.print("[stimulus] окно с бегущей полосой на {d} с — пора запускать запись в другой программе\n", .{seconds});
            try w.flush();
            zigrec.win32.c.Sleep(seconds * 1000);
            stim.stop();
            try w.print("[stimulus] перерисовок {d}\n", .{stim.repaints()});
        } else |err| {
            try w.print("[stimulus] не поднялся: {s}\n", .{@errorName(err)});
            code = 1;
        }
    } else if (benches and eq(cmd, "capture-rate")) {
        code = try captureRate(w, argInt(args, 2, 3), if (args.len > 3 and eq(args[3], "gdi")) .gdi else .dxgi, argInt(args, 4, 0));
    } else if (benches and eq(cmd, "bench-run")) {
        code = try benchRun(init.io, arena, w, argInt(args, 2, 10), argInt(args, 3, 60), if (args.len > 4) args[4] else ".check\\bench.mp4", argInt(args, 5, 1920), argInt(args, 6, 1080), hasFlag(args, "--strict"));
    } else if (benches and eq(cmd, "pixel-color")) {
        if (args.len < 10) {
            try w.writeAll("нужны: файл BGRA, ширина, высота, x, y, R, G, B\n");
            code = 2;
        } else {
            code = try pixelColor(init.io, arena, w, args[2], argInt(args, 3, 0), argInt(args, 4, 0), argInt(args, 5, 0), argInt(args, 6, 0), argInt(args, 7, 0), argInt(args, 8, 0), argInt(args, 9, 0));
        }
    } else if (benches and eq(cmd, "pixel-check")) {
        if (args.len < 7) {
            try w.writeAll("нужны: файл BGRA, ширина, высота, x, y\n");
            code = 2;
        } else {
            code = try pixelCheck(init.io, arena, w, args[2], argInt(args, 3, 0), argInt(args, 4, 0), argInt(args, 5, 0), argInt(args, 6, 0));
        }
    } else if (benches and eq(cmd, "events-smoke")) {
        if (args.len < 3) {
            try w.writeAll("нужен путь к файлу .events\n");
            code = 2;
        } else {
            code = try eventsSmoke(init.io, arena, w, args[2]);
        }
    } else if (benches and eq(cmd, "pan-smoke")) {
        code = try panSmoke(w);
    } else if (benches and eq(cmd, "export-smoke")) {
        if (args.len < 4) {
            try w.writeAll("нужны исходник mp4 и выходной файл\n");
            code = 2;
        } else {
            code = try exportSmoke(arena, w, args[2], args[3], args.len > 4 and eq(args[4], "--offkey"), args.len > 4 and eq(args[4], "--burn"), args.len > 4 and eq(args[4], "--annot"));
        }
    } else if (benches and eq(cmd, "keyframes-smoke")) {
        if (args.len < 4) {
            try w.writeAll("нужны путь к mp4 и файл со списком I-кадров от ffmpeg\n");
            code = 2;
        } else {
            code = try keyframesSmoke(arena, w, args[2], args[3]);
        }
    } else if (benches and eq(cmd, "clock-smoke")) {
        code = try clockSmoke(w);
    } else if (benches and eq(cmd, "devices-smoke")) {
        code = try devicesSmoke(w);
    } else if (benches and eq(cmd, "probe-smoke")) {
        code = try probeSmoke(arena, w, argInt(args, 2, 1));
    } else if (eq(cmd, "monitors")) {
        code = try listMonitors(arena, w);
    } else if (eq(cmd, "windows")) {
        code = try listWindows(w);
    } else {
        try w.print("неизвестная команда: {s}\n\n", .{cmd});
        try w.writeAll(usageText());
        if (!benches) try w.writeAll("В этой сборке самопроверок и стендов нет (-Dbenches=false): команды *-smoke,\nbench-run и проверочные не работают. Полная сборка: zig build.\n");
        code = 2;
    }

    try w.flush();
    if (code != 0) std.process.exit(code);
}

/// Волна движения (#134) — самопроверка на своём клипе.
///
/// Клип делает сам стенд: сорок кадров бегущей картинки, десять одинаковых
/// (рука на буксировке замерла), снова сорок бегущих. Волна обязана найти
/// ровно эту неподвижную середину — не «примерно там», а те самые кадры.
/// Проверять волну на живой записи нельзя: в ней неизвестно, где рывок.
/// Короткий клип для стенда: две секунды бегущего номера кадра.
fn makeClip(allocator: std.mem.Allocator, w: anytype, path: []const u8) !void {
    const bench = zigrec.testbench;
    const width: u32 = 384;
    const height: u32 = 256;
    const fps: u32 = 30;
    const screen = try bench.Screen.init(width, height, fps);
    const buf = try allocator.alloc(u8, screen.frameBytes());
    defer allocator.free(buf);

    var enc = try zigrec.encode.Writer.create(path, width, height, .{ .fps = fps, .preset = .max });
    errdefer enc.abort();
    const frame_ns: u64 = std.time.ns_per_s / fps;
    var made: u32 = 0;
    while (made < fps * 2) : (made += 1) {
        try screen.render(buf, made + 1);
        try enc.writeFrame(buf, screen.width * 4, made * frame_ns);
    }
    _ = try enc.finish();
    try w.print("[seek] клипа не было — сделал свой: {s}\n", .{path});
}

/// Самопроверка кодовой страницы консоли.
///
/// Проверяем ДВЕ разные вещи, и обе нужны: что мы выставили страницу (иначе
/// правка просто не сработала) и что наша строка осталась целой в байтах
/// (иначе беда была бы не в консоли, а в самой строке). Как выглядят буквы
/// на экране, стенд знать не может — шрифт консоли не наше дело.
const setWindowPosZ = @extern(
    *const fn (zigrec.win32.c.HWND, usize, i32, i32, i32, i32, zigrec.win32.c.UINT) callconv(.winapi) zigrec.win32.c.BOOL,
    .{ .name = "SetWindowPos" },
);

/// Самопроверка ярлыка: окно открывается, консоль не заводится.
///
/// Жалоба владельца: «нажимаю на иконку — открывается консоль и быстро
/// закрывается, и дальше я вижу GUI».
///
/// **Проверяем признак в самом exe, а не поведение окон.** Консоль заводит
/// Windows по полю «подсистема» в заголовке файла, ещё до первой нашей
/// строки. Первый заход стенда искал окно консоли среди окон процесса — и
/// не нашёл ни у кого: окном консоли владеет conhost.exe, а не мы. Стенд
/// при этом зеленел, ничего не проверяя. Поле в заголовке врать не может.
///
/// Читаем оба exe: у оконного должно быть 2 (GUI), у консольного 3. Вторая
/// половина не для красоты — без неё «у оконного 2» ничего не значило бы:
/// сломанное чтение молчало бы одинаково про оба.
fn guiSmoke(w: anytype) !u8 {
    const c = zigrec.win32.c;
    const class = std.unicode.utf8ToUtf16LeStringLiteral("ZigRecMain");

    var exe_w: [std.fs.max_path_bytes]u16 = undefined;
    const exe_len = c.GetModuleFileNameW(null, &exe_w, exe_w.len);
    if (exe_len == 0) {
        try w.writeAll("[gui] ПРОВАЛ: не узнать собственный путь\n");
        return 1;
    }
    var path_w: [std.fs.max_path_bytes]u16 = undefined;
    const cut = lastSlash(exe_w[0..exe_len]);
    @memcpy(path_w[0..cut], exe_w[0..cut]);
    const name = std.unicode.utf8ToUtf16LeStringLiteral("\\zigrec-gui.exe");
    @memcpy(path_w[cut .. cut + name.len], name);
    path_w[cut + name.len] = 0;

    var dir_utf8: [std.fs.max_path_bytes]u8 = undefined;
    const dir_n = std.unicode.utf16LeToUtf8(&dir_utf8, exe_w[0..cut]) catch 0;
    var gui_path: [std.fs.max_path_bytes]u8 = undefined;
    const gui_name = "\\zigrec-gui.exe";
    @memcpy(gui_path[0..dir_n], dir_utf8[0..dir_n]);
    @memcpy(gui_path[dir_n .. dir_n + gui_name.len], gui_name);
    var console_path: [std.fs.max_path_bytes]u8 = undefined;
    const console_n = std.unicode.utf16LeToUtf8(&console_path, exe_w[0..exe_len]) catch 0;

    var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const gui_kind = subsystemOf(io, gui_path[0 .. dir_n + gui_name.len]) catch |err| {
        try w.print("[gui] ПРОВАЛ: не прочитать zigrec-gui.exe: {s}\n", .{@errorName(err)});
        return 1;
    };
    const console_kind = subsystemOf(io, console_path[0..console_n]) catch |err| {
        try w.print("[gui] ПРОВАЛ: не прочитать zigrec.exe: {s}\n", .{@errorName(err)});
        return 1;
    };
    try w.print("[gui] подсистема: zigrec-gui.exe {d}, zigrec.exe {d} (2 — окно, 3 — консоль)\n", .{ gui_kind, console_kind });

    if (console_kind != 3) {
        try w.writeAll("[gui] ПРОВАЛ: у zigrec.exe не признак консоли — читаем не то поле\n");
        return 1;
    }
    if (gui_kind != 2) {
        try w.writeAll("[gui] ПРОВАЛ: zigrec-gui.exe помечен как консольный — консоль будет мигать\n");
        return 1;
    }

    // И он действительно открывает окно, а не просто «не мигает».
    if (c.FindWindowW(class, null) != null) {
        try w.writeAll("[gui] ПРОВАЛ: окно уже открыто — закройте его\n");
        return 1;
    }
    var si = std.mem.zeroes(c.STARTUPINFOW);
    si.cb = @sizeOf(c.STARTUPINFOW);
    var pi = std.mem.zeroes(c.PROCESS_INFORMATION);
    if (c.CreateProcessW(&path_w, null, null, null, 0, 0, null, null, &si, &pi) == 0) {
        try w.print("[gui] ПРОВАЛ: zigrec-gui.exe не запустился (ошибка {d})\n", .{c.GetLastError()});
        return 1;
    }
    defer {
        _ = c.CloseHandle(pi.hThread);
        _ = c.CloseHandle(pi.hProcess);
    }
    var waited: u32 = 0;
    var found: ?c.HWND = null;
    while (waited < 100) : (waited += 1) {
        if (c.FindWindowW(class, null)) |h| {
            if (c.IsWindowVisible(h) != 0) {
                found = h;
                break;
            }
        }
        c.Sleep(100);
    }
    const hwnd = found orelse {
        _ = c.TerminateProcess(pi.hProcess, 1);
        try w.writeAll("[gui] ПРОВАЛ: окно так и не открылось\n");
        return 1;
    };
    _ = c.PostMessageW(hwnd, c.WM_CLOSE, 0, 0);
    _ = c.WaitForSingleObject(pi.hProcess, 3000);
    _ = c.TerminateProcess(pi.hProcess, 0);

    try w.writeAll("[gui] ЯРЛЫК ОТКРЫВАЕТ ОКНО БЕЗ КОНСОЛИ\n");
    return 0;
}

/// Поле «подсистема» из заголовка PE: 2 — окно, 3 — консоль.
///
/// Читаем ровно два числа и по смещениям, записанным в самом файле:
/// 0x3C хранит, где начинается заголовок PE, а подсистема лежит в 92 байтах
/// от его начала — одинаково и для 32, и для 64 бит.
fn subsystemOf(io: std.Io, path: []const u8) !u16 {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var at: [4]u8 = undefined;
    _ = try file.readPositionalAll(io, &at, 0x3C);
    const pe = std.mem.readInt(u32, &at, .little);

    var kind: [2]u8 = undefined;
    _ = try file.readPositionalAll(io, &kind, pe + 92);
    return std.mem.readInt(u16, &kind, .little);
}

fn lastSlash(text: []const u16) usize {
    var i: usize = text.len;
    while (i > 0) : (i -= 1) {
        if (text[i - 1] == '\\' or text[i - 1] == '/') return i - 1;
    }
    return text.len;
}

/// Снять главное окно со звуковой волной — для страницы проекта.
///
/// Владелец: «на главной странице я вижу старую версию и хочу видеть
/// звуковую волну с микрофона». Снимок в README устаревает молча: окно
/// меняется каждый выпуск, а картинка остаётся с версией годичной давности
/// и без того, что появилось. Поэтому снимок делает стенд, а не рука:
/// повторить его можно одной командой.
///
/// Стенд сам ставит окно в нужное состояние (включает звук), сам даёт ему
/// что показывать (играет тон в колонки, микрофон его слышит) и сам
/// проверяет, что волна на снимке ЕСТЬ. Без последней проверки картинка с
/// пустым полем выглядела бы «снято успешно».
fn readmeShot(allocator: std.mem.Allocator, w: anytype, path: []const u8, clicks: u64) !u8 {
    const c = zigrec.win32.c;
    const class = std.unicode.utf8ToUtf16LeStringLiteral("ZigRecMain");

    if (c.FindWindowW(class, null) != null) {
        try w.writeAll("[shot] ПРОВАЛ: окно уже открыто — закройте его, стенд не поймёт, чьё оно\n");
        return 1;
    }

    var exe_w: [std.fs.max_path_bytes]u16 = undefined;
    const exe_len = c.GetModuleFileNameW(null, &exe_w, exe_w.len);
    if (exe_len == 0 or exe_len >= exe_w.len) {
        try w.writeAll("[shot] ПРОВАЛ: не узнать собственный путь\n");
        return 1;
    }
    exe_w[exe_len] = 0;

    var si = std.mem.zeroes(c.STARTUPINFOW);
    si.cb = @sizeOf(c.STARTUPINFOW);
    var pi = std.mem.zeroes(c.PROCESS_INFORMATION);
    // Окно для страницы проекта снимаем по-русски: README написан
    // по-русски, и окно на снимке должно быть тем же, что у читателя.
    // Язык берётся из настроек, поэтому просим его ключом явно.
    var cmd_w: [std.fs.max_path_bytes + 16]u16 = undefined;
    const quote: u16 = '"';
    cmd_w[0] = quote;
    @memcpy(cmd_w[1 .. 1 + exe_len], exe_w[0..exe_len]);
    cmd_w[1 + exe_len] = quote;
    const tail = std.unicode.utf8ToUtf16LeStringLiteral(" --ru");
    @memcpy(cmd_w[2 + exe_len .. 2 + exe_len + tail.len], tail);
    cmd_w[2 + exe_len + tail.len] = 0;

    if (c.CreateProcessW(&exe_w, &cmd_w, null, null, 0, c.CREATE_NEW_CONSOLE, null, null, &si, &pi) == 0) {
        try w.print("[shot] ПРОВАЛ: не запуститься самому (ошибка {d})\n", .{c.GetLastError()});
        return 1;
    }
    defer {
        _ = c.CloseHandle(pi.hThread);
        _ = c.CloseHandle(pi.hProcess);
    }

    var waited: u32 = 0;
    var found: ?c.HWND = null;
    while (waited < 100) : (waited += 1) {
        if (c.FindWindowW(class, null)) |h| {
            if (c.IsWindowVisible(h) != 0) {
                found = h;
                break;
            }
        }
        c.Sleep(100);
    }
    const hwnd = found orelse {
        _ = c.TerminateProcess(pi.hProcess, 1);
        try w.writeAll("[shot] ПРОВАЛ: окно так и не открылось\n");
        return 1;
    };
    defer {
        _ = c.PostMessageW(hwnd, c.WM_CLOSE, 0, 0);
        _ = c.WaitForSingleObject(pi.hProcess, 3000);
        _ = c.TerminateProcess(pi.hProcess, 0);
    }

    // Включаем звук так же, как это делает человек: ставим галочку и
    // говорим окну, что по ней щёлкнули. Дёргать внутренности чужого
    // процесса нечем, да и незачем — путь через окно и есть настоящий.
    const check = c.GetDlgItem(hwnd, zigrec.ui.id_sound) orelse {
        try w.writeAll("[shot] ПРОВАЛ: не нашлась галочка звука\n");
        return 1;
    };
    _ = c.SendMessageW(check, c.BM_SETCHECK, 1, 0);
    _ = c.SendMessageW(hwnd, c.WM_COMMAND, @as(c.WPARAM, zigrec.ui.id_sound), @bitCast(@intFromPtr(check)));

    // Щелчки по полю звука: каждый меняет взгляд (волна → спектрограмма →
    // огибающая). Так стенд снимает любой из трёх и заодно показывает, что
    // они рисуются и не роняют окно.
    if (clicks > 0) {
        const wave_box = zigrec.ui.waveArea();
        const at_x: i32 = @divTrunc(wave_box.left + wave_box.right, 2);
        const at_y: i32 = @divTrunc(wave_box.top + wave_box.bottom, 2);
        const point: c.LPARAM = @as(c.LPARAM, at_x & 0xFFFF) | (@as(c.LPARAM, at_y & 0xFFFF) << 16);
        var done: u64 = 0;
        while (done < clicks) : (done += 1) {
            _ = c.SendMessageW(hwnd, c.WM_LBUTTONDOWN, 0, point);
            c.Sleep(150);
        }
    }

    // Тон в колонки: микрофон в комнате его слышит, и волна перестаёт быть
    // прямой линией. Без звука снимок вышел бы честным, но бесполезным.
    // Тише обычного: в упор громкий тон упирает волну в край поля.
    var tone = Tone{ .amplitude = 0.6, .breath_hz = 9 };
    tone.start();
    defer tone.finish();

    // Поднимаем «Усиление» — тот самый ползунок, что растягивает картинку,
    // а не вход. Тон из колонок доходит до микрофона тихим (−22 дБ), и на
    // шкале в полсотни точек это почти прямая линия; ползунок за тем и
    // сделан, чтобы тихое было видно. Числа на снимке при этом честные:
    // окно само пишет и уровень в децибелах, и во сколько раз растянуто.
    if (c.GetDlgItem(hwnd, zigrec.ui.id_gain_slider)) |slider| {
        _ = c.SendMessageW(slider, c.WM_USER + 5, 1, 6);
        _ = c.SendMessageW(hwnd, c.WM_HSCROLL, 0, @bitCast(@intFromPtr(slider)));
    }
    c.Sleep(1500);

    // Снимаем окно целиком, вместе с рамкой.
    // Границу берём у DWM, а не `GetWindowRect`: тот отдаёт окно вместе с
    // невидимой рамкой тени, и по краям снимка оказывается полоса чужого
    // рабочего стола. Это уже разобрано в `capture/source.zig`, оттуда
    // готовый ответ и берём.
    const area = zigrec.source.windowArea(hwnd) catch {
        try w.writeAll("[shot] ПРОВАЛ: не узнать границы окна\n");
        return 1;
    };
    const rc = c.RECT{
        .left = area.x,
        .top = area.y,
        .right = area.x + @as(i32, @intCast(area.width)),
        .bottom = area.y + @as(i32, @intCast(area.height)),
    };
    const width: u32 = area.width;
    const height: u32 = area.height;

    const screen_dc = c.GetDC(null);
    defer _ = c.ReleaseDC(null, screen_dc);
    const mem_dc = c.CreateCompatibleDC(screen_dc);
    defer _ = c.DeleteDC(mem_dc);

    var bmi = std.mem.zeroes(c.BITMAPINFO);
    bmi.bmiHeader.biSize = @sizeOf(c.BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = @intCast(width);
    // Отрицательная высота — строки сверху вниз, как их ждёт наш писатель.
    bmi.bmiHeader.biHeight = -@as(i32, @intCast(height));
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = c.BI_RGB;

    var bits: ?*anyopaque = null;
    const dib = c.CreateDIBSection(mem_dc, &bmi, c.DIB_RGB_COLORS, &bits, null, 0) orelse {
        try w.writeAll("[shot] ПРОВАЛ: не выделилась картинка\n");
        return 1;
    };
    defer _ = c.DeleteObject(dib);
    const old = c.SelectObject(mem_dc, dib);
    defer _ = c.SelectObject(mem_dc, old);

    // Снимаем С ЭКРАНА, а не просьбой к окну нарисовать себя.
    //
    // `PrintWindow` просит окно перерисоваться — и осциллографа на снимке
    // не оказывалось вовсе: волна рисуется по таймеру и переносится готовой
    // картинкой, а не в ответ на просьбу перерисоваться. На снимке выходила
    // прямая зелёная черта, и это читалось как «микрофон молчит», хотя
    // микрофон был ни при чём. С экрана берётся ровно то, что видит человек.
    // Поднять окно поверх всех — и не просьбой, а признаком «поверх всех».
    // `SetForegroundWindow` из чужого процесса Windows выполнять не обязана,
    // и первый заход снял чужое окно, лежавшее сверху: на снимке оказалась
    // посторонняя программа, а проверка «зелёного» приняла её ячейки за
    // волну и сказала «готово».
    // `HWND_TOPMOST` — это −1, а не адрес: в поле-указатель его не положить,
    // Zig падает на проверке выравнивания. Та же ловушка уже описана в
    // `capture/frame_overlay.zig`, и решение то же: объявить `SetWindowPos`
    // с целым вторым параметром, как оно и есть на уровне вызова Windows.
    _ = setWindowPosZ(hwnd, @bitCast(@as(isize, -1)), 0, 0, 0, 0, c.SWP_NOMOVE | c.SWP_NOSIZE | c.SWP_SHOWWINDOW);
    _ = c.SetForegroundWindow(hwnd);
    c.Sleep(500);
    if (c.BitBlt(mem_dc, 0, 0, @intCast(width), @intCast(height), screen_dc, rc.left, rc.top, c.SRCCOPY) == 0) {
        try w.writeAll("[shot] ПРОВАЛ: не снялось с экрана\n");
        return 1;
    }

    const stride: usize = @as(usize, width) * 4;
    const raw: [*]u8 = @ptrCast(bits.?);
    const pixels = raw[0 .. stride * height];

    // Волну ищем ТОЛЬКО в её поле, а не по всему снимку.
    //
    // По всему снимку считать нельзя: зелёного хватает и в чужих окнах, и
    // первый заход на этом попался — снял постороннюю программу и сказал
    // «готово». Поле осциллографа живёт в клиентских точках, поэтому
    // переводим их в точки снимка: рамка и заголовок окна дают сдвиг.
    var client_origin = c.POINT{ .x = 0, .y = 0 };
    _ = c.ClientToScreen(hwnd, &client_origin);
    const dx = client_origin.x - rc.left;
    const dy = client_origin.y - rc.top;
    const wave = zigrec.ui.waveArea();

    var green: usize = 0;
    // Тёмные точки — это фон поля осциллограммы: по ним видно, что поле
    // нарисовано, даже когда микрофон молчит.
    var dark: usize = 0;
    var y: i32 = wave.top + dy;
    while (y < wave.bottom + dy) : (y += 1) {
        if (y < 0 or y >= @as(i32, @intCast(height))) continue;
        var x: i32 = wave.left + dx;
        while (x < wave.right + dx) : (x += 1) {
            if (x < 0 or x >= @as(i32, @intCast(width))) continue;
            const at = @as(usize, @intCast(y)) * stride + @as(usize, @intCast(x)) * 4;
            const b = pixels[at];
            const g = pixels[at + 1];
            const r = pixels[at + 2];
            if (g > 140 and r < 120 and b < 120) green += 1;
            if (r < 70 and g < 70 and b < 70) dark += 1;
        }
    }
    try w.print("[shot] окно {d}x{d}, точек волны {d}\n", .{ width, height, green });

    const png = zigrec.png.fromBgra(allocator, pixels, width, height, stride) catch |err| {
        try w.print("[shot] ПРОВАЛ: картинка не собралась: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(png);
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = png });

    try w.print("[shot] записан {s}, {d} байт\n", .{ path, png.len });

    // Триста точек — это заведомо больше, чем даст одна прямая линия
    // (поле шириной под четыреста точек, линия в две точки толщиной даёт
    // около восьмисот, но она рисуется ТОЛЬКО когда звук включён и идёт).
    // Со щелчками стенд проверяет другое — что круг взглядов замкнулся и
    // поле по-прежнему рисуется. Требовать при этом волну нельзя: в общем
    // прогоне соседний шаг может держать микрофон, и тогда поле честно
    // показывает «микрофон занят», а не волну. Проверяем, что поле тёмное,
    // то есть осциллограмма на месте.
    if (clicks > 0) {
        if (dark < 1000) {
            try w.writeAll("[shot] ПРОВАЛ: поле звука не нарисовано — круг взглядов не замкнулся\n");
            return 1;
        }
        try w.print("[shot] круг взглядов замкнулся: поле на месте ({d} тёмных точек)\n", .{dark});
        return 0;
    }

    if (green < 300) {
        try w.writeAll("[shot] ПРОВАЛ: волны на снимке нет — звук не включился или микрофон молчит\n");
        return 1;
    }
    try w.writeAll("[shot] СНИМОК С ВОЛНОЙ ГОТОВ\n");
    return 0;
}

/// Сколько ячеек в строке соотношений.
const aspect_cells: usize = zigrec.aspect.ratios.len;

/// Настоящее нажатие мыши там, где стоит курсор.
fn mouseClick() void {
    const c = zigrec.win32.c;
    var down = std.mem.zeroes(c.INPUT);
    down.type = c.INPUT_MOUSE;
    down.unnamed_0.mi.dwFlags = c.MOUSEEVENTF_LEFTDOWN;
    var up = std.mem.zeroes(c.INPUT);
    up.type = c.INPUT_MOUSE;
    up.unnamed_0.mi.dwFlags = c.MOUSEEVENTF_LEFTUP;
    _ = c.SendInput(1, &down, @sizeOf(c.INPUT));
    c.Sleep(60);
    _ = c.SendInput(1, &up, @sizeOf(c.INPUT));
}

/// Снять открытое меню формата.
///
/// Меню — отдельное окно поверх нашего, и рисуем мы в нём строку
/// соотношений своим кодом. Проверить её можно только глазами, а глазам
/// нужен снимок, который получается одинаково каждый раз.
///
/// Нажатие посылаем `PostMessageW`, а не `SendMessageW`: меню держит поток
/// окна внутри себя, пока не закроется, и `SendMessage` заморозил бы вместе
/// с ним сам стенд.
fn menuShot(allocator: std.mem.Allocator, w: anytype, path: []const u8, cell: u64) !u8 {
    const c = zigrec.win32.c;
    const class = std.unicode.utf8ToUtf16LeStringLiteral("ZigRecMain");

    if (c.FindWindowW(class, null) != null) {
        try w.writeAll("[menu] ПРОВАЛ: окно уже открыто — закройте его\n");
        return 1;
    }

    var exe_w: [std.fs.max_path_bytes]u16 = undefined;
    const exe_len = c.GetModuleFileNameW(null, &exe_w, exe_w.len);
    if (exe_len == 0) return 1;
    var line: [std.fs.max_path_bytes * 2]u8 = undefined;
    var exe_utf8: [std.fs.max_path_bytes]u8 = undefined;
    const exe_n = std.unicode.utf16LeToUtf8(&exe_utf8, exe_w[0..exe_len]) catch 0;
    const cmd_utf8 = std.fmt.bufPrint(&line, "\"{s}\" --ru", .{exe_utf8[0..exe_n]}) catch return 1;
    var cmd_w: [std.fs.max_path_bytes * 2]u16 = undefined;
    const cmd_n = std.unicode.utf8ToUtf16Le(&cmd_w, cmd_utf8) catch return 1;
    cmd_w[cmd_n] = 0;

    var si = std.mem.zeroes(c.STARTUPINFOW);
    si.cb = @sizeOf(c.STARTUPINFOW);
    var pi = std.mem.zeroes(c.PROCESS_INFORMATION);
    if (c.CreateProcessW(null, &cmd_w, null, null, 0, c.CREATE_NEW_CONSOLE, null, null, &si, &pi) == 0) {
        try w.writeAll("[menu] ПРОВАЛ: окно не запустилось\n");
        return 1;
    }
    defer {
        _ = c.CloseHandle(pi.hThread);
        _ = c.CloseHandle(pi.hProcess);
    }

    var waited: u32 = 0;
    var found: ?c.HWND = null;
    while (waited < 100) : (waited += 1) {
        if (c.FindWindowW(class, null)) |h| {
            if (c.IsWindowVisible(h) != 0) {
                found = h;
                break;
            }
        }
        c.Sleep(100);
    }
    const hwnd = found orelse {
        _ = c.TerminateProcess(pi.hProcess, 1);
        try w.writeAll("[menu] ПРОВАЛ: окно не открылось\n");
        return 1;
    };
    defer {
        _ = c.PostMessageW(hwnd, c.WM_CLOSE, 0, 0);
        _ = c.WaitForSingleObject(pi.hProcess, 3000);
        _ = c.TerminateProcess(pi.hProcess, 0);
    }

    _ = setWindowPosZ(hwnd, @bitCast(@as(isize, -1)), 0, 0, 0, 0, c.SWP_NOMOVE | c.SWP_NOSIZE | c.SWP_SHOWWINDOW);
    _ = c.SetForegroundWindow(hwnd);
    c.Sleep(400);

    // Курсор — на стрелку в кнопке «Записать область»: окно само смотрит,
    // куда ткнули, и по стрелке открывает меню формата.
    const btn = c.GetDlgItem(hwnd, zigrec.ui.id_area_rec) orelse {
        try w.writeAll("[menu] ПРОВАЛ: не нашлась кнопка области\n");
        return 1;
    };
    var rc: c.RECT = undefined;
    _ = c.GetWindowRect(btn, &rc);
    _ = c.SetCursorPos(rc.right - 12, @divTrunc(rc.top + rc.bottom, 2));
    c.Sleep(200);
    _ = c.PostMessageW(hwnd, c.WM_COMMAND, @as(c.WPARAM, zigrec.ui.id_area_rec), @bitCast(@intFromPtr(btn)));
    c.Sleep(900);

    // Щелчок по ячейке строки соотношений — настоящим нажатием мыши.
    //
    // Не посылкой сообщения: меню крутит свой цикл ввода и читает мышь
    // у системы, а не из нашей очереди. Проверять надо то же, что делает
    // рука, — иначе «нажатие» проверит сообщение, а не меню.
    if (cell < aspect_cells) {
        // Где строка, спрашиваем у САМОГО МЕНЮ, а не у окна: стенд —
        // отдельный процесс, и память окна ему не видна. Меню — обычное
        // окно системного класса, и строка соотношений в нём последняя.
        const menu_class = std.unicode.utf8ToUtf16LeStringLiteral("#32768");
        // Меню открывается не мгновенно: ждём его появления, а не гадаем
        // одной задержкой.
        var look: u32 = 0;
        var menu_found: ?c.HWND = null;
        while (look < 40) : (look += 1) {
            // Windows держит окна меню про запас и прячет их: невидимое
            // нам не годится — у него и размера-то нет.
            const maybe = c.FindWindowW(menu_class, null);
            if (maybe) |h| {
                if (c.IsWindowVisible(h) != 0) {
                    menu_found = h;
                    break;
                }
            }
            c.Sleep(100);
        }
        const menu_hwnd = menu_found orelse {
            try w.writeAll("[menu] ПРОВАЛ: окно меню не нашлось\n");
            return 1;
        };
        var menu_rc: c.RECT = undefined;
        _ = c.GetWindowRect(menu_hwnd, &menu_rc);
        const edge: i32 = 3;
        const row_h: i32 = 26;
        const row_x = menu_rc.left + edge;
        const row_w = (menu_rc.right - edge) - row_x;
        const row_y = menu_rc.bottom - edge - row_h;
        if (row_w <= 0) {
            try w.writeAll("[menu] ПРОВАЛ: меню оказалось пустым\n");
            return 1;
        }
        const left = row_x + zigrec.aspect.cellLeft(@intCast(cell), row_w, aspect_cells);
        const right = row_x + zigrec.aspect.cellLeft(@intCast(cell + 1), row_w, aspect_cells);
        // Середина ячейки, но не ближе двенадцати точек к краю строки:
        // у самого края попадаешь в рамку меню, и оно просто закрывается.
        const middle = @divTrunc(left + right, 2);
        const click_x = std.math.clamp(middle, row_x + 12, row_x + row_w - 12);
        const click_y = row_y + @divTrunc(row_h, 2);
        _ = c.SetCursorPos(click_x, click_y);
        c.Sleep(200);
        mouseClick();
        c.Sleep(500);

        // Что выбралось, написано на самой кнопке.
        var text: [128]u16 = undefined;
        const n: usize = @intCast(@max(c.GetWindowTextW(btn, &text, text.len), 0));
        var utf8: [256]u8 = undefined;
        const got_len = std.unicode.utf16LeToUtf8(&utf8, text[0..n]) catch 0;
        const got = utf8[0..got_len];
        var want: [16]u8 = undefined;
        const want_text = zigrec.aspect.ratios[@intCast(cell)].label(&want);
        try w.print("[menu] меню {d},{d}..{d},{d}; строка {d},{d} шириной {d}\n", .{ menu_rc.left, menu_rc.top, menu_rc.right, menu_rc.bottom, row_x, row_y, row_w });
        try w.print("[menu] ткнули в ({d},{d}) — ячейка {d}, на кнопке: «{s}»\n", .{ click_x, click_y, cell, got });
        if (std.mem.indexOf(u8, got, want_text) == null) {
            try w.print("[menu] ПРОВАЛ: ждали {s}, а выбралось другое\n", .{want_text});
            return 1;
        }
        try w.print("[menu] ЯЧЕЙКА ВЫБИРАЕТ СВОЁ СООТНОШЕНИЕ ({s})\n", .{want_text});
        return 0;
    }

    // Перед снимком наводим курсор на вторую ячейку строки: подсветку
    // ячейки иначе не увидеть, а именно её и проверяем глазами.
    {
        const menu_class = std.unicode.utf8ToUtf16LeStringLiteral("#32768");
        var look: u32 = 0;
        while (look < 30) : (look += 1) {
            const maybe = c.FindWindowW(menu_class, null);
            if (maybe) |h| {
                if (c.IsWindowVisible(h) != 0) {
                    var menu_rc: c.RECT = undefined;
                    _ = c.GetWindowRect(h, &menu_rc);
                    const edge: i32 = 3;
                    const row_h: i32 = 26;
                    const row_x = menu_rc.left + edge;
                    const row_w = (menu_rc.right - edge) - row_x;
                    const at_x = row_x + zigrec.aspect.cellLeft(1, row_w, aspect_cells) + @divTrunc(row_w, @as(i32, @intCast(aspect_cells)) * 2);
                    _ = c.SetCursorPos(at_x, menu_rc.bottom - edge - @divTrunc(row_h, 2));
                    c.Sleep(400);
                    break;
                }
            }
            c.Sleep(100);
        }
    }

    // Снимаем прямоугольник от кнопки вниз и вправо: меню открывается под
    // кнопкой, а какой оно ширины — решает сама Windows.
    const shot_x = rc.left - 10;
    const shot_y = rc.bottom - 10;
    const shot_w: u32 = 520;
    const shot_h: u32 = 460;

    const screen_dc = c.GetDC(null);
    defer _ = c.ReleaseDC(null, screen_dc);
    const mem_dc = c.CreateCompatibleDC(screen_dc);
    defer _ = c.DeleteDC(mem_dc);

    var bmi = std.mem.zeroes(c.BITMAPINFO);
    bmi.bmiHeader.biSize = @sizeOf(c.BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = @intCast(shot_w);
    bmi.bmiHeader.biHeight = -@as(i32, @intCast(shot_h));
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = c.BI_RGB;
    var bits: ?*anyopaque = null;
    const dib = c.CreateDIBSection(mem_dc, &bmi, c.DIB_RGB_COLORS, &bits, null, 0) orelse return 1;
    defer _ = c.DeleteObject(dib);
    const old = c.SelectObject(mem_dc, dib);
    defer _ = c.SelectObject(mem_dc, old);

    if (c.BitBlt(mem_dc, 0, 0, @intCast(shot_w), @intCast(shot_h), screen_dc, shot_x, shot_y, c.SRCCOPY) == 0) {
        try w.writeAll("[menu] ПРОВАЛ: не снялось с экрана\n");
        return 1;
    }
    // Меню закрываем сразу: оно держит поток окна, и без этого закрытие
    // окна ниже не сработает.
    _ = c.PostMessageW(hwnd, c.WM_CANCELMODE, 0, 0);
    _ = c.SetForegroundWindow(hwnd);

    const stride: usize = @as(usize, shot_w) * 4;
    const raw: [*]u8 = @ptrCast(bits.?);
    const png = try zigrec.png.fromBgra(allocator, raw[0 .. stride * shot_h], shot_w, shot_h, stride);
    defer allocator.free(png);
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    try std.Io.Dir.cwd().writeFile(threaded.io(), .{ .sub_path = path, .data = png });
    try w.print("[menu] записан {s}: {d}x{d}\n", .{ path, shot_w, shot_h });
    return 0;
}

/// Снять окно редактора — чтобы посмотреть на него глазами.
///
/// Минимапа, дорожки и кадр рисуются нашим кодом, и ошибки в них видны
/// только глазами: цвет не тот, полоса не там, подпись обрезана. Стенд не
/// судит красоту — он даёт картинку, которую можно посмотреть, и делает это
/// одинаково каждый раз.
fn editorShot(allocator: std.mem.Allocator, w: anytype, path: []const u8, video: ?[]const u8, wheel: u64) !u8 {
    const c = zigrec.win32.c;
    // Имя класса берём у окна, а не переписываем: разъехались бы —
    // и стенд искал бы окно, которого нет.
    const class = std.unicode.utf8ToUtf16LeStringLiteral(zigrec.ui.editor_class);

    var exe_w: [std.fs.max_path_bytes]u16 = undefined;
    const exe_len = c.GetModuleFileNameW(null, &exe_w, exe_w.len);
    if (exe_len == 0) {
        try w.writeAll("[shot] ПРОВАЛ: не узнать собственный путь\n");
        return 1;
    }
    exe_w[exe_len] = 0;

    // Командная строка: exe, слово edit и, если дали, файл.
    var line: [std.fs.max_path_bytes * 2]u8 = undefined;
    var exe_utf8: [std.fs.max_path_bytes]u8 = undefined;
    const exe_n = std.unicode.utf16LeToUtf8(&exe_utf8, exe_w[0..exe_len]) catch 0;
    const cmd_utf8 = if (video) |v|
        std.fmt.bufPrint(&line, "\"{s}\" edit \"{s}\"", .{ exe_utf8[0..exe_n], v }) catch return 1
    else
        std.fmt.bufPrint(&line, "\"{s}\" edit", .{exe_utf8[0..exe_n]}) catch return 1;
    var cmd_w: [std.fs.max_path_bytes * 2]u16 = undefined;
    const cmd_n = std.unicode.utf8ToUtf16Le(&cmd_w, cmd_utf8) catch return 1;
    cmd_w[cmd_n] = 0;

    var si = std.mem.zeroes(c.STARTUPINFOW);
    si.cb = @sizeOf(c.STARTUPINFOW);
    var pi = std.mem.zeroes(c.PROCESS_INFORMATION);
    if (c.CreateProcessW(null, &cmd_w, null, null, 0, c.CREATE_NEW_CONSOLE, null, null, &si, &pi) == 0) {
        try w.print("[shot] ПРОВАЛ: редактор не запустился (ошибка {d})\n", .{c.GetLastError()});
        return 1;
    }
    defer {
        _ = c.CloseHandle(pi.hThread);
        _ = c.CloseHandle(pi.hProcess);
    }

    var waited: u32 = 0;
    var found: ?c.HWND = null;
    while (waited < 150) : (waited += 1) {
        if (c.FindWindowW(class, null)) |h| {
            if (c.IsWindowVisible(h) != 0) {
                found = h;
                break;
            }
        }
        c.Sleep(100);
    }
    const hwnd = found orelse {
        _ = c.TerminateProcess(pi.hProcess, 1);
        try w.writeAll("[shot] ПРОВАЛ: окно редактора не открылось\n");
        return 1;
    };
    // Файл читается не мгновенно: дорожки и волна появляются позже окна.
    c.Sleep(2500);

    // Колесо над кадром: ставим настоящий курсор в середину окна просмотра
    // и крутим. Окно спрашивает положение курсора само, поэтому подделать
    // его сообщением нельзя — и не надо: так проверяется то же, что делает
    // рука.
    if (wheel > 0) {
        var rc: c.RECT = undefined;
        _ = c.GetWindowRect(hwnd, &rc);
        const at_x = @divTrunc(rc.left + rc.right, 2);
        // Окно просмотра — верхняя треть окна под панелью кнопок.
        const at_y = rc.top + @divTrunc(rc.bottom - rc.top, 3);
        _ = c.SetCursorPos(at_x, at_y);
        c.Sleep(200);
        var turn: u64 = 0;
        while (turn < wheel) : (turn += 1) {
            const point: c.LPARAM = @as(c.LPARAM, at_x & 0xFFFF) | (@as(c.LPARAM, at_y & 0xFFFF) << 16);
            _ = c.SendMessageW(hwnd, c.WM_MOUSEWHEEL, @as(c.WPARAM, 120) << 16, point);
            c.Sleep(120);
        }
        c.Sleep(400);
    }

    const ok = shootWindow(allocator, w, hwnd, path) catch |err| {
        try w.print("[shot] ПРОВАЛ: {s}\n", .{@errorName(err)});
        _ = c.PostMessageW(hwnd, c.WM_CLOSE, 0, 0);
        _ = c.TerminateProcess(pi.hProcess, 0);
        return 1;
    };

    _ = c.PostMessageW(hwnd, c.WM_CLOSE, 0, 0);
    _ = c.WaitForSingleObject(pi.hProcess, 3000);
    _ = c.TerminateProcess(pi.hProcess, 0);
    return if (ok) 0 else 1;
}

/// Снять окно с экрана и записать png. Общий кусок для обоих стендов.
fn shootWindow(allocator: std.mem.Allocator, w: anytype, hwnd: zigrec.win32.c.HWND, path: []const u8) !bool {
    const c = zigrec.win32.c;
    const area = try zigrec.source.windowArea(hwnd);
    const width: u32 = area.width;
    const height: u32 = area.height;

    const screen_dc = c.GetDC(null);
    defer _ = c.ReleaseDC(null, screen_dc);
    const mem_dc = c.CreateCompatibleDC(screen_dc);
    defer _ = c.DeleteDC(mem_dc);

    var bmi = std.mem.zeroes(c.BITMAPINFO);
    bmi.bmiHeader.biSize = @sizeOf(c.BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = @intCast(width);
    bmi.bmiHeader.biHeight = -@as(i32, @intCast(height));
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = c.BI_RGB;

    var bits: ?*anyopaque = null;
    const dib = c.CreateDIBSection(mem_dc, &bmi, c.DIB_RGB_COLORS, &bits, null, 0) orelse return error.NoImage;
    defer _ = c.DeleteObject(dib);
    const old = c.SelectObject(mem_dc, dib);
    defer _ = c.SelectObject(mem_dc, old);

    _ = setWindowPosZ(hwnd, @bitCast(@as(isize, -1)), 0, 0, 0, 0, c.SWP_NOMOVE | c.SWP_NOSIZE | c.SWP_SHOWWINDOW);
    _ = c.SetForegroundWindow(hwnd);
    c.Sleep(500);
    if (c.BitBlt(mem_dc, 0, 0, @intCast(width), @intCast(height), screen_dc, area.x, area.y, c.SRCCOPY) == 0) {
        return error.NotShot;
    }

    const stride: usize = @as(usize, width) * 4;
    const raw: [*]u8 = @ptrCast(bits.?);
    const png = try zigrec.png.fromBgra(allocator, raw[0 .. stride * height], width, height, stride);
    defer allocator.free(png);

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    try std.Io.Dir.cwd().writeFile(threaded.io(), .{ .sub_path = path, .data = png });
    try w.print("[shot] записан {s}: {d}x{d}, {d} байт\n", .{ path, width, height, png.len });
    return true;
}

/// Самопроверка справки: два текста описывают одни и те же команды.
///
/// Справка живёт двумя цельными текстами, а не парами строк, — иначе лист
/// с колонками разъехался бы по ширине на первой же правке. Плата за это:
/// их надо править парой, и забыть вторую легко. По-русски всё на месте,
/// а английский читатель команды просто не увидит — и никто не заметит,
/// потому что своя справка у каждого читается на своём языке.
///
/// Считаем строки, начинающиеся с «  zigrec», и сверяем числа. Это не
/// перевод по существу — совпадения смысла стенд проверить не может, — но
/// ровно ту ошибку, которой мы боимся (одну правили, другую забыли), он
/// ловит наверняка.
fn usageSmoke(w: anytype) !u8 {
    const ru = countCommands(usage);
    const en = countCommands(usage_en);
    try w.print("[usage] команд: по-русски {d}, по-английски {d}\n", .{ ru, en });
    if (ru != en) {
        try w.writeAll("[usage] ПРОВАЛ: справки разошлись — одну правили, другую забыли\n");
        return 1;
    }
    // Пустая справка — тоже провал: считать было бы нечего, и стенд соврал
    // бы зелёным ответом.
    if (ru == 0) {
        try w.writeAll("[usage] ПРОВАЛ: в справке нет ни одной команды\n");
        return 1;
    }
    try w.writeAll("[usage] СПРАВКИ СОВПАДАЮТ\n");
    return 0;
}

fn countCommands(text: []const u8) usize {
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        if (std.mem.startsWith(u8, line, "  zigrec")) n += 1;
    }
    return n;
}

fn consoleSmoke(w: anytype) !u8 {
    const c = zigrec.win32.c;
    const cp = c.GetConsoleOutputCP();
    const word = "рекордер экрана";

    try w.print("[console] кодовая страница вывода: {d}\n", .{cp});
    try w.print("[console] проба: {s} ({d} байт)\n", .{ word, word.len });

    // Двадцать девять байт: пятнадцать букв, из них четырнадцать русских
    // по два байта, пробел и «р»… — считает компилятор, а не мы.
    if (!std.unicode.utf8ValidateSlice(word)) {
        try w.writeAll("[console] ПРОВАЛ: наша строка не UTF-8\n");
        return 1;
    }
    // Ноль — консоли нет вовсе (вывод перенаправлен без своей консоли);
    // это не провал: на перенаправленный вывод страница не влияет.
    if (cp != 0 and cp != 65001) {
        try w.print("[console] ПРОВАЛ: страница {d}, а не 65001 — буквы рассыплются\n", .{cp});
        return 1;
    }
    try w.writeAll("[console] КИРИЛЛИЦА В КОНСОЛИ ЦЕЛА\n");
    return 0;
}

/// Наблюдатель за ростом прочитанного: когда нужное место станет слышно.
///
/// Переменные уровня файла, а не поля: читающий поток зовёт нас без всякого
/// «своего» указателя, а стенд в один миг меряет ровно один файл.
const SeekWatch = struct {
    var want: u64 = 0;
    var started: u64 = 0;
    var at_ms: u64 = 0;

    fn grew(ctx: ?*anyopaque, samples: []f32, rate: u32, ready: usize) void {
        _ = ctx;
        _ = samples;
        if (at_ms != 0 or rate == 0) return;
        if (ready >= want * rate) at_ms = (zigrec.win32.nowNs() - started) / std.time.ns_per_ms;
    }
};

/// Сколько стоит прыжок указателя по длинному файлу и чтение его звука.
///
/// Владелец (28.09.2026): открыл часовой mp4, ткнул в четвёртую минуту —
/// окно «конкретно подвисает». Гадать, что именно встало, нельзя: в этот миг
/// делаются две разные работы — перемотка картинки и чтение звука целиком.
/// Стенд меряет их порознь и называет виновника числом.
///
/// **Порог — это отзывчивость окна, а не скорость железа.** Прыжок указателя
/// человек считает мгновенным до четверти секунды; всё, что дольше секунды,
/// он называет зависанием. Поэтому стенд валится на секунде, а не на «вдвое
/// медленнее, чем в прошлый раз».
fn seekTime(allocator: std.mem.Allocator, w: anytype, path: []const u8, sec: u64) !u8 {
    const when_ns = sec * std.time.ns_per_s;
    var bad: u8 = 0;

    // Файла нет — сделаем свой: стенд обязан проверять себя сам, а не ждать,
    // что кто-то оставит после себя клип в нужном месте. Первый заход как раз
    // на это и наткнулся: соседний шаг убирал за собой, и мерить было нечего.
    if (!fileExists(path)) try makeClip(allocator, w, path);

    const clock = zigrec.win32.nowNs;
    var mark = clock();
    var p = zigrec.player.Player.openScaled(allocator, path, 640, 360) catch |err| {
        try w.print("[seek] ПРОВАЛ: файл не открылся: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer p.close();
    const open_ms = (clock() - mark) / std.time.ns_per_ms;
    try w.print("[seek] открытие: {d} мс, длительность {d} с\n", .{ open_ms, p.duration_ns / std.time.ns_per_s });

    mark = clock();
    p.showAt(when_ns) catch |err| {
        try w.print("[seek] ПРОВАЛ: перемотка не удалась: {s}\n", .{@errorName(err)});
        return 1;
    };
    const seek_ms = (clock() - mark) / std.time.ns_per_ms;
    const landed = p.at_ns / std.time.ns_per_s;
    try w.print("[seek] прыжок на {d} с: {d} мс, попали на {d} с\n", .{ sec, seek_ms, landed });
    if (seek_ms > 1000) {
        try w.print("[seek] ПРОВАЛ: прыжок дольше секунды — окно замрёт\n", .{});
        bad = 1;
    }
    // Попасть надо туда, куда просили: перемотка, молча оставившая указатель
    // в начале, выглядит как «редактор не слушается».
    const gap = if (landed > sec) landed - sec else sec - landed;
    if (gap > 2) {
        try w.print("[seek] ПРОВАЛ: просили {d} с, показан {d} с\n", .{ sec, landed });
        bad = 1;
    }

    // Главное число этого стенда: когда звук нужного места станет слышен.
    // Владелец жаловался не на «файл читается долго», а на «прыгнул на третью
    // минуту — и первые секунды тишина». Значит мерить надо именно это.
    SeekWatch.want = sec;
    SeekWatch.at_ms = 0;
    SeekWatch.started = clock();

    mark = clock();
    var sound = zigrec.audio_read.readWatched(allocator, path, .{
        .ctx = null,
        .say = SeekWatch.grew,
    }) catch |err| {
        try w.print("[seek] звука нет: {s}\n", .{@errorName(err)});
        return bad;
    };
    defer sound.deinit(allocator);
    const read_ms = (clock() - mark) / std.time.ns_per_ms;
    const mb = sound.samples.len * @sizeOf(f32) / (1024 * 1024);
    try w.print("[seek] звук целиком: {d} мс, {d} отсчётов, {d} МБ в памяти\n", .{ read_ms, sound.samples.len, mb });

    if (SeekWatch.at_ms > 0) {
        try w.print("[seek] звук на {d}-й секунде слышен через {d} мс\n", .{ sec, SeekWatch.at_ms });
        // Три секунды — предел терпения: дольше человек считает, что звука
        // нет вовсе, и лезет проверять громкость.
        if (SeekWatch.at_ms > 3000) {
            try w.writeAll("[seek] ПРОВАЛ: звук нужного места ждёт слишком долго\n");
            bad = 1;
        }
    } else {
        try w.print("[seek] до {d}-й секунды звука в файле не хватило\n", .{sec});
    }

    if (bad == 0) try w.writeAll("[seek] ПРЫЖОК БЫСТРЫЙ\n");
    return bad;
}

fn motionSmoke(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8) !u8 {
    const bench = zigrec.testbench;
    // Размер — как у стенда кодирования: меньше он не умеет рисовать таймкод.
    const width: u32 = 384;
    const height: u32 = 256;
    const fps: u32 = 30;
    const moving_head: u32 = 40;
    const still_len: u32 = 10;
    const moving_tail: u32 = 40;

    const screen = try bench.Screen.init(width, height, fps);
    const buf = try allocator.alloc(u8, screen.frameBytes());
    defer allocator.free(buf);

    var enc = zigrec.encode.Writer.create(path, width, height, .{ .fps = fps, .preset = .max }) catch |err| {
        try w.print("[motion] ПРОВАЛ: кодировщик не создался: {s}\n", .{@errorName(err)});
        return 1;
    };
    var closed = false;
    errdefer if (!closed) enc.abort();

    const frame_ns: u64 = std.time.ns_per_s / fps;
    var made: u32 = 0;
    var index: u32 = 1;
    while (made < moving_head + still_len + moving_tail) : (made += 1) {
        // В середине номер кадра не меняем — картинка стоит.
        const still = made >= moving_head and made < moving_head + still_len;
        if (!still) index += 1;
        try screen.render(buf, index);
        try enc.writeFrame(buf, width * 4, frame_ns * made);
    }
    const summary = enc.finish() catch |err| {
        try w.print("[motion] ПРОВАЛ: файл не закрылся: {s}\n", .{@errorName(err)});
        return 1;
    };
    closed = true;
    _ = zigrec.mp4.makeFastStart(io, allocator, path) catch false;
    try w.print("[motion] клип: {d} кадров, неподвижны {d}..{d}\n", .{ summary.frames, moving_head, moving_head + still_len - 1 });

    // Теперь считаем волну по готовому файлу — тем же путём, что редактор.
    var wave = zigrec.motion.compute(allocator, path, 0) catch |err| {
        try w.print("[motion] ПРОВАЛ: волна не посчиталась: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer wave.deinit(allocator);

    if (wave.step.len + 8 < summary.frames) {
        try w.print("[motion] ПРОВАЛ: кадров в клипе {d}, а столбиков в волне {d}\n", .{ summary.frames, wave.step.len });
        return 1;
    }
    const counted = wave.marks();
    try w.print("[motion] столбиков {d}, стоящих кадров {d}, скачков {d}\n", .{ wave.step.len, counted.still, counted.jumps });

    // Засечки обязаны лежать в известной середине, а не где попало.
    var inside: usize = 0;
    var outside: usize = 0;
    var i: usize = 1;
    while (i < wave.step.len) : (i += 1) {
        if (!wave.isStill(i)) continue;
        // Плюс-минус два кадра: декодер отдаёт кадры чуть иначе, чем мы их
        // писали (перестановка B-кадров), и требовать точного номера значило
        // бы проверять кодировщик, а не волну.
        if (i + 2 >= moving_head and i <= moving_head + still_len + 2) inside += 1 else outside += 1;
    }
    try w.print("[motion] засечек в середине {d}, вне неё {d}\n", .{ inside, outside });
    if (inside < still_len / 2) {
        try w.writeAll("[motion] ПРОВАЛ: неподвижную середину волна не нашла\n");
        return 1;
    }
    if (outside > 2) {
        try w.writeAll("[motion] ПРОВАЛ: засечки стоят там, где движение было ровным\n");
        return 1;
    }
    // Движущаяся часть обязана быть заметно выше нуля — иначе волна плоская
    // и ничего не показывает.
    const at_move = wave.at(5 * frame_ns);
    if (at_move < 0.005) {
        try w.print("[motion] ПРОВАЛ: на движении волна почти нулевая ({d:.4})\n", .{at_move});
        return 1;
    }
    try w.print("[motion] на движении {d:.3}, в середине {d:.3}\n", .{ at_move, wave.at((moving_head + still_len / 2) * frame_ns) });
    std.Io.Dir.cwd().deleteFile(io, path) catch {};
    try w.writeAll("[motion] ВОЛНА ДВИЖЕНИЯ НАХОДИТ РЫВКИ\n");
    return 0;
}

/// Двойной клик по exe открывает окно — самопроверка (без глаз).
///
/// Запускаем себя же так, как это делает Проводник: без ключей и со своей
/// новой консолью. Ждём окно `ZigRecMain`, смотрим, что оно видимо, и что в
/// стандартный поток не ушла справка — мигнувшая справка вместо окна и была
/// тем, на что жаловался владелец.
fn clickSmoke(io: std.Io, allocator: std.mem.Allocator, w: anytype) !u8 {
    const c = zigrec.win32.c;
    const class = std.unicode.utf8ToUtf16LeStringLiteral("ZigRecMain");

    if (c.FindWindowW(class, null) != null) {
        try w.writeAll("[click] ПРОВАЛ: окно уже открыто — стенд не поймёт, чьё оно. Закройте его.\n");
        return 1;
    }

    var exe_w: [std.fs.max_path_bytes]u16 = undefined;
    const exe_len = c.GetModuleFileNameW(null, &exe_w, exe_w.len);
    if (exe_len == 0 or exe_len >= exe_w.len) {
        try w.writeAll("[click] ПРОВАЛ: не узнать собственный путь\n");
        return 1;
    }
    exe_w[exe_len] = 0;

    // Вывод — в файл: так проверяется, что справки в нём нет. Своя консоль
    // при этом всё равно создаётся, и прятать её программа обязана.
    const said_path = ".check\\click.txt";
    var said_file = try std.Io.Dir.cwd().createFile(io, said_path, .{});
    said_file.close(io);

    var said_w: [std.fs.max_path_bytes]u16 = undefined;
    const said_n = try std.unicode.utf8ToUtf16Le(&said_w, said_path);
    said_w[said_n] = 0;

    var sa = std.mem.zeroes(c.SECURITY_ATTRIBUTES);
    sa.nLength = @sizeOf(c.SECURITY_ATTRIBUTES);
    sa.bInheritHandle = 1;
    const out_handle = c.CreateFileW(
        &said_w,
        c.GENERIC_WRITE,
        c.FILE_SHARE_READ | c.FILE_SHARE_WRITE,
        &sa,
        c.OPEN_EXISTING,
        c.FILE_ATTRIBUTE_NORMAL,
        null,
    );

    var si = std.mem.zeroes(c.STARTUPINFOW);
    si.cb = @sizeOf(c.STARTUPINFOW);
    if (out_handle != c.INVALID_HANDLE_VALUE) {
        si.dwFlags = c.STARTF_USESTDHANDLES;
        si.hStdOutput = out_handle;
        si.hStdError = out_handle;
    }
    var pi = std.mem.zeroes(c.PROCESS_INFORMATION);
    // CREATE_NEW_CONSOLE — ровно то, что делает Проводник по двойному клику.
    if (c.CreateProcessW(&exe_w, null, null, null, 1, c.CREATE_NEW_CONSOLE, null, null, &si, &pi) == 0) {
        try w.print("[click] ПРОВАЛ: не запуститься самому (ошибка {d})\n", .{c.GetLastError()});
        return 1;
    }
    defer {
        _ = c.CloseHandle(pi.hThread);
        _ = c.CloseHandle(pi.hProcess);
        if (out_handle != c.INVALID_HANDLE_VALUE) _ = c.CloseHandle(out_handle);
    }

    // Ждём не просто появления окна, а того, что его уже показали: окно
    // рождается невидимым и без заголовка, и первый заход стенда именно так
    // и поймал «окно есть, но его не видно».
    var waited: u32 = 0;
    var hwnd: ?c.HWND = null;
    while (waited < 100) : (waited += 1) {
        const found_now = c.FindWindowW(class, null);
        if (found_now) |h| {
            if (c.IsWindowVisible(h) != 0) {
                hwnd = h;
                break;
            }
        }
        c.Sleep(100);
    }
    const found = hwnd orelse {
        _ = c.TerminateProcess(pi.hProcess, 1);
        try w.writeAll("[click] ПРОВАЛ: за десять секунд окно так и не открылось\n");
        return 1;
    };
    const visible = c.IsWindowVisible(found) != 0;
    var title: [256]u16 = undefined;
    const title_len = c.GetWindowTextW(found, &title, title.len);
    var title_utf8: [512]u8 = undefined;
    const title_text = if (title_len > 0)
        title_utf8[0..(std.unicode.utf16LeToUtf8(&title_utf8, title[0..@intCast(title_len)]) catch 0)]
    else
        "";

    // Кнопка «папка записей» должна быть в окне и быть доступной СРАЗУ:
    // за вчерашним файлом идут ещё до первой записи этого сеанса, и
    // выключенная кнопка была бы ровно тем, чего просили избежать.
    const dir_btn = c.GetDlgItem(found, zigrec.ui.id_open_dir);
    const dir_ok = dir_btn != null and c.IsWindowEnabled(dir_btn) != 0;

    _ = c.PostMessageW(found, c.WM_CLOSE, 0, 0);
    _ = c.WaitForSingleObject(pi.hProcess, 3000);
    _ = c.TerminateProcess(pi.hProcess, 0);

    const said = std.Io.Dir.cwd().readFileAlloc(io, said_path, allocator, .limited(1 << 20)) catch "";
    std.Io.Dir.cwd().deleteFile(io, said_path) catch {};

    try w.print("[click] окно «{s}»: {s}; в поток ушло {d} байт\n", .{
        title_text,
        if (visible) "видимо" else "НЕ ВИДИМО",
        said.len,
    });
    if (!visible) {
        try w.writeAll("[click] ПРОВАЛ: окно есть, но его не видно\n");
        return 1;
    }
    // «рекордер экрана и редактор» — первая строка справки.
    if (std.mem.indexOf(u8, said, "рекордер экрана") != null) {
        try w.writeAll("[click] ПРОВАЛ: вместо окна напечатана справка\n");
        return 1;
    }
    if (!dir_ok) {
        try w.writeAll("[click] ПРОВАЛ: кнопки «папка записей» нет или она выключена\n");
        return 1;
    }
    try w.writeAll("[click] кнопка «папка записей» на месте и доступна\n");
    try w.writeAll("[click] ДВОЙНОЙ КЛИК ОТКРЫВАЕТ ОКНО\n");
    return 0;
}

/// Своя ли у нас консоль — то есть запустили нас двойным кликом, а не из
/// уже открытого терминала.
///
/// `GetConsoleProcessList` перечисляет тех, кто сидит на этой консоли. Нас
/// одних — значит консоль создана под нас, и прятать её можно. Если там есть
/// ещё кто-то (cmd, PowerShell, наш же стенд), это чужое окно с чужим текстом,
/// и трогать его нельзя ни при каких обстоятельствах.
/// Сказать консоли, что вывод — UTF-8.
///
/// Делаем это до любого печатания и не проверяем, есть ли консоль вообще:
/// без неё вызов просто ничего не меняет, а лишняя проверка была бы ещё
/// одним местом, где можно ошибиться. На перенаправленный в файл вывод
/// кодовая страница не влияет — там байты и так наши.
fn setConsoleUtf8() void {
    if (builtin.os.tag != .windows) return;
    const c = zigrec.win32.c;
    _ = c.SetConsoleOutputCP(65001);
    // И ввод тоже: в командной строке бывают русские пути и заголовки окон.
    _ = c.SetConsoleCP(65001);
}

fn ownConsoleAlone() bool {
    if (builtin.os.tag != .windows) return false;
    const c = zigrec.win32.c;
    var ids: [4]c.DWORD = undefined;
    const n = c.GetConsoleProcessList(&ids, ids.len);
    return n == 1;
}

/// Спрятать своё консольное окно.
///
/// Прячем, а не освобождаем (`FreeConsole`): после освобождения вывод в
/// стандартный поток становится ошибкой, а печатать нам ещё может
/// понадобиться — например, если окно не откроется. Спрятанная консоль
/// принимает текст молча.
fn hideConsole() void {
    if (builtin.os.tag != .windows) return;
    const c = zigrec.win32.c;
    const console = c.GetConsoleWindow() orelse return;
    _ = c.ShowWindow(console, c.SW_HIDE);
}

/// Снять `--lang ЯЗЫК` из ключей и выставить язык окон. Названный ключом
/// язык сильнее настроек: так самопроверки меряют окна на обоих языках,
/// какой бы ни стоял у владельца машины.
fn takeLang(arena: std.mem.Allocator, raw: anytype) !@TypeOf(raw) {
    const Item = @typeInfo(@TypeOf(raw)).pointer.child;
    var out = try arena.alloc(Item, raw.len);
    var n: usize = 0;
    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        if (eq(raw[i], "--lang") and i + 1 < raw.len) {
            zigrec.lang.force(zigrec.lang.Language.parse(raw[i + 1]));
            i += 1;
            continue;
        }
        // Короткие `--en` и `--ru`: владелец написал `zigrec --help --en`, и
        // это естественнее, чем `--lang en`. Снимаем их так же — до разбора
        // команд, чтобы ни одна из них про язык не знала.
        if (eq(raw[i], "--en")) {
            zigrec.lang.force(.en);
            continue;
        }
        if (eq(raw[i], "--ru")) {
            zigrec.lang.force(.ru);
            continue;
        }
        out[n] = raw[i];
        n += 1;
    }
    return out[0..n];
}

/// Ошибки разбора ключей — тоже словами.
fn explainArgs(err: ArgError) []const u8 {
    return switch (err) {
        ArgError.MissingValue => "у ключа нет значения",
        ArgError.BadValue => "значение ключа не подходит",
        ArgError.UnknownKey => "неизвестный ключ",
        ArgError.OneSourceOnly => "источник записи должен быть один: монитор, область или окно",
    };
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// Есть ли такой ключ среди аргументов.
fn hasFlag(args: []const []const u8, name: []const u8) bool {
    for (args) |a| {
        if (eq(a, name)) return true;
    }
    return false;
}

fn argInt(args: []const []const u8, index: usize, default: u32) u32 {
    if (args.len <= index) return default;
    return std.fmt.parseInt(u32, args[index], 10) catch default;
}

// ------------------------------------------------------------ самопроверки

fn captureSmoke(allocator: std.mem.Allocator, w: anytype, frames: u32, backend: zigrec.capture.Backend) !u8 {
    try w.print("[smoke] захват: показываем {d} кадров и читаем их обратно с экрана\n", .{frames});
    try w.flush();

    const report = zigrec.smoke.run(allocator, .{ .frames = frames, .backend = backend }) catch |err| {
        try w.print("[smoke] ПРОВАЛ: {s}\n", .{explain(err)});
        return 1;
    };

    try w.print("[smoke] экран {d}x{d}, путь {s}\n", .{ report.width, report.height, report.backend.label() });
    try w.print("[smoke] показано {d}, снято {d}, номер прочитан в {d}\n", .{
        report.shown,
        report.captured,
        report.read,
    });
    // Совпадение с той же итерацией — свойство машины, а не захвата:
    // печатаем, но не судим по нему.
    try w.print("[smoke] экран отставал в среднем на {d:.1} кадра, совпало сразу {d}\n", .{
        report.lag,
        report.matched,
    });
    try w.print("[smoke] потери {d}, повторы {d}, порядок сбит {d} раз\n", .{
        report.tally.dropped,
        report.tally.duplicated,
        report.tally.out_of_order,
    });
    try w.print("[smoke] кадров в секунду {d:.1}, накоплено системой {d}, простоев {d}, пересозданий дубликации {d}\n", .{
        report.stats.fps(),
        report.stats.dropped,
        report.stats.idle,
        report.stats.recoveries,
    });

    if (!report.ok()) {
        try w.writeAll("[smoke] ПРОВАЛ: снято слишком мало кадров или номера не сходятся\n");
        return 1;
    }
    try w.writeAll("[smoke] ЗАХВАТ ЖИВОЙ\n");
    return 0;
}

/// Кодирование без захвата: кадры берём у стенда, поэтому результат
/// повторяем и не зависит ни от экрана, ни от того, что на нём происходит.
fn encodeSmoke(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8, frames: u32, with_audio: bool) !u8 {
    const bench = zigrec.testbench;
    const width: u32 = bench.min_width;
    const height: u32 = 64;
    const fps: u32 = 30;

    try w.print("[encode] {d} кадров стенда {d}x{d} в {s}\n", .{ frames, width, height, path });
    if (with_audio) try w.writeAll("[encode] со звуком: тишина и два всплеска — на первой и на второй секунде\n");
    try w.flush();

    const screen = try bench.Screen.init(width, height, fps);
    const buf = try allocator.alloc(u8, screen.frameBytes());
    defer allocator.free(buf);

    const audio: ?zigrec.encode.AudioSettings = if (with_audio) .{} else null;
    var enc = zigrec.encode.Writer.create(path, width, height, .{ .fps = fps, .audio = audio }) catch |err| {
        try w.print("[encode] ПРОВАЛ на создании писателя: {s}\n", .{@errorName(err)});
        return 1;
    };

    // Звук стенда синтезируется, а не берётся с микрофона: живой микрофон
    // у каждого свой, и проверка на нём ничего не доказывает.
    const plan = zigrec.tone.benchPlan();
    const audio_cfg = zigrec.encode.AudioSettings{};
    var audio_written: u64 = 0;
    var chunk: [4096]i16 = undefined;

    const frame_ns: u64 = std.time.ns_per_s / fps;
    var i: u32 = 1;
    while (i <= frames) : (i += 1) {
        try screen.render(buf, i);
        enc.writeFrame(buf, width * 4, frame_ns * i) catch |err| {
            try w.print("[encode] ПРОВАЛ на кадре {d}: {s}\n", .{ i, @errorName(err) });
            enc.abort();
            return 1;
        };
        if (!with_audio) continue;

        // Звук догоняет видео: отдаём ровно те отсчёты, что укладываются
        // в уже записанное время. Так дорожки не разъезжаются на длинной записи.
        const want = @as(u64, frame_ns) * i * audio_cfg.sample_rate / std.time.ns_per_s;
        while (audio_written < want) {
            const take: usize = @intCast(@min(want - audio_written, chunk.len));
            for (0..take) |k| {
                chunk[k] = zigrec.resample.toI16(plan.sampleAt(@intCast(audio_written + k), audio_cfg.sample_rate));
            }
            const at_ns = audio_written * std.time.ns_per_s / audio_cfg.sample_rate;
            enc.writeAudio(chunk[0..take], at_ns) catch |err| {
                try w.print("[encode] ПРОВАЛ на звуке: {s}\n", .{@errorName(err)});
                enc.abort();
                return 1;
            };
            audio_written += take;
        }
    }

    const summary = enc.finish() catch |err| {
        try w.print("[encode] ПРОВАЛ на закрытии файла: {s}\n", .{@errorName(err)});
        return 1;
    };
    try w.print("[encode] записано кадров {d}, длительность {d:.2} с\n", .{
        summary.frames,
        @as(f64, @floatFromInt(summary.duration_ns)) / @as(f64, std.time.ns_per_s),
    });
    if (with_audio) {
        try w.print("[encode] звуковых отсчётов {d} ({d:.2} с)\n", .{
            summary.audio_samples,
            @as(f64, @floatFromInt(summary.audio_samples)) / @as(f64, @floatFromInt(audio_cfg.sample_rate)),
        });
        if (summary.audio_samples == 0) {
            try w.writeAll("[encode] ПРОВАЛ: звуковая дорожка пуста\n");
            return 1;
        }
    }

    try fastStart(io, allocator, w, path);

    const ok = try verifyMp4(io, allocator, w, path);
    if (ok != 0) return ok;
    if (summary.frames + 1 < frames) {
        try w.writeAll("[encode] ПРОВАЛ: до файла дошли не все кадры\n");
        return 1;
    }
    try w.writeAll("[encode] ФАЙЛ ГОДНЫЙ\n");
    return 0;
}

/// Перенести moov в начало: своими руками, потому что штатный ключ
/// Media Foundation портит файл (см. src/encode.zig).
fn fastStart(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8) !void {
    const moved = zigrec.mp4.makeFastStart(io, allocator, path) catch |err| {
        try w.print("[mp4] не удалось перенести moov в начало: {s}\n", .{@errorName(err)});
        return;
    };
    if (moved) try w.writeAll("[mp4] moov перенесён в начало файла\n");
}

fn verifyMp4(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8) !u8 {
    var boxes: [64]zigrec.mp4.Box = undefined;
    const layout = zigrec.mp4.inspect(io, allocator, path, &boxes) catch |err| {
        try w.print("[mp4] ПРОВАЛ: {s} ({s})\n", .{ @errorName(err), path });
        return 1;
    };

    try w.print("[mp4] {s}: {d} байт, боксов {d}\n", .{ path, layout.total, layout.boxes.len });
    for (layout.boxes) |b| {
        try w.print("[mp4]   {d:>10}  {s}  {d}\n", .{ b.offset, b.kind, b.size });
    }
    if (!layout.playable()) {
        try w.writeAll("[mp4] ПРОВАЛ: нет moov или пустой mdat — файл не играется\n");
        return 1;
    }
    if (!layout.fastStart()) {
        try w.writeAll("[mp4] ПРОВАЛ: moov после mdat — браузер не начнёт играть, пока не скачает целиком\n");
        return 1;
    }
    try w.print("[mp4] moov перед mdat, данных {d} байт\n", .{layout.mdat_size});
    return 0;
}

/// Проверка распакованного потока: сюда попадает то, что вернул чужой
/// декодер. Так видно, пережил ли таймкод кодирование.
fn verifyRaw(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8, width: u32, height: u32) !u8 {
    if (width == 0 or height == 0) {
        try w.writeAll("[raw] нужны ширина и высота\n");
        return 2;
    }
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1 << 30)) catch |err| {
        try w.print("[raw] ПРОВАЛ: не читается {s}: {s}\n", .{ path, @errorName(err) });
        return 1;
    };
    defer allocator.free(data);

    const stride = width * 4;
    const frame_bytes = @as(usize, stride) * height;
    if (frame_bytes == 0 or data.len < frame_bytes) {
        try w.writeAll("[raw] ПРОВАЛ: в потоке нет ни одного кадра\n");
        return 1;
    }

    const count = data.len / frame_bytes;
    var seen = try allocator.alloc(u32, count);
    defer allocator.free(seen);
    var n: usize = 0;
    for (0..count) |k| {
        const frame = data[k * frame_bytes ..][0..frame_bytes];
        seen[n] = zigrec.testbench.readIndex(frame, width, stride) catch continue;
        n += 1;
    }

    const t = zigrec.testbench.tally(seen[0..n]);
    try w.print("[raw] кадров {d}, прочитано номеров {d}\n", .{ count, n });
    try w.print("[raw] потери {d}, повторы {d}, порядок сбит {d} раз\n", .{ t.dropped, t.duplicated, t.out_of_order });
    if (n > 0) try w.print("[raw] первый номер {d}, последний {d}\n", .{ seen[0], seen[n - 1] });

    if (n < count or !t.ok()) {
        try w.writeAll("[raw] ПРОВАЛ: таймкоды не пережили кодирование\n");
        return 1;
    }
    try w.writeAll("[raw] ТАЙМКОДЫ ЦЕЛЫ\n");
    return 0;
}

// ------------------------------------------------------------------ запись

/// Что и как писать. Разбор ключей отделён от самой записи, чтобы его
/// можно было проверить тестом.
const RecordArgs = struct {
    seconds: u32 = 5,
    fps: u32 = 30,
    monitor: u32 = 0,
    area: ?zigrec.source.Rect = null,
    window: ?[]const u8 = null,
    cursor: bool = true,
    clicks: bool = true,
    /// Область едет за курсором (#29).
    follow: bool = false,
    /// Путь захвата: авто (DXGI, при молчании — GDI), либо явно.
    backend: zigrec.capture.Backend = .auto,
    preset: zigrec.encode.Preset = .text_ui,
    bitrate_kbps: ?u32 = null,
    gop: u32 = 60,
    /// Писать ли звук с микрофона. По умолчанию нет: запись экрана
    /// не должна начинать слушать микрофон сама по себе.
    sound: bool = false,
    /// Системный звук: то, что идёт в колонки.
    system: bool = false,
    /// Двумя дорожками, а не одной сведённой.
    separate: bool = false,
    /// Появился этот файл — запись заканчивается (#124).
    stop_file: ?[]const u8 = null,
    /// Итог последней строкой в JSON (#125).
    json: bool = false,
};

const ArgError = error{
    /// Ключ есть, значения нет.
    MissingValue,
    /// Значение не разобралось.
    BadValue,
    /// Ключ неизвестен.
    UnknownKey,
    /// Указано несколько источников сразу.
    OneSourceOnly,
};

fn parseRecordArgs(args: []const []const u8) ArgError!RecordArgs {
    var out = RecordArgs{};
    var sources: u32 = 0;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const key = args[i];
        const has_value = i + 1 < args.len;
        if (eq(key, "--sec")) {
            if (!has_value) return ArgError.MissingValue;
            i += 1;
            out.seconds = std.fmt.parseInt(u32, args[i], 10) catch return ArgError.BadValue;
        } else if (eq(key, "--fps")) {
            if (!has_value) return ArgError.MissingValue;
            i += 1;
            out.fps = std.fmt.parseInt(u32, args[i], 10) catch return ArgError.BadValue;
            if (out.fps == 0 or out.fps > 240) return ArgError.BadValue;
        } else if (eq(key, "--monitor")) {
            if (!has_value) return ArgError.MissingValue;
            i += 1;
            out.monitor = std.fmt.parseInt(u32, args[i], 10) catch return ArgError.BadValue;
            sources += 1;
        } else if (eq(key, "--area")) {
            if (!has_value) return ArgError.MissingValue;
            i += 1;
            out.area = zigrec.source.parseArea(args[i]) orelse return ArgError.BadValue;
            sources += 1;
        } else if (eq(key, "--window")) {
            if (!has_value) return ArgError.MissingValue;
            i += 1;
            out.window = args[i];
            sources += 1;
        } else if (eq(key, "--sound")) {
            out.sound = true;
        } else if (eq(key, "--system")) {
            out.system = true;
        } else if (eq(key, "--separate")) {
            out.separate = true;
        } else if (eq(key, "--follow")) {
            out.follow = true;
        } else if (eq(key, "--backend")) {
            if (!has_value) return ArgError.MissingValue;
            i += 1;
            out.backend = if (eq(args[i], "dxgi")) .dxgi else if (eq(args[i], "gdi")) .gdi else if (eq(args[i], "wgc")) .wgc else if (eq(args[i], "auto")) .auto else return ArgError.BadValue;
        } else if (eq(key, "--no-cursor")) {
            out.cursor = false;
        } else if (eq(key, "--no-clicks")) {
            out.clicks = false;
        } else if (eq(key, "--stop-file")) {
            if (!has_value) return ArgError.MissingValue;
            i += 1;
            out.stop_file = args[i];
        } else if (eq(key, "--json")) {
            out.json = true;
        } else if (eq(key, "--preset")) {
            if (!has_value) return ArgError.MissingValue;
            i += 1;
            if (eq(args[i], "text")) {
                out.preset = .text_ui;
            } else if (eq(args[i], "video")) {
                out.preset = .video;
            } else if (eq(args[i], "max")) {
                out.preset = .max;
            } else return ArgError.BadValue;
        } else if (eq(key, "--bitrate")) {
            if (!has_value) return ArgError.MissingValue;
            i += 1;
            const v = std.fmt.parseInt(u32, args[i], 10) catch return ArgError.BadValue;
            if (v < 100 or v > 200_000) return ArgError.BadValue;
            out.bitrate_kbps = v;
        } else if (eq(key, "--gop")) {
            if (!has_value) return ArgError.MissingValue;
            i += 1;
            const v = std.fmt.parseInt(u32, args[i], 10) catch return ArgError.BadValue;
            if (v < 1 or v > 600) return ArgError.BadValue;
            out.gop = v;
        } else {
            return ArgError.UnknownKey;
        }
    }
    if (sources > 1) return ArgError.OneSourceOnly;
    return out;
}

/// Середина окна или области на рабочем столе — по ней выбирается монитор (#121).
/// Монитор целиком выбран номером, ему точка не нужна.
/// Строка «источник молчит» с вероятной причиной (#132); `null` — молчание
/// объяснимо и говорить не о чем.
fn silenceReason(src: zigrec.source.Source, written: u64) ?[]const u8 {
    return switch (src) {
        .window => |h| switch (zigrec.source.windowVisibility(h)) {
            .minimized => "[rec] ВНИМАНИЕ: окно не отдаёт кадров — оно свёрнуто; разверните его, запись идёт\n",
            .covered => "[rec] ВНИМАНИЕ: окно не отдаёт кадров — оно закрыто другими окнами, а часть программ " ++
                "(визуализаторы, игры) под чужими окнами не рисует; откройте его, запись идёт\n",
            // Видимое окно без перерисовки — неподвижная картинка.
            .visible => null,
        },
        .monitor, .area => if (written > 0) null else "[rec] ВНИМАНИЕ: экран не отдаёт кадров — " ++
            "сеанс заблокирован, дисплей спит или за машиной никого; запись идёт\n",
    };
}

fn sourceCenter(src: zigrec.source.Source) ?zigrec.capture.Point {
    const r: zigrec.source.Rect = switch (src) {
        .monitor => return null,
        .area => |a| a,
        .window => |h| zigrec.source.windowArea(h) catch return null,
    };
    return .{
        .x = r.x + @as(i32, @intCast(r.width / 2)),
        .y = r.y + @as(i32, @intCast(r.height / 2)),
    };
}

/// Подпись к числам `monitors` и `windows` (#122): при масштабе 150 % логические
/// и физические точки расходятся в полтора раза, и без неё `--area` угадывают.
const pixels_note = "(координаты и размеры — в физических точках экрана, без масштаба Windows; --area принимает их же)\n";

fn listMonitors(allocator: std.mem.Allocator, w: anytype) !u8 {
    const list = zigrec.source.listMonitors(allocator) catch |err| {
        try w.print("не получилось перечислить мониторы: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(list);
    for (list) |m| {
        try w.print("монитор {d}: {d}x{d} в точке ({d},{d}), {d} Гц{s}\n", .{
            m.index,
            m.area.width,
            m.area.height,
            m.area.x,
            m.area.y,
            m.refresh_hz,
            if (m.primary) " — основной" else "",
        });
    }
    const d = zigrec.source.desktopArea();
    try w.print("рабочий стол целиком: {d}x{d} в точке ({d},{d})\n", .{ d.width, d.height, d.x, d.y });
    try w.writeAll(pixels_note);
    return 0;
}

fn listWindows(w: anytype) !u8 {
    // Сам список считает `source`: он же отдаёт его окну записи и серверу,
    // и три разных списка окон в одной программе разошлись бы на первой же
    // правке правила «какое окно показывать».
    var buf: [zigrec.source.max_windows]zigrec.source.WindowInfo = undefined;
    const list = zigrec.source.listWindows(&buf);
    for (list) |it| {
        try w.print("{d}x{d} в точке ({d},{d})  {s}{s}\n", .{
            it.area.width,
            it.area.height,
            it.area.x,
            it.area.y,
            it.name(),
            // Свёрнутое помечаем: у него и размер, и место — те, какими
            // оно развернётся, а не те, что сейчас на экране.
            if (it.minimized) "  (свёрнуто)" else "",
        });
    }
    if (list.len == 0) try w.writeAll("видимых окон не нашлось\n");
    try w.writeAll(pixels_note);
    return 0;
}

/// Куда идут кадры: в видео или в петлю.
///
/// Два вида записи различаются только приёмником. Разводить ради этого
/// два цикла захвата значило бы держать две копии одного и того же —
/// и чинить их по очереди.
const Sink = union(enum) {
    mp4: zigrec.encode.Writer,
    gif: zigrec.gif_write.Sink,

    fn writeFrame(self: *Sink, pixels: []const u8, stride: u32, at_ns: u64) !void {
        return switch (self.*) {
            .mp4 => |*enc| enc.writeFrame(pixels, stride, at_ns),
            .gif => |*sink| sink.writeFrame(pixels, stride, at_ns),
        };
    }

    fn abort(self: *Sink) void {
        switch (self.*) {
            .mp4 => |*enc| enc.abort(),
            .gif => |*sink| sink.deinit(),
        }
    }
};

/// Просят ли петлю вместо видео.
fn wantsGif(path: []const u8) bool {
    return std.ascii.endsWithIgnoreCase(path, ".gif");
}

/// Итог последней записи: кадры, потери, простои, секунды.
const RecordOutcome = struct {
    written: u64 = 0,
    dropped: u64 = 0,
    idle: u64 = 0,
    seconds: f64 = 0,
    /// Сколько всего просидели в захвате и в кодировщике — раскладка кадра.
    capture_ns: u64 = 0,
    encode_ns: u64 = 0,
};
var last_record: RecordOutcome = .{};

/// Заголовки Windows — для остановки извне (#124).
const winc = zigrec.win32.c;

/// Попросили закончить запись: Ctrl+C, Ctrl+Break, закрытие консоли (#124).
var stop_requested: std.atomic.Value(bool) = .init(false);
/// Файл записи закрыт — обработчику закрытия консоли можно отпускать процесс.
var record_closed: std.atomic.Value(bool) = .init(true);
/// Сколько обработчик закрытия консоли ждёт, пока файл закроется. Windows
/// даёт на это около пяти секунд, потом процесс убивает сама.
const close_wait_ms: u32 = 4500;
/// Как часто проверять стоп-файл: чаще незачем, а на каждом кадре — дорого.
const stop_file_poll_ns: u64 = 250 * std.time.ns_per_ms;

fn onConsoleCtrl(kind: winc.DWORD) callconv(.winapi) winc.BOOL {
    switch (kind) {
        winc.CTRL_C_EVENT, winc.CTRL_BREAK_EVENT => {
            stop_requested.store(true, .release);
            return 1;
        },
        winc.CTRL_CLOSE_EVENT, winc.CTRL_LOGOFF_EVENT, winc.CTRL_SHUTDOWN_EVENT => {
            // После возврата из обработчика закрытия процесс убивается —
            // значит, ждать здесь, пока запись допишет `moov`, иначе файл
            // пропадёт целиком, как при снятии задачи.
            stop_requested.store(true, .release);
            var waited: u32 = 0;
            while (!record_closed.load(.acquire) and waited < close_wait_ms) : (waited += 50) winc.Sleep(50);
            return 1;
        },
        else => return 0,
    }
}

/// Есть ли файл по пути (без открытия: его может держать тот, кто создал).
fn fileExists(path: []const u8) bool {
    var wbuf: [std.fs.max_path_bytes]u16 = undefined;
    const n = std.unicode.utf8ToUtf16Le(&wbuf, path) catch return false;
    if (n >= wbuf.len) return false;
    wbuf[n] = 0;
    return winc.GetFileAttributesW(@ptrCast(&wbuf)) != winc.INVALID_FILE_ATTRIBUTES;
}

/// Итог в JSON одной строкой (#125). Путь экранируется: в нём бывают
/// обратные косые и кавычки.
fn writeJson(w: anytype, path: []const u8, outcome: zigrec.errors.Outcome, facts: zigrec.errors.Facts, backend: []const u8) !void {
    try w.writeAll("{\"file\":\"");
    for (path) |ch| switch (ch) {
        '\\' => try w.writeAll("\\\\"),
        '"' => try w.writeAll("\\\""),
        else => try w.writeByte(ch),
    };
    try w.print("\",\"code\":{d},\"outcome\":\"{s}\",\"frames\":{d},\"dropped\":{d},\"drop_share\":{d:.4},\"file_s\":{d:.2},\"record_s\":{d:.2},\"backend\":\"{s}\"}}\n", .{
        outcome.exitCode(),
        @tagName(outcome),
        facts.frames,
        facts.dropped,
        facts.dropShare(),
        @as(f64, @floatFromInt(facts.file_ns)) / @as(f64, std.time.ns_per_s),
        @as(f64, @floatFromInt(facts.record_ns)) / @as(f64, std.time.ns_per_s),
        backend,
    });
}

fn record(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8, opt: RecordArgs) !u8 {
    try w.print("[rec] пишем в {s}: {d} с, до {d} кадров в секунду\n", .{ path, opt.seconds, opt.fps });
    try w.flush();

    // Файл проверяем первым: незачем поднимать захват и кодировщик, чтобы
    // в конце узнать, что файл открыт в плеере.
    zigrec.errors.ensureWritable(path) catch |err| {
        try w.print("[rec] ПРОВАЛ: {s}\n{s}\n", .{ path, explain(err) });
        return zigrec.errors.Outcome.failed.exitCode();
    };

    // Окно ищем до открытия захвата: если его нет, незачем и начинать.
    var src: zigrec.source.Source = .{ .monitor = opt.monitor };
    if (opt.window) |title| {
        const hwnd = zigrec.source.findWindow(title) catch |err| {
            try w.print("[rec] ПРОВАЛ: окно «{s}».\n{s}\n", .{ title, explain(err) });
            return 1;
        };
        src = .{ .window = hwnd };
    } else if (opt.area) |a| {
        src = .{ .area = a };
    }

    // WGC снимает само окно — без окна ему снимать нечего.
    const by_window = opt.backend == .wgc;
    if (by_window and !src.isWindow()) {
        try w.writeAll("[rec] ПРОВАЛ: путь WGC снимает окно — нужен ключ --window.\n");
        return 2;
    }

    // Автопанорама — через GDI: DXGI отдаёт кадр только когда стол
    // меняется, а область едет и при неподвижном столе — кадр нужен всегда.
    var cap = zigrec.capture.Capturer.open(allocator, .{
        .output = opt.monitor,
        .backend = if (opt.follow) .gdi else opt.backend,
        .always_frames = opt.follow,
        .window = if (src == .window) src.window else null,
        // Окно и область снимаются с того монитора, где лежат (#121).
        .at = sourceCenter(src),
    }) catch |err| {
        try w.print("[rec] ПРОВАЛ: захват не открылся.\n{s}\n", .{explain(err)});
        return 1;
    };
    defer cap.deinit();

    const screen = cap.frameSize();
    // Размер кадра выбирается один раз: кодировщик не умеет менять его на ходу.
    // Окно во время записи можно двигать — область поедет следом, — но если его
    // растянуть, в кадре останется прежний прямоугольник. У WGC кадр — само
    // окно: область с нуля, ехать ей некуда.
    const area = if (by_window) screen.atOrigin().evenSized() else zigrec.source.resolve(src, screen) catch |err| {
        try w.print("[rec] ПРОВАЛ: источник не определился.\n{s}\n", .{explain(err)});
        return 1;
    };
    try w.print("[rec] экран {d}x{d}, путь {s}\n", .{ screen.width, screen.height, cap.backend().label() });
    try warnAboutFps(allocator, w, opt.monitor, opt.fps);
    try w.print("[rec] снимаем {d}x{d} в точке ({d},{d})\n", .{ area.width, area.height, area.x, area.y });

    // Звук поднимаем до создания файла: писатель принимает новые потоки
    // только до начала записи. Тот же слой, что и у окна, — иначе формы
    // разъедутся, и «в окне звук есть, а из консоли нет» станет вопросом времени.
    var sound = zigrec.audio.Feeder{
        .sources = .{ .microphone = opt.sound, .system = opt.system, .separate = opt.separate },
    };
    defer sound.deinit(allocator);
    const origin_ns = zigrec.win32.nowNs();
    if (opt.sound or opt.system) {
        sound.start(allocator, origin_ns);
        if (opt.sound) {
            if (sound.failure) |err| {
                try w.print("[rec] микрофона не будет: {s}\n", .{explain(err)});
            } else {
                try w.print("[rec] звук: микрофон, {d} Гц, один канал, {d} кбит/с\n", .{
                    sound.settings.sample_rate,
                    sound.settings.bitrate_kbps,
                });
            }
        }
        if (opt.system) {
            if (sound.system_failure) |err| {
                try w.print("[rec] системного звука не будет: {s}\n", .{explain(err)});
            } else {
                try w.print("[rec] звук: и то, что идёт в колонки{s}\n", .{
                    if (sound.writesSeparately())
                        " — второй дорожкой, отдельно от микрофона"
                    else if (sound.track != null)
                        " — сводится с микрофоном в одну дорожку"
                    else
                        "",
                });
            }
        }
    }

    const settings = zigrec.encode.Settings{
        .fps = opt.fps,
        .preset = opt.preset,
        .bitrate_kbps = opt.bitrate_kbps,
        .gop = opt.gop,
        .audio = sound.encoderSettings(),
        .audio2 = sound.encoderSettings2(),
    };
    try w.print("[rec] пресет «{s}», битрейт {d} кбит/с, ключевой кадр каждые {d}\n", .{
        opt.preset.label(),
        settings.bitrate(area.width, area.height),
        opt.gop,
    });
    const to_gif = wantsGif(path);
    var enc: Sink = if (to_gif) .{
        .gif = zigrec.gif_write.Sink.create(allocator, area.width, area.height, opt.fps),
    } else .{
        .mp4 = zigrec.encode.Writer.create(path, area.width, area.height, settings) catch |err| {
            try w.print("[rec] ПРОВАЛ: кодировщик не создался.\n{s}\n", .{explain(err)});
            return 1;
        },
    };
    if (to_gif) {
        try w.print("[rec] пишем петлю GIF, до {d} кадров в секунду\n", .{enc.gif.fps});
        if (opt.sound) try w.writeAll("[rec] в GIF звука не бывает: он записан не будет\n");
    }

    // Курсор дорисовываем сами: захват отдаёт рабочий стол без него. Для этого
    // нужен свой буфер — кадр захвата открыт только на чтение.
    var painter = zigrec.cursor.Painter.init(allocator, .{ .draw = opt.cursor, .clicks = opt.clicks });
    defer painter.deinit();
    const out_stride = area.width * 4;
    const canvas: ?[]u8 = if (opt.cursor)
        try allocator.alloc(u8, @as(usize, out_stride) * area.height)
    else
        null;
    defer if (canvas) |b| allocator.free(b);

    const started = origin_ns;
    const until = started + @as(u64, opt.seconds) * std.time.ns_per_s;
    var written: u64 = 0;
    var moved: u64 = 0;
    var current = area;
    var follower = zigrec.pan.Follower.init(area);
    var last_pan_ns = zigrec.win32.nowNs();
    var panned: u32 = 0;

    // Слой событий (#89): курсор, кнопки, клавиши, окна — в файл рядом
    // с записью. Пишется всегда: это данные, а не картинка, и весят
    // килобайты; курсор в кадр — отдельная галочка, как и было.
    var layer_path_buf: [1024]u8 = undefined;
    const layer_path = zigrec.events.sidecarPath(&layer_path_buf, path);
    var layer_buf: [1 << 14]u8 = undefined;
    var layer_file = std.Io.Dir.cwd().createFile(io, layer_path, .{}) catch null;
    defer if (layer_file) |*f| f.close(io);
    var layer_fw = if (layer_file) |*f| f.writer(io, &layer_buf) else null;
    var layer = if (layer_fw) |*fw| (zigrec.events.Writer.init(&fw.interface) catch null) else null;
    var tap = zigrec.event_tap.Tap{};
    // GDI снимает только область (#30). Просим до `next`, а не после: кадр
    // живёт в поверхности GDI, и пересоздавать её под живым кадром нельзя.
    var focused = false;
    var capture_ns: u64 = 0;
    var encode_ns: u64 = 0;
    // Темп (#104): кадры сверх заказанной частоты не кодируем. Шестидесяти-
    // герцевый стол отдаёт шестьдесят кадров и при заказанных тридцати —
    // половина работы уходила в файл, которому она не нужна.
    // Главное — не снимать лишнего вовсе: темп уходит в сам захват (#104).
    // Если путь держит темп сам, свой отбор не нужен — двое за один темп
    // спорят и теряют кадры.
    const paced_inside = cap.setRate(opt.fps);
    var pacer = if (paced_inside) zigrec.pace.Pacer{} else zigrec.pace.Pacer.forFps(opt.fps);
    // Остановка извне (#124): Ctrl+C и закрытие консоли доводят запись до
    // конца, стоп-файл — то же для скрипта, которому сигнал не послать.
    stop_requested.store(false, .release);
    record_closed.store(false, .release);
    defer record_closed.store(true, .release);
    _ = winc.SetConsoleCtrlHandler(onConsoleCtrl, 1);
    defer _ = winc.SetConsoleCtrlHandler(onConsoleCtrl, 0);
    var next_stop_check: u64 = 0;
    var stopped_early = false;
    var source_lost = false;
    var silence_told = false;
    var last_frame_ns = started;
    while (zigrec.win32.nowNs() < until) {
        if (stop_requested.load(.acquire)) {
            stopped_early = true;
            break;
        }
        if (opt.stop_file) |sf| {
            const now = zigrec.win32.nowNs();
            if (now >= next_stop_check) {
                next_stop_check = now + stop_file_poll_ns;
                if (fileExists(sf)) {
                    stopped_early = true;
                    break;
                }
            }
        }
        focused = cap.focus(current);
        const before_next = zigrec.win32.nowNs();
        const frame = cap.next(200) catch |err| {
            // Источник пропал, но кадры уже есть (#126): дописать снятое и
            // закрыть файл, а не бросить его без `moov`.
            if (written > 0 and !to_gif) {
                try w.print("[rec] источник пропал на {d:.1} с ({s}): записанное сохраняется\n", .{
                    @as(f64, @floatFromInt(zigrec.win32.nowNs() - started)) / @as(f64, std.time.ns_per_s),
                    @errorName(err),
                });
                source_lost = true;
                break;
            }
            try w.print("[rec] ПРОВАЛ на захвате: {s}\n", .{@errorName(err)});
            enc.abort();
            return 1;
        } orelse {
            // Источник замолчал (#132) — сказать сразу, а не NothingCaptured
            // в конце. Окно: только если оно свёрнуто или закрыто — видимое
            // неподвижное окно тоже молчит, и это не беда. Экран: только если
            // не было ни кадра. Запись идёт дальше: окно могут открыть.
            if (!silence_told and zigrec.errors.silentFor(last_frame_ns, zigrec.win32.nowNs())) {
                if (silenceReason(src, written)) |reason| {
                    silence_told = true;
                    try w.writeAll(reason);
                }
            }
            continue;
        };
        capture_ns += zigrec.win32.nowNs() - before_next;

        // Лишний по темпу кадр отпускаем сразу: он не наш.
        if (!pacer.accept(frame.timestamp_ns)) {
            cap.release();
            continue;
        }

        // Окно могли подвинуть: берём его положение заново, а размер держим
        // прежний — иначе кадр перестанет соответствовать заголовку файла.
        // WGC отдаёт само окно, где бы оно ни стояло: двигать область незачем.
        if (src.isWindow() and !by_window) {
            if (zigrec.source.resolve(src, screen)) |now| {
                if (now.x != current.x or now.y != current.y) {
                    moved += 1;
                    current.x = now.x;
                    current.y = now.y;
                    current = current.clampTo(screen.width, screen.height);
                    current.width = area.width;
                    current.height = area.height;
                }
            } else |_| {}
        }
        if (layer) |*ev| {
            const cursor_at: ?zigrec.events.Point = if (painter.position()) |p| .{ .x = p.x, .y = p.y } else null;
            tap.sampleNow(ev, frame.timestamp_ns -| started, cursor_at, .{
                .x = screen.x + current.x,
                .y = screen.y + current.y,
                .width = current.width,
                .height = current.height,
            }) catch {
                // Слой — не запись: если диск кончился, кадры важнее.
                layer = null;
            };
        }

        // Автопанорама (#29): область едет за курсором, как в окне записи.
        if (opt.follow and src == .area) {
            if (painter.position()) |pos| {
                const now = zigrec.win32.nowNs();
                const next = follower.update(pos.x, pos.y, area.width, area.height, screen.width, screen.height, now -| last_pan_ns);
                last_pan_ns = now;
                if (next.x != current.x or next.y != current.y) panned += 1;
                current = next;
            }
        }

        // GDI снял только область (#30) — кадр берём с нуля; DXGI отдал весь
        // стол — режем. Если область сдвинулась после снимка, кадр отстаёт
        // на один — как и раньше при переносе окна.
        const view = zigrec.capture_types.cropView(frame.pixels, frame.stride, if (focused) current.atOrigin() else current);

        var pixels = view;
        var pixels_stride = frame.stride;
        if (canvas) |buf| {
            // Копируем построчно в свой буфер и рисуем поверх курсор.
            var row: u32 = 0;
            while (row < area.height) : (row += 1) {
                const from = @as(usize, row) * frame.stride;
                if (from + out_stride > view.len) break;
                @memcpy(buf[@as(usize, row) * out_stride ..][0..out_stride], view[from..][0..out_stride]);
            }
            painter.poll(frame.timestamp_ns);
            // Окно снимается целиком и под чужими окнами (WGC): курсор рисуем,
            // только если мышь лежит на нём самом (#116).
            const cursor_seen = if (by_window) blk: {
                const p = painter.position() orelse break :blk false;
                break :blk zigrec.source.windowOwnsPoint(src.window, p.x, p.y);
            } else true;
            if (cursor_seen) painter.paint(
                buf,
                out_stride,
                .{ .width = area.width, .height = area.height },
                screen.x + current.x,
                screen.y + current.y,
                frame.timestamp_ns,
            );
            pixels = buf;
            pixels_stride = out_stride;
        }

        // Время от начала записи, а не показания часов: с двумя дорожками
        // начало отсчёта должно быть одно на обе.
        const before_encode = zigrec.win32.nowNs();
        enc.writeFrame(pixels, pixels_stride, frame.timestamp_ns -| started) catch |err| {
            try w.print("[rec] ПРОВАЛ на кодировании: {s}\n", .{@errorName(err)});
            cap.release();
            enc.abort();
            return 1;
        };
        encode_ns += zigrec.win32.nowNs() - before_encode;
        written += 1;
        last_frame_ns = zigrec.win32.nowNs();
        cap.release();

        if (to_gif) continue;
        sound.drain(&enc.mp4) catch |err| {
            try w.print("[rec] ПРОВАЛ на звуке: {s}\n", .{@errorName(err)});
            enc.abort();
            return 1;
        };
    }

    if (!to_gif) sound.finish(&enc.mp4) catch |err| {
        try w.print("[rec] ПРОВАЛ на хвосте звука: {s}\n", .{@errorName(err)});
        enc.abort();
        return 1;
    };

    // Петля собирается в конце: палитра считается по всем кадрам сразу,
    // и пока не виден последний, неизвестно, какие цвета в неё войдут.
    if (to_gif) {
        defer enc.gif.deinit();
        const loop = enc.gif.finish(io, path) catch |err| {
            try w.print("[rec] ПРОВАЛ: петля не записалась: {s}\n", .{@errorName(err)});
            return zigrec.errors.Outcome.failed.exitCode();
        };
        try w.print("[rec] петля: кадров {d}, пропущено {d}, {d:.2} с, {d} КБ\n", .{
            loop.frames,
            loop.skipped,
            @as(f64, @floatFromInt(loop.total_ns)) / @as(f64, std.time.ns_per_s),
            (loop.bytes + 1023) / 1024,
        });
        if (enc.gif.full) {
            try w.writeAll("[rec] петля упёрлась в предел памяти: хвост записи в неё не вошёл\n");
        }
        if (opt.follow) try w.print("[rec] область ехала за курсором: сдвигов {d}\n", .{panned});
        try w.print("[rec] итог: {s}\n", .{zigrec.errors.Outcome.recorded.label()});
        return zigrec.errors.Outcome.recorded.exitCode();
    }

    // Последний кадр — до остановки (#133): неподвижная под конец картинка
    // иначе укорачивала файл.
    const summary = enc.mp4.finishAt(zigrec.win32.nowNs() -| started) catch |err| {
        try w.print("[rec] ПРОВАЛ на закрытии файла: {s}\n", .{@errorName(err)});
        return 1;
    };
    if (sound.active()) {
        try w.print("[rec] звука записано {d:.1} с, потеряно отсчётов {d}\n", .{
            sound.seconds(),
            sound.dropped(),
        });
    }
    const stats = cap.stats();
    const secs = @as(f64, @floatFromInt(zigrec.win32.nowNs() - started)) / @as(f64, std.time.ns_per_s);
    // Итог последней записи — для стенда сравнения (#30): он зовёт `record`
    // как есть и потом читает числа отсюда.
    last_record = .{ .written = written, .dropped = stats.dropped, .idle = stats.idle, .seconds = secs, .capture_ns = capture_ns, .encode_ns = encode_ns };
    try w.print("[rec] кадров записано {d} за {d:.1} с ({d:.1} в секунду), простоев {d}, потерь {d}\n", .{
        summary.frames,
        secs,
        @as(f64, @floatFromInt(summary.frames)) / @max(secs, 0.001),
        stats.idle,
        stats.dropped,
    });
    if (summary.frames == 0) {
        try w.writeAll("[rec] ПРОВАЛ: за всё время экран не отдал ни одного кадра.\n" ++
            "Скорее всего, на экране ничего не менялось или он не показывается совсем.\n");
        return zigrec.errors.Outcome.failed.exitCode();
    }
    try fastStart(io, allocator, w, path);
    if (try verifyMp4(io, allocator, w, path) != 0) return zigrec.errors.Outcome.failed.exitCode();

    // Итог — по фактам (#115 #123 #126): доля потерь, длительность файла
    // против времени записи, пропавший источник.
    const record_ns = zigrec.win32.nowNs() - started;
    const file_ns: u64 = if (zigrec.probe.read(io, allocator, path)) |info| info.duration_ns else |_| 0;
    const facts = zigrec.errors.Facts{
        .frames = summary.frames,
        .dropped = stats.dropped,
        .record_ns = record_ns,
        .file_ns = file_ns,
        .source_lost = source_lost,
    };
    const outcome = zigrec.errors.judge(facts);
    if (stopped_early) try w.print("[rec] остановлено раньше срока: на {d:.1} с\n", .{
        @as(f64, @floatFromInt(record_ns)) / @as(f64, std.time.ns_per_s),
    });
    try w.print("[rec] потерь {d:.2} %, в файле {d:.1} с при записи {d:.1} с\n", .{
        facts.dropShare() * 100.0,
        @as(f64, @floatFromInt(file_ns)) / @as(f64, std.time.ns_per_s),
        @as(f64, @floatFromInt(record_ns)) / @as(f64, std.time.ns_per_s),
    });
    if (facts.short()) try w.writeAll("[rec] ВНИМАНИЕ: файл короче записи — хвост не дописан (машина не успевала кодировать?)\n");
    if (cap.downgradeWaitMs() > 0) try w.print("[rec] путь понижен: DXGI молчал {d} мс, дальше снимал GDI\n", .{cap.downgradeWaitMs()});
    if (stats.produced > 0) try w.print("[rec] захват снял {d} кадров, в файл ушло {d}; снимок стоил {d:.1} мс\n", .{
        stats.produced,
        summary.frames,
        @as(f64, @floatFromInt(stats.snap_total_ns)) / @as(f64, @floatFromInt(@max(stats.produced, 1))) / 1e6,
    });
    if (pacer.skipped > 0) try w.print("[rec] сверх темпа отпущено {d} кадров: экран менялся чаще, чем {d} раз в секунду\n", .{ pacer.skipped, opt.fps });
    if (opt.follow) try w.print("[rec] область ехала за курсором: сдвигов {d}\n", .{panned});
    if (layer) |*ev| {
        if (layer_fw) |*fw| fw.interface.flush() catch {};
        try w.print("[rec] слой событий: {d} в {s}\n", .{ ev.count, layer_path });
    } else {
        try w.writeAll("[rec] слой событий не записан: файл рядом с записью не создался\n");
    }
    try w.print("[rec] итог: {s}\n", .{outcome.label()});
    if (opt.json) try writeJson(w, path, outcome, facts, cap.backend().label());
    return outcome.exitCode();
}

/// Уровень звука в файле. Проверка на известном сигнале, а не на живом
/// микрофоне: микрофон у каждого свой и шумит по-разному, а синус минус
/// двадцать децибел из файла — это проверяемое число.
fn audioCheck(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8, expect_db: ?f32) !u8 {
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1 << 28)) catch |err| {
        try w.print("[audio] ПРОВАЛ: не читается {s}: {s}\n", .{ path, @errorName(err) });
        return 1;
    };
    defer allocator.free(data);

    const info = zigrec.wav.parse(data) catch |err| {
        try w.print("[audio] ПРОВАЛ: {s} — {s}\n", .{ path, @errorName(err) });
        return 1;
    };
    const m = zigrec.wav.measure(data, info);
    try w.print("[audio] {s}: {d} Гц, каналов {d}, {d} бит, {d:.2} с\n", .{
        std.fs.path.basename(path),
        info.sample_rate,
        info.channels,
        info.bits,
        info.durationSeconds(),
    });
    try w.print("[audio] пик {d:.2} дБ, среднеквадратичное {d:.2} дБ\n", .{ m.dbfs(), m.rmsDbfs() });

    if (expect_db) |want| {
        const diff = @abs(m.dbfs() - want);
        try w.print("[audio] ожидали {d:.2} дБ, разница {d:.2} дБ\n", .{ want, diff });
        if (diff > 1.0) {
            try w.writeAll("[audio] ПРОВАЛ: уровень не сходится с ожидаемым\n");
            return 1;
        }
    }
    try w.writeAll("[audio] УРОВЕНЬ СОШЁЛСЯ\n");
    return 0;
}

/// Сверить вынутую звуковую дорожку со стендом: тот ли уровень и на месте ли
/// всплески.
///
/// Уровень отвечает на вопрос «звук вообще дошёл и не исказился». Моменты
/// всплесков — на вопрос «звук не разъехался с видео», и это то, что человек
/// замечает первым: губы отдельно, голос отдельно.
///
/// Два всплеска, а не один: по одному не отличить постоянный сдвиг (звук
/// начался позже) от накапливающегося дрейфа (звук идёт с другой скоростью).
fn audioSync(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8) !u8 {
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1 << 28)) catch |err| {
        try w.print("[sync] ПРОВАЛ: не читается {s}: {s}\n", .{ path, @errorName(err) });
        return 1;
    };
    defer allocator.free(data);

    const info = zigrec.wav.parse(data) catch |err| {
        try w.print("[sync] ПРОВАЛ: {s} — {s}\n", .{ path, @errorName(err) });
        return 1;
    };
    const frames = info.frameCount();
    try w.print("[sync] {s}: {d} Гц, каналов {d}, {d:.2} с\n", .{
        std.fs.path.basename(path),
        info.sample_rate,
        info.channels,
        info.durationSeconds(),
    });

    const samples = try allocator.alloc(f32, frames);
    defer allocator.free(samples);
    for (samples, 0..) |*v, i| v.* = zigrec.wav.sampleAt(data, info, i);

    const plan = zigrec.tone.benchPlan();
    const want_peak = plan.peak();
    var peak: f32 = 0;
    for (samples) |v| peak = @max(peak, @abs(v));
    const want_db = 20 * std.math.log10(want_peak);
    const got_db = if (peak > 0.00003) 20 * std.math.log10(peak) else -90;
    try w.print("[sync] уровень {d:.2} дБ, ожидали {d:.2} дБ\n", .{ got_db, want_db });
    if (@abs(got_db - want_db) > 3.0) {
        try w.writeAll("[sync] ПРОВАЛ: уровень дорожки не тот\n");
        return 1;
    }

    // Порог берём заметно ниже всплеска, но выше того, что кодировщик
    // оставляет в тишине.
    const threshold = want_peak * 0.25;
    var onsets: [8]u64 = undefined;
    const found = zigrec.tone.findOnsets(samples, info.sample_rate, threshold, 64, &onsets);
    if (found != plan.bursts.len) {
        try w.print("[sync] ПРОВАЛ: всплесков {d}, а должно быть {d}\n", .{ found, plan.bursts.len });
        return 1;
    }

    // Порог из цели эпика: рассинхрон меньше 20 миллисекунд.
    const tolerance_ms: f64 = 20;
    var worst: f64 = 0;
    for (plan.bursts, 0..) |b, i| {
        const got_ms = @as(f64, @floatFromInt(onsets[i])) / @as(f64, std.time.ns_per_ms);
        const want_ms = @as(f64, @floatFromInt(b.at_ns)) / @as(f64, std.time.ns_per_ms);
        const off = got_ms - want_ms;
        worst = @max(worst, @abs(off));
        try w.print("[sync] всплеск {d}: ждали {d:.0} мс, пришёл {d:.0} мс, сдвиг {d:.1} мс\n", .{
            i + 1, want_ms, got_ms, off,
        });
    }
    try w.print("[sync] наибольший рассинхрон {d:.1} мс, порог {d:.0} мс\n", .{ worst, tolerance_ms });
    if (worst > tolerance_ms) {
        try w.writeAll("[sync] ПРОВАЛ: звук разъехался с видео\n");
        return 1;
    }
    try w.writeAll("[sync] ЗВУК НА МЕСТЕ\n");
    return 0;
}

/// Самопроверка адресов прослушивания.
///
/// Разбор адреса проверен тестами, но «разбирается» и «на нём можно слушать»
/// — разные вещи. IPv6 на машине может быть выключен, петля `::1` может
/// не отвечать. Поэтому здесь мы по-настоящему поднимаем ожидание входящего
/// и по-настоящему в него стучимся.
///
/// `0.0.0.0` нарочно не трогаем: открывать порт всей сети ради самопроверки
/// невежливо. Что мы про него знаем, проверено тестами на разборе.
fn listenSmoke(io: std.Io, w: anytype, port: u16) !u8 {
    const listen = zigrec.listen;
    const interfaces = zigrec.interfaces;
    var bad: u8 = 0;

    // Список — тот же, что видит человек в настройках (#86): каждая его
    // строка обязана слушать и отвечать, иначе она обещает то, чего нет.
    var found: [interfaces.max_entries]interfaces.Entry = undefined;
    const got = interfaces.list(&found);
    var rows: [interfaces.max_choices]interfaces.Choice = undefined;
    const list = interfaces.choices(&rows, got);
    try w.print("[listen] адресов у машины: {d}, строк в списке: {d}\n", .{ got.len, list.len });
    for (got) |*e| try w.print("[listen]   {s} — {s}\n", .{ e.address(), e.ifaceName() });
    if (list.len < 4) {
        try w.writeAll("[listen] ПРОВАЛ: в списке нет даже постоянных строк\n");
        return 1;
    }
    // При «всех» угол окна называет адрес интерфейса — он должен быть
    // одним из найденных, а не выдуманным.
    const reach = interfaces.reachable("0.0.0.0", got);
    try w.print("[listen] при 0.0.0.0 наружу называем: {s}\n", .{reach});
    if (!std.mem.eql(u8, reach, "0.0.0.0")) {
        var known = false;
        for (got) |*e| {
            if (std.mem.eql(u8, e.address(), reach)) known = true;
        }
        if (!known) {
            try w.writeAll("[listen] ПРОВАЛ: названный наружу адрес не из найденных\n");
            bad = 1;
        }
    }

    for (list) |choice| {
        const address = choice.address;
        var where_buf: [listen.max_text + 8]u8 = undefined;
        const where = listen.write(&where_buf, address, port);

        var addr = listen.parse(address, port) catch {
            try w.print("[listen] ПРОВАЛ: {s} не разобрался\n", .{address});
            bad = 1;
            continue;
        };
        addr.setPort(port);

        var server = addr.listen(io, .{ .reuse_address = true }) catch |err| {
            // IPv6 на машине может быть выключен — это не поломка программы,
            // но и «работает» сказать нельзя. А адрес IPv4, который Windows
            // только что назвала поднятым, слушать обязан.
            try w.print("[listen] {s}: слушать не вышло ({s})\n", .{ where, @errorName(err) });
            if (choice.family == .ip4) {
                try w.print("[listen] ПРОВАЛ: {s} — {s} есть в списке, но не слушается\n", .{ address, choice.note });
                bad = 1;
            }
            continue;
        };
        defer server.deinit(io);

        const knock_at = zigrec.control.knockAddress(address);
        var to = listen.parse(knock_at, port) catch {
            try w.print("[listen] ПРОВАЛ: некуда стучаться для {s}\n", .{address});
            bad = 1;
            continue;
        };
        to.setPort(port);

        const stream = to.connect(io, .{ .mode = .stream, .protocol = .tcp }) catch |err| {
            try w.print("[listen] ПРОВАЛ: {s} слушает, но не отвечает ({s})\n", .{ where, @errorName(err) });
            bad = 1;
            continue;
        };
        stream.close(io);

        const scope = listen.scopeOf(address) catch listen.Scope.loopback;
        try w.print("[listen] {s} — {s} ({s}): слушает и отвечает\n", .{ where, scope.label(), choice.note });
    }

    if (bad != 0) return 1;
    try w.writeAll("[listen] АДРЕСА РАБОТАЮТ\n");
    return 0;
}

/// Ничего не делаем: стенду сообщения не нужны, он смотрит сам.
fn frameIgnored(userdata: ?*anyopaque) void {
    _ = userdata;
}

/// Самопроверка навигации.
///
/// Меряем то, ради чего всё затевалось: сколько времени занимает ПРОСЬБА
/// показать кадр. Это то, на что тратит время окно, и оно должно оставаться
/// малым независимо от того, сколько длится само раскодирование.
///
/// Раньше окно ждало декодер: щелчок по линейке на длинном файле
/// останавливал его на десятки миллисекунд, а перетаскивание указателя —
/// на всё время перетаскивания.
fn navSmoke(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8, asks: u32) !u8 {
    // Просим кадр такого размера, какой показывает окно редактора:
    // именно это и меряем.
    var service = zigrec.frames.Service{
        .allocator = allocator,
        .max_width = 960,
        .max_height = 540,
    };
    service.start(frameIgnored, null) catch |err| {
        try w.print("[nav] ПРОВАЛ: служба кадров не завелась: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer service.stop();

    // Изображаем перетаскивание указателя: просьбы идут одна за другой,
    // и декодер заведомо не успевает за ними.
    var worst_ns: u64 = 0;
    var total_ns: u64 = 0;
    var i: u32 = 0;
    while (i < asks) : (i += 1) {
        const when = @as(u64, i) * 250 * std.time.ns_per_ms;
        const before = zigrec.win32.nowNs();
        service.want(path, when);
        const spent = zigrec.win32.nowNs() -| before;
        worst_ns = @max(worst_ns, spent);
        total_ns += spent;
    }

    const worst_us = @as(f64, @floatFromInt(worst_ns)) / 1000.0;
    const mean_us = @as(f64, @floatFromInt(total_ns / @max(asks, 1))) / 1000.0;
    try w.print("[nav] просьб {d}: в среднем {d:.1} мкс, худшая {d:.1} мкс\n", .{
        asks,
        mean_us,
        worst_us,
    });

    // Порог с большим запасом: на просьбу уходит переписать несколько сотен
    // байт под замком. Если это занимает миллисекунды — значит, окно опять
    // чего-то ждёт.
    const limit_us: f64 = 2000;
    if (worst_us > limit_us) {
        try w.print("[nav] ПРОВАЛ: просьба заняла {d:.1} мкс — окно чего-то ждёт\n", .{worst_us});
        return 1;
    }

    // Кадр должен в итоге прийти. Ждём его, но не вечно.
    const started = zigrec.win32.nowNs();
    var arrived = false;
    const Peek = struct {
        got: *bool,
        at: *u64,
        size: *[2]u32,
        fn look(self: @This(), pixels: []const u8, width: u32, height: u32, at_ns: u64) void {
            _ = pixels;
            self.got.* = true;
            self.at.* = at_ns;
            self.size.* = .{ width, height };
        }
    };
    var at_ns: u64 = 0;
    var size: [2]u32 = .{ 0, 0 };
    while (zigrec.win32.nowNs() -| started < 10 * std.time.ns_per_s) {
        if (service.withFrame(Peek, .{ .got = &arrived, .at = &at_ns, .size = &size }, Peek.look)) break;
        io.sleep(.fromMilliseconds(10), .awake) catch break;
    }
    const waited_ms = @as(f64, @floatFromInt(zigrec.win32.nowNs() -| started)) / @as(f64, std.time.ns_per_ms);

    if (!arrived) {
        if (service.trouble) |err| {
            try w.print("[nav] кадр не пришёл: {s} — в файле может не быть картинки\n", .{@errorName(err)});
            return 0;
        }
        try w.writeAll("[nav] ПРОВАЛ: кадр так и не пришёл\n");
        return 1;
    }

    try w.print("[nav] кадр пришёл через {d:.0} мс, время кадра {d:.2} с, размер {d}x{d}\n", .{
        waited_ms,
        @as(f64, @floatFromInt(at_ns)) / @as(f64, std.time.ns_per_s),
        size[0],
        size[1],
    });
    try w.print("[nav] просьб в очереди осталось {d}\n", .{service.behind()});
    // #83: при прокрутке волна обязана меняться. Столбик считался по доле
    // от видимого прямоугольника клипа, а не по времени под пикселем,
    // и пользователь возил ползунок, глядя на одну и ту же картинку.
    // Проверяем тем же правилом, каким рисует окно: строим огибающую
    // с ростом громкости вдоль файла и смотрим на один пиксель до и после
    // прокрутки.
    {
        const wf = zigrec.waveform;
        const total: usize = wf.bucketsFor(600 * std.time.ns_per_s) * 10;
        var builder = try wf.Builder.init(allocator, total, 600 * std.time.ns_per_s);
        var k: usize = 0;
        while (k < total) : (k += 1) {
            builder.push(@as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(total)));
        }
        var env = builder.finish();
        defer env.deinit(allocator);
        const clip = zigrec.timeline.Clip{ .at_ns = 0, .in_ns = 0, .len_ns = 600 * std.time.ns_per_s };
        const x = zigrec.editor_view.header_w + 120;
        const before = zigrec.editor_view.View{ .at_ns = 0, .ns_per_px = std.time.ns_per_s };
        const after = zigrec.editor_view.View{ .at_ns = 300 * std.time.ns_per_s, .ns_per_px = std.time.ns_per_s };
        const s0 = zigrec.editor_view.waveSpanAt(before, clip, x).?;
        const s1 = zigrec.editor_view.waveSpanAt(after, clip, x).?;
        const h0 = env.relativeBetween(s0.from_ns, s0.to_ns);
        const h1 = env.relativeBetween(s1.from_ns, s1.to_ns);
        try w.print("[nav] волна под одним пикселем до и после прокрутки: {d:.2} → {d:.2}\n", .{ h0, h1 });
        if (h1 <= h0) {
            try w.writeAll("[nav] ПРОВАЛ: прокрутка не меняет волну под пикселем\n");
            return 1;
        }

        // #84: при приближении соседние столбики отличаются, а не идут
        // блоками. Масштаб — две минуты на экран, как на снимке пользователя:
        // столбец огибающей в 50 мс короче пикселя в 200 мс, и волна
        // с ростом громкости обязана расти на каждом пикселе.
        const close = zigrec.editor_view.View{ .at_ns = 300 * std.time.ns_per_s, .ns_per_px = 200 * std.time.ns_per_ms };
        var grew: usize = 0;
        var px: i32 = 0;
        while (px < 100) : (px += 1) {
            const sa = zigrec.editor_view.waveSpanAt(close, clip, x + px).?;
            const sb = zigrec.editor_view.waveSpanAt(close, clip, x + px + 1).?;
            if (env.relativeBetween(sb.from_ns, sb.to_ns) > env.relativeBetween(sa.from_ns, sa.to_ns)) grew += 1;
        }
        try w.print("[nav] при приближении из 100 соседних столбиков выше предыдущего: {d}\n", .{grew});
        if (grew < 90) {
            try w.writeAll("[nav] ПРОВАЛ: волна при приближении идёт блоками — разрешение огибающей мало́\n");
            return 1;
        }
    }

    try w.writeAll("[nav] ОКНО НЕ ЖДЁТ ДЕКОДЕР\n");
    return 0;
}

/// Самопроверка открытия файла.
///
/// Редактор узнаёт, что внутри файла, не поднимая в память полуторагигабайтную
/// запись целиком: сначала голова, потом — если оглавление в хвосте — проход
/// по цепочке боксов. Быстрый путь обязан сказать то же, что и полное чтение:
/// иначе окно покажет одну длительность, а играть будет другая.
///
/// Заодно меряем время. «Моментально» — это число, а не ощущение.
fn openSmoke(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8) !u8 {
    const media = zigrec.media;

    const t0 = zigrec.win32.nowNs();
    const quick = media.read(io, allocator, path) catch |err| {
        try w.print("[open] ПРОВАЛ: файл не открылся: {s}\n", .{media.explain(err)});
        return 1;
    };
    const t1 = zigrec.win32.nowNs();

    // Полное чтение — то, как было раньше: поднять весь файл и разобрать.
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1 << 31)) catch |err| {
        try w.print("[open] ПРОВАЛ: файл не читается целиком: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(data);
    const full = media.parse(data) catch |err| {
        try w.print("[open] ПРОВАЛ: разбор целого файла: {s}\n", .{media.explain(err)});
        return 1;
    };
    const t2 = zigrec.win32.nowNs();

    const fast_ms = @as(f64, @floatFromInt(t1 - t0)) / @as(f64, std.time.ns_per_ms);
    const slow_ms = @as(f64, @floatFromInt(t2 - t1)) / @as(f64, std.time.ns_per_ms);
    try w.print("[open] {s}: {s}, {d:.2} с, дорожек {d}, {d} МБ\n", .{
        std.fs.path.basename(path),
        full.format.label(),
        full.seconds(),
        full.count,
        data.len / (1 << 20),
    });
    try w.print("[open] быстрый путь {d:.1} мс, полное чтение {d:.1} мс\n", .{ fast_ms, slow_ms });
    if (fast_ms > 0.01) {
        try w.print("[open] быстрее в {d:.0} раз\n", .{slow_ms / fast_ms});
    }

    // Сойтись должны и длительность, и состав дорожек: по ним рисуется
    // таймлайн, и разойдясь, они разойдутся молча.
    if (quick.count != full.count) {
        try w.print("[open] ПРОВАЛ: дорожек быстрым путём {d}, полным {d}\n", .{ quick.count, full.count });
        return 1;
    }
    if (quick.duration_ns != full.duration_ns) {
        try w.print("[open] ПРОВАЛ: длительность быстрым путём {d}, полным {d}\n", .{
            quick.duration_ns,
            full.duration_ns,
        });
        return 1;
    }
    for (quick.list(), full.list()) |a, b| {
        if (a.kind != b.kind or a.width != b.width or a.height != b.height) {
            try w.writeAll("[open] ПРОВАЛ: дорожка быстрым путём не та, что полным\n");
            return 1;
        }
    }
    try w.writeAll("[open] БЫСТРЫЙ ПУТЬ СОШЁЛСЯ С ПОЛНЫМ\n");
    return 0;
}

/// Самопроверка раскладки окна.
///
/// «Кнопка не влезла» — ошибка, которую видно только глазами и только
/// на той машине, где рамка окна оказалась толще ожидаемой. Стенд собирает
/// настоящее окно, не показывая его, и проходит по всем его кнопкам:
/// вылезло ли что-нибудь за рабочую часть.
fn uiSmoke(allocator: std.mem.Allocator, w: anytype) !u8 {
    var bad: u8 = 0;
    if (try checkWindow(w, "запись", zigrec.ui.checkLayout(allocator))) bad = 1;
    if (try checkWindow(w, "редактор", zigrec.editor.checkLayout(allocator))) bad = 1;

    // Столбцы панели дублей (#26): при минимальной ширине панели.
    var tcols: [zigrec.editor.takes_columns.len]zigrec.editor.ColumnFit = undefined;
    for (zigrec.editor.takesColumnFits(&tcols)) |fit| {
        try w.print("[ui] столбец дублей «{s}»: надо {d}, есть {d}\n", .{ fit.label, fit.need, fit.have });
        if (!fit.fits()) {
            try w.print("[ui] ПРОВАЛ: заголовок столбца дублей «{s}» не влезает\n", .{fit.label});
            bad = 1;
        }
    }

    // Столбцы панели меток тоже рисуются своим кодом.
    var cols: [zigrec.editor.marks_columns.len]zigrec.editor.ColumnFit = undefined;
    for (zigrec.editor.marksColumnFits(&cols)) |fit| {
        try w.print("[ui] столбец меток «{s}»: надо {d}, есть {d}\n", .{ fit.label, fit.need, fit.have });
        if (!fit.fits()) {
            try w.print("[ui] ПРОВАЛ: заголовок столбца «{s}» не влезает, не хватает {d} точек\n", .{
                fit.label,
                fit.need - fit.have,
            });
            bad = 1;
        }
    }

    // Поле для броска рисуется своим кодом, и его подпись не проходит
    // через замер органов управления: обрезанную подпись там видно только
    // глазами. Меряем её настоящим шрифтом.
    const drop = zigrec.ui.dropLabelFit();
    try w.print("[ui] подпись поля броска «{s}»: надо {d}, есть {d}\n", .{
        zigrec.ui.drop_text,
        drop.need,
        drop.have,
    });
    if (!drop.fits()) {
        try w.print("[ui] ПРОВАЛ: подпись поля броска не влезает, не хватает {d} точек\n", .{
            drop.need - drop.have,
        });
        bad = 1;
    }

    // Кнопка области носит на себе выбранный формат (#146): подпись стала
    // длиннее, а место под неё то же.
    const area_fit = zigrec.ui.areaButtonFit();
    try w.print("[ui] подпись кнопки области с форматом: надо {d}, есть {d}\n", .{ area_fit.need, area_fit.have });
    if (!area_fit.fits()) {
        try w.print("[ui] ПРОВАЛ: формат не влезает на кнопку, не хватает {d} точек\n", .{area_fit.need - area_fit.have});
        bad = 1;
    }

    // Подписи окна настроек: при 125 % DPI они обрезались (#86).
    var set_fits: [zigrec.ui.settings_labels.len]zigrec.ui.DropFit = undefined;
    for (zigrec.ui.settingsLabelsFit(&set_fits), 0..) |fit, i| {
        try w.print("[ui] подпись настроек «{s}»: надо {d}, есть {d}\n", .{ zigrec.ui.settings_labels[i].text, fit.need, fit.have });
        if (!fit.fits()) {
            try w.print("[ui] ПРОВАЛ: подпись настроек не влезает, не хватает {d} точек\n", .{fit.need - fit.have});
            bad = 1;
        }
    }

    // Угол MCP (#86): с адресом интерфейса и числом просьб надпись длиннее
    // прежней, а места под неё столько же.
    const corner_fit = zigrec.ui.cornerFit();
    try w.print("[ui] надпись угла MCP «{s}»: надо {d}, есть {d}\n", .{
        zigrec.mcp_corner.longest_text,
        corner_fit.need,
        corner_fit.have,
    });
    if (!corner_fit.fits()) {
        try w.print("[ui] ПРОВАЛ: надпись угла MCP не влезает, не хватает {d} точек\n", .{
            corner_fit.need - corner_fit.have,
        });
        bad = 1;
    }

    if (bad != 0) return 1;
    try w.writeAll("[ui] ОБА ОКНА В ПОРЯДКЕ\n");
    return 0;
}

/// Разобрать замер одного окна. Возвращает, было ли плохо.
fn checkWindow(w: anytype, name: []const u8, got: anyerror!zigrec.ui.Layout) !bool {
    const layout = got catch |err| {
        try w.print("[ui] ПРОВАЛ: окно «{s}» не собралось: {s}\n", .{ name, @errorName(err) });
        return true;
    };

    try w.print("[ui] {s}: рабочая часть {d}x{d}, органов управления {d}\n", .{
        name,
        layout.client_w,
        layout.client_h,
        layout.controls,
    });
    if (layout.controls == 0) {
        try w.print("[ui] ПРОВАЛ: в окне «{s}» не оказалось ни одной кнопки\n", .{name});
        return true;
    }
    if (layout.outside > 0) {
        try w.print("[ui] ПРОВАЛ: в окне «{s}» не поместилось {d}; вниз на {d}, вправо на {d} точек\n", .{
            name,
            layout.outside,
            layout.over_bottom,
            layout.over_right,
        });
        return true;
    }
    if (layout.overlaps > 0) {
        try w.print("[ui] ПРОВАЛ: в окне «{s}» кнопки налезают друг на друга: {d}; худшее — «{s}» и «{s}», {d} точек площадью\n", .{
            name,
            layout.overlaps,
            layout.overlapA(),
            layout.overlapB(),
            layout.worst_overlap,
        });
        return true;
    }
    if (layout.cramped > 0) {
        try w.print("[ui] ПРОВАЛ: в окне «{s}» подписей не влезло: {d}; худшая «{s}» — надо {d}, есть {d} точек\n", .{
            name,
            layout.cramped,
            layout.crampedText(),
            layout.cramped_need,
            layout.cramped_have,
        });
        return true;
    }
    if (!layout.clips_children) {
        // Без этого признака фон окна ложится поверх кнопок, и они
        // перерисовываются следом: на обновлении по таймеру это мигание.
        try w.print("[ui] ПРОВАЛ: окно «{s}» рисует под своими кнопками — они будут мигать\n", .{name});
        return true;
    }
    try w.print("[ui] {s}: всё поместилось, подписи влезают, под кнопками не рисуем\n", .{name});
    return false;
}

/// Самопроверка захвата системного звука.
///
/// Задача #20. Loopback нечем проверить, если ничего не играет: он молчит
/// вместе с колонками. Поэтому стенд сам играет известный план — два
/// всплеска по сто миллисекунд с интервалом в секунду — и одновременно
/// слушает то, что уходит в колонки. Дальше сверяется числом: всплесков
/// два, интервал между ними — секунда с допуском в двадцать миллисекунд,
/// уровень — заданный, и во времени дорожки нет дыр, хотя между всплесками
/// колонки молчали. Последнее — самое важное: без заполнения тишины
/// loopback отдал бы два всплеска подряд, и звук уехал бы вперёд на всю
/// паузу.
///
/// Без устройства вывода проверять нечего — об этом говорится словами,
/// и стенд не считается проваленным: сборочная машина бывает без колонок.
fn loopbackSmoke(allocator: std.mem.Allocator, w: anytype) !u8 {
    const mic = zigrec.mic;
    const tone = zigrec.tone;
    const rate: u32 = 48_000;
    const seconds: f32 = 3.2;

    const track = try allocator.create(zigrec.track.Track);
    defer allocator.destroy(track);
    track.* = .{};

    var cap = mic.Capture{ .kind = .system, .track = track, .track_rate = rate };
    cap.start() catch |err| {
        try w.print("[loopback] ПРОВАЛ: захват не поднялся: {s}\n", .{explain(err)});
        return 1;
    };
    zigrec.win32.c.Sleep(250);
    if (cap.failure) |err| {
        if (err == error.NoSpeakers) {
            try w.writeAll("[loopback] пропущено: нет устройства вывода, ловить нечего\n");
            return 0;
        }
        try w.print("[loopback] ПРОВАЛ: захват не поднялся: {s}\n", .{explain(err)});
        return 1;
    }
    try w.print("[loopback] слушаем колонки: {d} Гц, каналов {d}\n", .{ cap.sample_rate, cap.channels });

    // Играем план. Захват идёт в своём потоке, пока мы тут ждём.
    const plan = tone.benchPlan();
    zigrec.play.playPlan(plan, seconds) catch |err| {
        cap.stop();
        if (err == error.NoSpeakers) {
            try w.writeAll("[loopback] пропущено: нет устройства вывода, играть некуда\n");
            return 0;
        }
        try w.print("[loopback] ПРОВАЛ: не удалось проиграть план: {s}\n", .{zigrec.play.explain(err)});
        return 1;
    };
    zigrec.win32.c.Sleep(300);
    cap.stop();

    // Забираем всё, что поймали.
    const room: usize = @intFromFloat((seconds + 1.0) * @as(f32, @floatFromInt(rate)));
    const got = try allocator.alloc(i16, room);
    defer allocator.free(got);
    var n: usize = 0;
    while (n < got.len) {
        const k = track.pop(got[n..]);
        if (k == 0) break;
        n += k;
    }
    const samples = try allocator.alloc(f32, n);
    defer allocator.free(samples);
    for (got[0..n], 0..) |v, i| samples[i] = @as(f32, @floatFromInt(v)) / 32768.0;

    const got_seconds = @as(f64, @floatFromInt(n)) / @as(f64, rate);
    try w.print("[loopback] поймано {d} отсчётов — {d:.2} с, потерь {d}\n", .{
        n,
        got_seconds,
        track.dropped.load(.monotonic),
    });

    var bad: u8 = 0;

    // 1. Дыр во времени нет: поймано примерно столько, сколько играли.
    // Меньше — значит паузы между всплесками не заполнены тишиной.
    if (got_seconds < seconds * 0.9) {
        try w.print("[loopback] ПРОВАЛ: играли {d:.1} с, а в дорожке только {d:.2} с — дыры во времени\n", .{
            seconds,
            got_seconds,
        });
        bad = 1;
    }

    // 2. Всплесков два, и ровно через секунду.
    var onsets: [8]u64 = undefined;
    const found = tone.findOnsets(samples, rate, 0.1, rate / 100, &onsets);
    try w.print("[loopback] всплесков найдено {d}\n", .{found});
    if (found < 2) {
        try w.writeAll("[loopback] ПРОВАЛ: всплески не пойманы\n");
        bad = 1;
    } else {
        const gap_ms = @as(f64, @floatFromInt(onsets[1] - onsets[0])) / 1e6;
        try w.print("[loopback] интервал между всплесками {d:.1} мс (ждали 1000)\n", .{gap_ms});
        if (@abs(gap_ms - 1000.0) > 20.0) {
            try w.writeAll("[loopback] ПРОВАЛ: интервал уехал больше чем на 20 мс\n");
            bad = 1;
        }
    }

    // 3. Уровень — заданный: половина шкалы, минус шесть децибел, с допуском
    // на громкость системы. Если Windows режет громкость вдвое — это
    // тоже надо знать, а не гадать потом, почему запись тихая.
    var peak: f32 = 0;
    for (samples) |v| peak = @max(peak, @abs(v));
    const peak_db = if (peak > 0) 20.0 * std.math.log10(peak) else -120.0;
    try w.print("[loopback] пик {d:.1} дБ (ждали около -6)\n", .{peak_db});
    if (peak_db < -30.0) {
        try w.writeAll("[loopback] ПРОВАЛ: слишком тихо — loopback поймал не то или громкость выведена в ноль\n");
        bad = 1;
    }

    if (bad != 0) return 1;
    try w.writeAll("[loopback] СИСТЕМНЫЙ ЗВУК ЛОВИТСЯ, ВРЕМЯ БЕЗ ДЫР\n");
    return 0;
}

/// Сквозная проверка системного звука: loopback → подача → mp4.
///
/// Первая половина стенда ловит звук в память; этого мало — в файл он идёт
/// через подачу, смешение и кодировщик, и любой из них может молча потерять
/// звук. Здесь пишется настоящий mp4 с чёрными кадрами и системным звуком,
/// пока в колонках играет план. Проверяет его чужой декодер: `check.cmd`
/// вынимает дорожку ffmpeg-ом и меряет интервал всплесков.
fn loopbackRecord(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8, separate: bool) !u8 {
    const bench = zigrec.testbench;
    const width: u32 = bench.min_width;
    const height: u32 = 64;
    const fps: u32 = 30;
    const seconds: f32 = 3.2;

    // Врозь — значит и микрофон тоже: две дорожки из двух источников.
    // Микрофона на стенде может не быть — тогда об этом говорится,
    // и проверяется одна дорожка, а не две.
    var sound = zigrec.audio.Feeder{
        .sources = .{ .microphone = separate, .system = true, .separate = separate },
    };
    defer sound.deinit(allocator);
    const origin_ns = zigrec.win32.nowNs();
    sound.start(allocator, origin_ns);
    if (separate) {
        if (sound.failure) |err| {
            try w.print("[loopback] микрофона нет ({s}): будет одна дорожка вместо двух\n", .{explain(err)});
        } else {
            try w.writeAll("[loopback] микрофон и колонки пишутся двумя дорожками\n");
        }
    }
    if (sound.system_failure) |err| {
        if (err == error.NoSpeakers) {
            try w.writeAll("[loopback] запись пропущена: нет устройства вывода\n");
            return 0;
        }
        try w.print("[loopback] ПРОВАЛ: системный звук не поднялся: {s}\n", .{explain(err)});
        return 1;
    }

    const screen = try bench.Screen.init(width, height, fps);
    const buf = try allocator.alloc(u8, screen.frameBytes());
    defer allocator.free(buf);

    var enc = zigrec.encode.Writer.create(path, width, height, .{
        .fps = fps,
        .audio = sound.encoderSettings(),
        .audio2 = sound.encoderSettings2(),
    }) catch |err| {
        try w.print("[loopback] ПРОВАЛ: кодировщик не создался: {s}\n", .{explain(err)});
        return 1;
    };

    // План играет в своём потоке: вывод звука ждёт устройство, а кадры
    // и слив звука должны идти своим чередом, как при настоящей записи.
    const Player = struct {
        fn run(plan: zigrec.tone.Plan, secs: f32, failed: *bool) void {
            zigrec.play.playPlan(plan, secs) catch {
                failed.* = true;
            };
        }
    };
    var play_failed = false;
    const player = std.Thread.spawn(.{}, Player.run, .{ zigrec.tone.benchPlan(), seconds, &play_failed }) catch {
        try w.writeAll("[loopback] ПРОВАЛ: поток вывода звука не завёлся\n");
        return 1;
    };

    const frame_ns = std.time.ns_per_s / fps;
    const frames: u32 = @intFromFloat(seconds * @as(f32, @floatFromInt(fps)));
    var i: u32 = 0;
    while (i < frames) : (i += 1) {
        try screen.render(buf, i);
        enc.writeFrame(buf, width * 4, frame_ns * i) catch |err| {
            try w.print("[loopback] ПРОВАЛ на кадре {d}: {s}\n", .{ i, @errorName(err) });
            return 1;
        };
        try sound.drain(&enc);
        // Кадры идут в реальном времени: звук ловится по часам, и файл
        // должен получить его в том же темпе, что при настоящей записи.
        io.sleep(.fromMilliseconds(1000 / fps), .awake) catch {};
    }
    player.join();
    try sound.finish(&enc);

    const summary = enc.finish() catch |err| {
        try w.print("[loopback] ПРОВАЛ на закрытии файла: {s}\n", .{@errorName(err)});
        return 1;
    };
    try w.print("[loopback] записано кадров {d}, звуковых отсчётов {d} ({d:.2} с), потерь {d}\n", .{
        summary.frames,
        summary.audio_samples,
        sound.seconds(),
        sound.dropped(),
    });
    if (summary.audio2_samples > 0) {
        try w.print("[loopback] вторая дорожка: {d} отсчётов ({d:.2} с)\n", .{
            summary.audio2_samples,
            sound.seconds2(),
        });
    }
    // Дрейф чинится понемногу; сколько всего пришлось поправить — это
    // число, а не ощущение, и оно должно быть в отчёте.
    try w.print("[loopback] правка дрейфа: вставлено {d}, выброшено {d} отсчётов\n", .{
        sound.drift_inserted,
        sound.drift_dropped,
    });
    if (play_failed) {
        try w.writeAll("[loopback] ПРОВАЛ: план не доиграл\n");
        return 1;
    }
    if (summary.audio_samples == 0) {
        try w.writeAll("[loopback] ПРОВАЛ: звуковая дорожка в файле пуста\n");
        return 1;
    }
    // Звука должно быть примерно столько, сколько шла запись: короче —
    // значит паузы колонок не заполнены и звук уехал вперёд.
    if (sound.seconds() < seconds * 0.85) {
        try w.print("[loopback] ПРОВАЛ: писали {d:.1} с, а звука в файле {d:.2} с — дыры во времени\n", .{
            seconds,
            sound.seconds(),
        });
        return 1;
    }

    try fastStart(io, allocator, w, path);
    try w.print("[loopback] ФАЙЛ ЗАПИСАН: {s}\n", .{path});
    return 0;
}

/// Интервал между двумя всплесками в WAV — для дорожек, чьё начало
/// не привязано к нулю записи.
///
/// `audio-sync` меряет всплески от начала файла; тут начало — момент,
/// когда стенд поднял захват, и до первого всплеска лежит неизвестная
/// задержка устройства. Зато интервал между всплесками от неё не зависит:
/// если он уехал, значит, время дорожки сломано.
fn onsetSpacing(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8, want_ms: u64) !u8 {
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1 << 28)) catch |err| {
        try w.print("[spacing] ПРОВАЛ: не читается {s}: {s}\n", .{ path, @errorName(err) });
        return 1;
    };
    defer allocator.free(data);
    const info = zigrec.wav.parse(data) catch |err| {
        try w.print("[spacing] ПРОВАЛ: {s} — не WAV: {s}\n", .{ path, @errorName(err) });
        return 1;
    };
    const count = info.frameCount();
    const samples = try allocator.alloc(f32, count);
    defer allocator.free(samples);
    for (samples, 0..) |*v, k| v.* = zigrec.wav.sampleAt(data, info, k);

    var onsets: [8]u64 = undefined;
    const found = zigrec.tone.findOnsets(samples, info.sample_rate, 0.1, info.sample_rate / 100, &onsets);
    try w.print("[spacing] {s}: {d:.2} с, всплесков {d}\n", .{
        std.fs.path.basename(path),
        info.durationSeconds(),
        found,
    });
    if (found < 2) {
        try w.writeAll("[spacing] ПРОВАЛ: нужны хотя бы два всплеска\n");
        return 1;
    }
    const gap_ms = @as(f64, @floatFromInt(onsets[1] - onsets[0])) / 1e6;
    try w.print("[spacing] интервал {d:.1} мс, ждали {d} ± 20\n", .{ gap_ms, want_ms });
    if (@abs(gap_ms - @as(f64, @floatFromInt(want_ms))) > 20.0) {
        try w.writeAll("[spacing] ПРОВАЛ: интервал уехал больше чем на 20 мс\n");
        return 1;
    }
    try w.writeAll("[spacing] ИНТЕРВАЛ СОШЁЛСЯ\n");
    return 0;
}

/// Сколько в файле звуковых дорожек — нашим читателем.
///
/// Задача #21. Две дорожки в одном mp4 — это не «звук есть», это «плеер
/// видит две и даёт переключать». Наш `probe` разбирает `moov` сам;
/// чужой счёт делает ffmpeg в `check.cmd`. Сойтись должны оба.
fn tracksCheck(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8, want_audio: u32) !u8 {
    const info = zigrec.probe.read(io, allocator, path) catch |err| {
        try w.print("[tracks] ПРОВАЛ: {s} не разбирается: {s}\n", .{ path, @errorName(err) });
        return 1;
    };
    var audio: u32 = 0;
    var video: u32 = 0;
    for (info.tracks[0..info.count]) |t| {
        switch (t.kind) {
            .audio => audio += 1,
            .video => video += 1,
            .other => {},
        }
        try w.print("[tracks]  {d}. {s}: {s}, {d:.2} с\n", .{ t.id, t.kind.label(), t.codecLabel(), t.seconds() });
    }
    try w.print("[tracks] {s}: видео {d}, звуковых {d} (ждали {d})\n", .{
        std.fs.path.basename(path),
        video,
        audio,
        want_audio,
    });
    if (audio != want_audio) {
        try w.writeAll("[tracks] ПРОВАЛ: звуковых дорожек не столько\n");
        return 1;
    }
    try w.writeAll("[tracks] ДОРОЖЕК СТОЛЬКО, СКОЛЬКО ЖДАЛИ\n");
    return 0;
}

/// Самопроверка значков.
///
/// Задача #81. Значок, который никто не нарисовал, выглядит в окне так же,
/// как значок, который просто не туда поставили: пустое место. А два
/// похожих значка — это два названия одного и того же, и выбор между ними
/// ничего не значит.
///
/// Здесь все значки сводятся в одну картинку — её можно посмотреть
/// глазами, — и тут же сверяются числом: ни один не пустой, ни один
/// не залит целиком, ни один не повторяет соседа.
fn iconsSmoke(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8) !u8 {
    const icons = zigrec.icons;
    const side = icons.side;
    // Клетка значка в точках: значок выходит 36 на 36 — разглядеть можно.
    const cell = 3;
    const pad = 6;
    const box = side * cell + pad * 2;

    const count = icons.all.len;
    const width: u32 = @intCast(box * @as(i32, @intCast(count)));
    const height: u32 = @intCast(box);

    const pixels = try allocator.alloc(u8, @as(usize, width) * height * 4);
    defer allocator.free(pixels);
    // Белый фон: значки тёмные, и на белом их видно так же, как в окне.
    @memset(pixels, 0xFF);

    var bad: u8 = 0;
    for (icons.all, 0..) |icon, n| {
        const weight = icon.weight();
        try w.print("[icons] {s}: клеток {d} из {d}\n", .{ icon.label(), weight, side * side });
        if (weight == 0) {
            try w.print("[icons] ПРОВАЛ: значок «{s}» не нарисован вовсе\n", .{icon.label()});
            bad = 1;
        }
        if (weight == side * side) {
            try w.print("[icons] ПРОВАЛ: значок «{s}» залит целиком — это не значок\n", .{icon.label()});
            bad = 1;
        }

        const x0 = @as(usize, @intCast(box * @as(i32, @intCast(n)))) + pad;
        var row: usize = 0;
        while (row < side) : (row += 1) {
            var col: usize = 0;
            while (col < side) : (col += 1) {
                if (!icon.on(row, col)) continue;
                var dy: usize = 0;
                while (dy < cell) : (dy += 1) {
                    var dx: usize = 0;
                    while (dx < cell) : (dx += 1) {
                        const px = x0 + col * cell + dx;
                        const py = pad + row * cell + dy;
                        const at = (py * @as(usize, width) + px) * 4;
                        pixels[at + 0] = 0x20;
                        pixels[at + 1] = 0x20;
                        pixels[at + 2] = 0x20;
                        pixels[at + 3] = 0xFF;
                    }
                }
            }
        }
    }

    // Пары: ни один значок не повторяет другого.
    for (icons.all, 0..) |a, i| {
        for (icons.all[0..i]) |b| {
            var same: usize = 0;
            for (0..side) |r| {
                for (0..side) |col| {
                    if (a.on(r, col) == b.on(r, col)) same += 1;
                }
            }
            const part = same * 100 / (side * side);
            if (part >= 95) {
                try w.print("[icons] ПРОВАЛ: «{s}» и «{s}» совпадают на {d}%\n", .{
                    a.label(),
                    b.label(),
                    part,
                });
                bad = 1;
            }
        }
    }

    const png_bytes = zigrec.png.fromBgra(allocator, pixels, width, height, width * 4) catch |err| {
        try w.print("[icons] ПРОВАЛ: картинка не собралась: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(png_bytes);

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = png_bytes }) catch |err| {
        try w.print("[icons] ПРОВАЛ: не записывается {s}: {s}\n", .{ path, @errorName(err) });
        return 1;
    };
    try w.print("[icons] {d} значков сведены в {s}: {d}x{d}, {d} байт\n", .{
        count,
        std.fs.path.basename(path),
        width,
        height,
        png_bytes.len,
    });

    // Строки меню рисуем мы сами, и живое меню не снять: оно исчезает
    // от щелчка мимо. Рисуем те же строки в память и смотрим на пиксели.
    var rows: [zigrec.editor.menu_rows]zigrec.editor.RowCheck = undefined;
    const drawn = zigrec.editor.checkMenuRows(&rows);
    if (drawn.len == 0) {
        try w.writeAll("[icons] ПРОВАЛ: строки меню не нарисовались вовсе\n");
        bad = 1;
    }
    for (drawn) |row| {
        if (row.ok()) continue;
        if (row.want != 0) {
            try w.print("[icons] ПРОВАЛ: строка цвета «{s}»: ждали 0x{X:0>6}, вышло 0x{X:0>6}\n", .{
                row.what,
                row.want,
                row.middle,
            });
        } else {
            try w.print("[icons] ПРОВАЛ: строка значка «{s}» нарисовалась пустой\n", .{row.what});
        }
        bad = 1;
    }
    try w.print("[icons] строк меню нарисовано {d}, все не пустые\n", .{drawn.len});

    if (bad != 0) return 1;
    try w.writeAll("[icons] ВСЕ ЗНАЧКИ НАРИСОВАНЫ И РАЗЛИЧИМЫ\n");
    return 0;
}

/// Самопроверка захвата окна.
///
/// Задача #77. Съёмка окна обещает две вещи: окно найдётся по части
/// заголовка и область поедет за ним. Вторую глазами не проверить —
/// надо двигать окно и смотреть, что снимается, — поэтому здесь окно
/// заводится своё, двигается и спрашивается заново.
fn windowSmoke(io: std.Io, w: anytype) !u8 {
    const c = zigrec.win32.c;
    const source = zigrec.source;
    if (@import("builtin").os.tag != .windows) {
        try w.writeAll("[window] пропущено: не Windows\n");
        return 0;
    }

    // Без этого Windows отдаёт растянутые координаты при масштабе больше
    // ста процентов, и сравнение размеров разъезжается на ровном месте.
    _ = c.SetProcessDPIAware();

    const class_name = "ZigRecWindowSmoke";
    const title = "Стенд захвата окна · ZigRec";
    const want_w: i32 = 640;
    const want_h: i32 = 360;

    const hinst: c.HINSTANCE = @ptrCast(c.GetModuleHandleW(null));
    var wc = std.mem.zeroes(c.WNDCLASSEXW);
    wc.cbSize = @sizeOf(c.WNDCLASSEXW);
    wc.lpfnWndProc = smokeWindowProc;
    wc.hInstance = hinst;
    wc.lpszClassName = std.unicode.utf8ToUtf16LeStringLiteral(class_name);
    wc.hbrBackground = @ptrFromInt(@as(usize, c.COLOR_BTNFACE) + 1);
    _ = c.RegisterClassExW(&wc);

    const hwnd = c.CreateWindowExW(
        c.WS_EX_TOPMOST | c.WS_EX_TOOLWINDOW | c.WS_EX_NOACTIVATE,
        std.unicode.utf8ToUtf16LeStringLiteral(class_name),
        std.unicode.utf8ToUtf16LeStringLiteral(title),
        c.WS_POPUP | c.WS_BORDER,
        120,
        120,
        want_w,
        want_h,
        null,
        null,
        hinst,
        null,
    ) orelse {
        try w.writeAll("[window] ПРОВАЛ: своё окно не создалось\n");
        return 1;
    };
    defer _ = c.DestroyWindow(hwnd);
    _ = c.ShowWindow(hwnd, c.SW_SHOWNOACTIVATE);
    _ = c.UpdateWindow(hwnd);
    // Окну надо дать проявиться: список окон читает то, что показано,
    // а показ происходит не в тот же миг, когда об этом попросили.
    io.sleep(.fromMilliseconds(200), .awake) catch {};

    var bad: u8 = 0;

    // 1. Окно есть в списке, и с теми размерами, какие заказаны.
    var seen: [zigrec.source.max_windows]source.WindowInfo = undefined;
    const list = source.listWindows(&seen);
    try w.print("[window] видимых окон в списке: {d}\n", .{list.len});

    var found: ?source.WindowInfo = null;
    for (list) |it| {
        if (std.mem.indexOf(u8, it.name(), "Стенд захвата окна") != null) found = it;
    }
    const mine = found orelse {
        try w.writeAll("[window] ПРОВАЛ: своего же окна нет в списке\n");
        return 1;
    };
    try w.print("[window] нашлось: «{s}» {d}x{d} в точке ({d},{d})\n", .{
        mine.name(),
        mine.area.width,
        mine.area.height,
        mine.area.x,
        mine.area.y,
    });
    if (mine.area.width != want_w or mine.area.height != want_h) {
        try w.print("[window] ПРОВАЛ: заказывали {d}x{d}, а в списке {d}x{d}\n", .{
            want_w, want_h, mine.area.width, mine.area.height,
        });
        bad = 1;
    }

    // 2. Поиск по части заголовка приводит к тому же окну.
    const by_title = source.findWindow("Стенд захвата") catch {
        try w.writeAll("[window] ПРОВАЛ: по части заголовка окно не находится\n");
        return 1;
    };
    if (by_title != mine.handle) {
        try w.writeAll("[window] ПРОВАЛ: по заголовку нашлось другое окно\n");
        bad = 1;
    } else {
        try w.writeAll("[window] по части заголовка нашлось то же самое окно\n");
    }

    // 3. Окно из списка считается живым, и его номер годится для ответа.
    if (!source.stillThere(mine.handle)) {
        try w.writeAll("[window] ПРОВАЛ: окно из списка считается закрытым\n");
        bad = 1;
    }
    if (mine.number() == 0) {
        try w.writeAll("[window] ПРОВАЛ: у окна из списка нулевой номер\n");
        bad = 1;
    }

    // 4. Главное обещание: область едет за окном.
    const moved_to_x: i32 = 400;
    const moved_to_y: i32 = 260;
    _ = c.SetWindowPos(hwnd, null, moved_to_x, moved_to_y, 0, 0, c.SWP_NOSIZE | c.SWP_NOZORDER | c.SWP_NOACTIVATE);
    io.sleep(.fromMilliseconds(200), .awake) catch {};

    const after = source.windowArea(hwnd) catch {
        try w.writeAll("[window] ПРОВАЛ: после переноса размеры окна не читаются\n");
        return 1;
    };
    try w.print("[window] подвинули на ({d},{d}) — снимаемая область стала ({d},{d}) {d}x{d}\n", .{
        moved_to_x, moved_to_y, after.x, after.y, after.width, after.height,
    });
    // Прямоугольник берётся без невидимой рамки тени, поэтому он не обязан
    // совпасть с заказанным пиксель в пиксель; важно, что он поехал.
    if (after.x == mine.area.x and after.y == mine.area.y) {
        try w.writeAll("[window] ПРОВАЛ: окно подвинули, а область осталась на месте\n");
        bad = 1;
    }
    if (after.width != mine.area.width or after.height != mine.area.height) {
        try w.writeAll("[window] ПРОВАЛ: от переноса изменился размер области\n");
        bad = 1;
    }

    // 5. Закрытое окно должно опознаваться как закрытое, а не писаться в пустоту.
    _ = c.DestroyWindow(hwnd);
    io.sleep(.fromMilliseconds(100), .awake) catch {};
    if (source.stillThere(mine.handle)) {
        try w.writeAll("[window] ПРОВАЛ: закрытое окно всё ещё считается живым\n");
        bad = 1;
    } else {
        try w.writeAll("[window] закрытое окно опознано как закрытое\n");
    }

    if (bad != 0) return 1;
    try w.writeAll("[window] ЗАХВАТ ОКНА В ПОРЯДКЕ\n");
    return 0;
}

fn smokeWindowProc(hwnd: zigrec.win32.c.HWND, msg: zigrec.win32.c.UINT, wp: zigrec.win32.c.WPARAM, lp: zigrec.win32.c.LPARAM) callconv(.winapi) zigrec.win32.c.LRESULT {
    return zigrec.win32.c.DefWindowProcW(hwnd, msg, wp, lp);
}

/// Самопроверка громкости и кривой громкости.
///
/// Задачи #61 и #62. Нарисованная кривая, которая ничего не меняет в звуке, —
/// это картинка, а не громкость, и отличить одно от другого по окну нельзя:
/// линия выглядит одинаково в обоих случаях.
///
/// Здесь берётся настоящий файл, из него собирается проект с известной
/// кривой — от «как записано» в начале до минус двадцати децибел в конце, —
/// смесь пишется в WAV, и он тут же читается обратно и меряется. Ожидаемые
/// числа считаются из той же кривой, но другим путём: не сведением,
/// а прямо по правилу.
fn mixSmoke(
    io: std.Io,
    allocator: std.mem.Allocator,
    w: anytype,
    src_path: []const u8,
    out_path: []const u8,
) !u8 {
    const timeline = zigrec.timeline;
    const volume = zigrec.volume;
    const mixdown = zigrec.mixdown;

    var audio = zigrec.audio_read.read(allocator, src_path) catch |err| {
        try w.print("[mix] ПРОВАЛ: {s}: {s}\n", .{ src_path, zigrec.audio_read.explain(err) });
        return 1;
    };
    defer audio.deinit(allocator);

    const len_ns = audio.durationNs();
    try w.print("[mix] исходник {s}: {d} Гц, {d:.2} с, отсчётов {d}\n", .{
        std.fs.path.basename(src_path),
        audio.rate,
        @as(f64, @floatFromInt(len_ns)) / @as(f64, std.time.ns_per_s),
        audio.samples.len,
    });
    if (len_ns < std.time.ns_per_s) {
        try w.writeAll("[mix] ПРОВАЛ: исходник короче секунды, мерить нечего\n");
        return 1;
    }

    // Проект: одна звуковая дорожка, весь исходник, кривая вниз на 20 дБ.
    const project = try allocator.create(timeline.Project);
    defer allocator.destroy(project);
    project.* = .{};
    const source = project.addSource(src_path, len_ns) catch return 1;
    _ = project.addTrack(.audio, "Звук") catch return 1;
    project.place(0, source, 0, len_ns) catch return 1;

    const fall_db10: volume.Db10 = -200;
    _ = project.addCurvePoint(0, 0, 0) catch return 1;
    _ = project.addCurvePoint(0, len_ns, fall_db10) catch return 1;

    const rate: u32 = audio.rate;
    const out = try allocator.alloc(i16, mixdown.totalSamples(project, rate));
    defer allocator.free(out);
    mixdown.mix(project, rate, &.{audio.forMix()}, out);

    // Пишем WAV и тут же читаем его обратно: мерить то, что осталось
    // в памяти, значит не проверить ни запись, ни чтение.
    {
        var buf: [1 << 16]u8 = undefined;
        var file = std.Io.Dir.cwd().createFile(io, out_path, .{}) catch |err| {
            try w.print("[mix] ПРОВАЛ: не создать {s}: {s}\n", .{ out_path, @errorName(err) });
            return 1;
        };
        defer file.close(io);
        var fw = file.writer(io, &buf);
        zigrec.wav.write(&fw.interface, rate, 1, out) catch |err| {
            try w.print("[mix] ПРОВАЛ: не записать WAV: {s}\n", .{@errorName(err)});
            return 1;
        };
        fw.interface.flush() catch {};
    }

    const back = std.Io.Dir.cwd().readFileAlloc(io, out_path, allocator, .limited(1 << 28)) catch |err| {
        try w.print("[mix] ПРОВАЛ: не прочитать обратно {s}: {s}\n", .{ out_path, @errorName(err) });
        return 1;
    };
    defer allocator.free(back);
    const info = zigrec.wav.parse(back) catch |err| {
        try w.print("[mix] ПРОВАЛ: свой же WAV не разбирается: {s}\n", .{@errorName(err)});
        return 1;
    };
    try w.print("[mix] смесь {s}: {d} Гц, каналов {d}, {d:.2} с\n", .{
        std.fs.path.basename(out_path),
        info.sample_rate,
        info.channels,
        info.durationSeconds(),
    });

    // Уровень исходника: всё считается относительно него, а не абсолютно.
    const src_peak = peakOfFloats(audio.samples);
    const src_db = toDb(src_peak);
    try w.print("[mix] уровень исходника {d:.2} дБ\n", .{src_db});

    var bad: u8 = 0;
    const spots = [_]f64{ 0.05, 0.5, 0.95 };
    for (spots) |part| {
        const at_ns: u64 = @intFromFloat(@as(f64, @floatFromInt(len_ns)) * part);
        // Ожидание считаем прямо по правилу кривой, а не спрашиваем сведение:
        // иначе стенд проверял бы сведение им же самим.
        const want_db = src_db + @as(f64, @floatFromInt(fall_db10)) / 10.0 * part;

        const from = @as(usize, @intFromFloat(@as(f64, @floatFromInt(at_ns)) / 1e9 * @as(f64, @floatFromInt(rate))));
        const window = rate / 20; // двадцатая доля секунды
        const got_db = toDb(peakOfPcm(back, info, from, window));

        const gap = @abs(got_db - want_db);
        try w.print("[mix] на {d:.0}%: ждали {d:.2} дБ, вышло {d:.2} дБ, разница {d:.2}\n", .{
            part * 100, want_db, got_db, gap,
        });
        // Полтора децибела: смесь берёт пик в короткое окно, и на спуске
        // он неизбежно чуть отстаёт от точного значения кривой.
        if (gap > 1.5) {
            try w.writeAll("[mix] ПРОВАЛ: громкость не пошла по кривой\n");
            bad = 1;
        }
    }

    // И проверка проверки: без кривой те же места должны звучать ровно.
    project.setCurveOn(0, false) catch {};
    mixdown.mix(project, rate, &.{audio.forMix()}, out);
    const flat_start = toDb(peakOfSamples(out, 0, rate / 20));
    const flat_end = toDb(peakOfSamples(out, out.len -| (rate / 20), rate / 20));
    try w.print("[mix] без кривой: начало {d:.2} дБ, конец {d:.2} дБ\n", .{ flat_start, flat_end });
    if (@abs(flat_start - flat_end) > 1.0) {
        try w.writeAll("[mix] ПРОВАЛ: выключенная кривая всё равно меняет громкость\n");
        bad = 1;
    }
    if (@abs(flat_start - src_db) > 1.0) {
        try w.writeAll("[mix] ПРОВАЛ: без правок смесь звучит не как исходник\n");
        bad = 1;
    }

    if (bad != 0) return 1;
    try w.writeAll("[mix] ГРОМКОСТЬ ИДЁТ ПО КРИВОЙ\n");
    return 0;
}

fn toDb(peak: f64) f64 {
    if (peak <= 0) return -120;
    return 20.0 * std.math.log10(peak);
}

fn peakOfFloats(samples: []const f32) f64 {
    var peak: f64 = 0;
    for (samples) |v| {
        const a = @abs(@as(f64, v));
        if (a > peak) peak = a;
    }
    return peak;
}

fn peakOfSamples(samples: []const i16, from: usize, count: usize) f64 {
    var peak: f64 = 0;
    var i = from;
    const to = @min(from + count, samples.len);
    while (i < to) : (i += 1) {
        const v = @as(f64, @floatFromInt(samples[i]));
        const a = if (v < 0) -v / 32768.0 else v / 32767.0;
        if (a > peak) peak = a;
    }
    return peak;
}

fn peakOfPcm(bytes: []const u8, info: zigrec.wav.Info, from: usize, count: usize) f64 {
    var peak: f64 = 0;
    var i = from;
    const to = @min(from + count, info.frameCount());
    while (i < to) : (i += 1) {
        const a = @abs(@as(f64, zigrec.wav.sampleAt(bytes, info, i)));
        if (a > peak) peak = a;
    }
    return peak;
}

/// Самопроверка пульта управления съёмкой.
///
/// Где пульту встать, проверено тестами: это чистый счёт. А вот влезут ли
/// подписи в кнопки, чистый счёт знать не может — он меряет буквы прикидкой,
/// не имея на руках шрифта. Разойдётся прикидка с делом — подпись обрежется
/// молча, и на пульте окажется кнопка «⏸ Пауз». Здесь ширину меряет сама
/// Windows тем шрифтом, которым пульт и рисуется.
fn remoteSmoke(w: anytype) !u8 {
    const remote = zigrec.remote;

    var fits: [zigrec.remote_win.label_count]zigrec.remote_win.Fit = undefined;
    const measured = zigrec.remote_win.measureLabels(&fits);
    if (measured.len == 0) {
        try w.writeAll("[remote] ПРОВАЛ: не удалось получить контекст рисования\n");
        return 1;
    }

    var bad: u8 = 0;

    // Сперва проверим саму проверку шрифта: если она не видит заведомо
    // отсутствующего знака, то и настоящую дырку не увидит, и стенд будет
    // молча зелёным.
    if (zigrec.remote_win.probeMissing(zigrec.remote_win.absent_probe) == 0) {
        try w.writeAll("[remote] ПРОВАЛ: проверка шрифта не видит даже заведомо отсутствующего знака\n");
        bad = 1;
    } else {
        try w.writeAll("[remote] проверка шрифта жива: отсутствующий знак опознан\n");
    }

    for (measured) |fit| {
        try w.print("[remote] «{s}»: надо {d}, есть {d}\n", .{ fit.label, fit.need, fit.have });
        if (fit.need > fit.have) {
            try w.print("[remote] ПРОВАЛ: подпись «{s}» не влезает, не хватает {d} точек\n", .{
                fit.label,
                fit.need - fit.have,
            });
            bad = 1;
        }
        if (fit.missing != 0) {
            // Пустой квадратик вместо знака той же ширины: вёрстка сходится,
            // а кнопка становится непонятной.
            var one: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(fit.missing, &one) catch 0;
            try w.print("[remote] ПРОВАЛ: в подписи «{s}» знака «{s}» нет в шрифте — будет пустой квадратик\n", .{
                fit.label,
                one[0..len],
            });
            bad = 1;
        }
    }

    // Кнопки не должны налезать ни друг на друга, ни на полоску звука,
    // ни на край пульта.
    const stop = remote.stopButton();
    const pause = remote.pauseButton();
    const bar = remote.levelBar();
    try w.print("[remote] пульт {d}x{d}: стоп {d}..{d}, пауза {d}..{d}, полоска до {d}\n", .{
        remote.width,
        remote.height,
        stop.x,
        stop.right(),
        pause.x,
        pause.right(),
        bar.right(),
    });
    if (stop.overlaps(pause) or bar.overlaps(stop) or bar.overlaps(pause) or
        pause.right() > remote.width or pause.bottom() > remote.height)
    {
        try w.writeAll("[remote] ПРОВАЛ: на пульте всё налезает друг на друга\n");
        bad = 1;
    }

    // И пульт не должен вставать в снимаемую область.
    const screen = remote.Rect{ .x = 0, .y = 0, .w = 1920, .h = 1080 };
    const area = remote.Rect{ .x = 300, .y = 200, .w = 900, .h = 500 };
    const spot = remote.place(screen, area, false);
    try w.print("[remote] область {d},{d} {d}x{d} — пульт встал в {d},{d}\n", .{
        area.x, area.y, area.w, area.h, spot.at.x, spot.at.y,
    });
    if (spot.in_frame or spot.at.overlaps(area)) {
        try w.writeAll("[remote] ПРОВАЛ: пульт встал в кадр\n");
        bad = 1;
    }

    if (bad != 0) return 1;
    try w.writeAll("[remote] ПУЛЬТ В ПОРЯДКЕ\n");
    return 0;
}

/// Самопроверка сочетания клавиш.
///
/// Разбор строки проверен тестами, но числа в нём наши собственные:
/// и модификаторы, и коды клавиш выписаны из заголовков Windows руками.
/// Сойдутся ли они с настоящими, в памяти не проверишь — а не сойдутся,
/// и клавиша просто не сработает или сработает не та. Здесь мы просим
/// Windows зарегистрировать сочетание по-настоящему и тут же отпускаем.
fn hotkeySmoke(w: anytype, text: []const u8) !u8 {
    const hotkey = zigrec.hotkey;
    const c = zigrec.win32.c;

    const keys = hotkey.parse(text) catch |err| {
        try w.print("[hotkey] ПРОВАЛ: «{s}» — {s}\n", .{ text, hotkey.explain(err) });
        return 1;
    };

    var back: [hotkey.max_text]u8 = undefined;
    try w.print("[hotkey] разобрано: {s} (модификаторы 0x{X:0>4}, клавиша 0x{X:0>2})\n", .{
        keys.write(&back),
        keys.modifiers(),
        keys.key,
    });

    // Записанное словами должно читаться обратно тем же: иначе в настройках
    // окажется не то, что человек ввёл.
    if (!std.mem.eql(u8, keys.write(&back), text)) {
        try w.print("[hotkey] ПРОВАЛ: обратно вышло «{s}» вместо «{s}»\n", .{ keys.write(&back), text });
        return 1;
    }

    // Регистрируем на поток, без окна: окно тут ни при чём, проверяются числа.
    const id: c_int = 0x5A16;
    if (c.RegisterHotKey(null, id, keys.modifiers(), keys.key) == 0) {
        try w.print("[hotkey] {s} занято другой программой — Windows его не отдала\n", .{text});
        // Это не провал проекта: сочетание может быть законно занято.
        // Но и «работает» сказать нельзя, поэтому говорим как есть.
        try w.writeAll("[hotkey] ЗАНЯТО\n");
        return 0;
    }
    _ = c.UnregisterHotKey(null, id);
    try w.print("[hotkey] Windows приняла {s} и отпустила\n", .{text});
    try w.writeAll("[hotkey] СОЧЕТАНИЕ РАБОТАЕТ\n");
    return 0;
}

/// Самопроверка записи GIF.
///
/// Кадры берём у стенда, а не с экрана: в них записан номер, и его можно
/// прочитать обратно. Записываем петлю, читаем её своим разбором и сверяем
/// числа — а в `check.cmd` ту же петлю распаковывает ffmpeg, и номера
/// кадров достаёт `verify-raw`. Своим кодом проверять свою же запись
/// значит не заметить ошибки, сделанной в обе стороны одинаково.
fn gifWriteSmoke(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8, frames: u32) !u8 {
    const bench = zigrec.testbench;
    const width: u32 = bench.min_width;
    const height: u32 = 64;

    const screen = bench.Screen.init(width, height, 20) catch {
        try w.writeAll("[gifw] ПРОВАЛ: кадр меньше таймкода\n");
        return 1;
    };

    const list = try allocator.alloc(zigrec.gif.Frame, frames);
    defer {
        for (list) |f| allocator.free(f.pixels);
        allocator.free(list);
    }
    for (list, 0..) |*f, i| {
        const px = try allocator.alloc(u8, screen.frameBytes());
        try screen.render(px, @intCast(i + 1));
        f.* = .{ .delay_ns = 50 * std.time.ns_per_ms, .pixels = px };
    }

    const bytes = zigrec.gif_write.encode(allocator, list, width, height, 0) catch |err| {
        try w.print("[gifw] ПРОВАЛ: петля не собралась: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(bytes);

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = bytes }) catch |err| {
        try w.print("[gifw] ПРОВАЛ: не записывается {s}: {s}\n", .{ path, @errorName(err) });
        return 1;
    };
    try w.print("[gifw] {d} кадров {d}x{d} → {d} байт ({d} байт на кадр)\n", .{
        frames,
        width,
        height,
        bytes.len,
        bytes.len / frames,
    });

    var back = zigrec.gif.decode(allocator, bytes) catch |err| {
        try w.print("[gifw] ПРОВАЛ: своя же петля не читается: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer back.deinit(allocator);

    if (back.frames.len != frames or back.width != width or back.height != height) {
        try w.print("[gifw] ПРОВАЛ: вернулось {d} кадров {d}x{d}\n", .{
            back.frames.len,
            back.width,
            back.height,
        });
        return 1;
    }

    // Главное: номер кадра должен пережить палитру и сжатие. Таймкод
    // нарисован чёрным по белому, и если он не читается — палитра съела
    // то, ради чего кадр и записывали.
    var wrong: usize = 0;
    for (back.frames, 0..) |f, i| {
        const got = bench.readIndex(f.pixels, width, width * 4) catch {
            wrong += 1;
            continue;
        };
        if (got != i + 1) wrong += 1;
    }
    if (wrong > 0) {
        try w.print("[gifw] ПРОВАЛ: номер не прочитался в {d} кадрах из {d}\n", .{ wrong, frames });
        return 1;
    }
    try w.print("[gifw] номера всех {d} кадров целы\n", .{frames});
    try w.print("[gifw] петля {d:.2} с, крутится бесконечно: {s}\n", .{
        @as(f64, @floatFromInt(back.totalNs())) / @as(f64, std.time.ns_per_s),
        if (back.loops == 0) "да" else "нет",
    });
    try w.writeAll("[gifw] ПЕТЛЯ ЗАПИСАНА\n");
    return 0;
}

/// Самопроверка чтения GIF.
///
/// Файл делает чужая программа, читаем своим разбором, а первый кадр
/// кладём в png — его снова читает чужая программа. Так замыкается круг:
/// ошибка в нашем понимании формата не может пройти незамеченной, потому
/// что на обоих концах стоит не наш код.
fn gifSmoke(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8, png_path: ?[]const u8) !u8 {
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1 << 28)) catch |err| {
        try w.print("[gif] ПРОВАЛ: не читается {s}: {s}\n", .{ path, @errorName(err) });
        return 1;
    };
    defer allocator.free(data);

    const counted = zigrec.gif.measure(data) catch |err| {
        try w.print("[gif] ПРОВАЛ: не пересчитались кадры: {s}\n", .{@errorName(err)});
        return 1;
    };
    try w.print("[gif] {s}: {d}x{d}, кадров {d}, петля {d:.2} с\n", .{
        std.fs.path.basename(path),
        counted.width,
        counted.height,
        counted.frames,
        @as(f64, @floatFromInt(counted.total_ns)) / @as(f64, std.time.ns_per_s),
    });

    var img = zigrec.gif.decode(allocator, data) catch |err| {
        try w.print("[gif] ПРОВАЛ: не разобрался: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer img.deinit(allocator);

    // Быстрый пересчёт и полный разбор обязаны сойтись: иначе числа
    // в окне будут не те, что на экране.
    if (img.frames.len != counted.frames or img.totalNs() != counted.total_ns or
        img.width != counted.width or img.height != counted.height)
    {
        try w.writeAll("[gif] ПРОВАЛ: быстрый пересчёт разошёлся с полным разбором\n");
        return 1;
    }
    try w.writeAll("[gif] пересчёт сошёлся с разбором\n");

    // Ни один кадр не должен быть пустым: чёрный холст означает, что
    // распаковка отдала нули, а мы этого не заметили.
    var empty: usize = 0;
    for (img.frames) |f| {
        var lit: usize = 0;
        for (f.pixels) |b| {
            if (b != 0) lit += 1;
        }
        if (lit * 20 < f.pixels.len) empty += 1;
    }
    if (empty > 0) {
        try w.print("[gif] ПРОВАЛ: почти пустых кадров {d} из {d}\n", .{ empty, img.frames.len });
        return 1;
    }
    try w.print("[gif] все {d} кадров с картинкой\n", .{img.frames.len});

    if (png_path) |out_path| {
        const bytes = zigrec.png.fromBgra(
            allocator,
            img.frames[0].pixels,
            img.width,
            img.height,
            @as(usize, img.width) * 4,
        ) catch |err| {
            try w.print("[gif] ПРОВАЛ: кадр не лёг в png: {s}\n", .{@errorName(err)});
            return 1;
        };
        defer allocator.free(bytes);
        std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = bytes }) catch |err| {
            try w.print("[gif] ПРОВАЛ: не записывается {s}: {s}\n", .{ out_path, @errorName(err) });
            return 1;
        };
        try w.print("[gif] первый кадр записан в {s} ({d} байт)\n", .{
            std.fs.path.basename(out_path),
            bytes.len,
        });
    }

    try w.writeAll("[gif] GIF ПРОЧИТАН\n");
    return 0;
}

/// Самопроверка списков недавних на диске.
///
/// Правила списка проверены тестами в памяти. Здесь добавляется диск:
/// русские буквы в путях, пробелы в именах, кодировка файла — всё то,
/// что в памяти не проверишь.
fn recentSmoke(io: std.Io, allocator: std.mem.Allocator, w: anytype, dir: []const u8) !u8 {
    const recent = zigrec.recent;
    zigrec.paths.ensureDir(dir);

    var made = recent.Recent{};
    made.recorded.add("D:\\Мои видео\\запись экрана 1.mp4");
    made.recorded.add("D:\\Мои видео\\запись экрана 2.mp4");
    // Тот же файл ещё раз — должен всплыть наверх, а не появиться дважды.
    made.recorded.add("D:\\Мои видео\\запись экрана 1.mp4");
    made.viewed.add("E:\\чужое\\клип с пробелами.mov");

    if (!recent.save(&made, dir)) {
        try w.print("[recent] ПРОВАЛ: не записалось в {s}\n", .{dir});
        return 1;
    }
    try w.print("[recent] записано: записей {d}, просмотров {d}\n", .{
        made.recorded.count,
        made.viewed.count,
    });

    const back = recent.load(io, allocator, dir);
    if (back.recorded.count != 2 or back.viewed.count != 1) {
        try w.print("[recent] ПРОВАЛ: вернулось записей {d}, просмотров {d}\n", .{
            back.recorded.count,
            back.viewed.count,
        });
        return 1;
    }
    if (!std.mem.eql(u8, back.recorded.at(0), "D:\\Мои видео\\запись экрана 1.mp4")) {
        try w.print("[recent] ПРОВАЛ: наверху оказалось «{s}»\n", .{back.recorded.at(0)});
        return 1;
    }
    if (!std.mem.eql(u8, back.viewed.at(0), "E:\\чужое\\клип с пробелами.mov")) {
        try w.writeAll("[recent] ПРОВАЛ: путь с пробелами развалился\n");
        return 1;
    }
    try w.print("[recent] прочитано обратно, наверху: {s}\n", .{back.recorded.at(0)});

    // Пропавший файл должен опознаваться как пропавший, а не прятаться.
    if (recent.onDisk(back.recorded.at(0))) {
        try w.writeAll("[recent] ПРОВАЛ: несуществующий файл выдан за существующий\n");
        return 1;
    }
    try w.writeAll("[recent] пропавший файл опознан как пропавший\n");
    try w.writeAll("[recent] СПИСКИ ЦЕЛЫ\n");
    return 0;
}

/// Самопроверка хранения: оба способа, и возврат к тому, что было.
///
/// Трогаем настоящий признак рядом с программой — и обязательно возвращаем
/// его в прежнее состояние: самопроверка не должна менять то, как человек
/// настроил программу.
fn homeSmoke(w: anytype) !u8 {
    const paths = zigrec.paths;
    const was = paths.currentMode();
    try w.print("[home] сейчас: {s}\n", .{was.label()});

    var exe_buf: [paths.max_path]u8 = undefined;
    const exe_dir = paths.exeDir(&exe_buf) catch {
        try w.writeAll("[home] ПРОВАЛ: не нашлась папка программы\n");
        return 1;
    };

    var buf: [paths.max_path]u8 = undefined;
    var code: u8 = 0;

    if (paths.setMode(.portable)) {
        const base = paths.base(&buf) catch "";
        try w.print("[home] Portable: {s}\n", .{base});
        if (paths.currentMode() != .portable or !std.mem.eql(u8, base, exe_dir)) {
            try w.writeAll("[home] ПРОВАЛ: Portable не привёл к папке программы\n");
            code = 1;
        }
    } else {
        try w.writeAll("[home] ПРОВАЛ: признак Portable не создался\n");
        code = 1;
    }

    if (code == 0) {
        if (paths.setMode(.classic)) {
            const base = paths.base(&buf) catch "";
            try w.print("[home] Classic: {s}\n", .{base});
            if (paths.currentMode() != .classic or std.mem.eql(u8, base, exe_dir)) {
                try w.writeAll("[home] ПРОВАЛ: Classic не увёл из папки программы\n");
                code = 1;
            }
        } else {
            try w.writeAll("[home] ПРОВАЛ: признак Portable не убрался\n");
            code = 1;
        }
    }

    // Возвращаем как было — что бы ни случилось выше.
    _ = paths.setMode(was);
    if (paths.currentMode() != was) {
        try w.writeAll("[home] ПРОВАЛ: способ хранения не вернулся к прежнему\n");
        return 1;
    }
    try w.print("[home] вернулись к прежнему: {s}\n", .{was.label()});
    if (code != 0) return code;
    try w.writeAll("[home] ХРАНЕНИЕ ПЕРЕКЛЮЧАЕТСЯ\n");
    return 0;
}

/// Самопроверка снимка кадра.
///
/// Рисуем эталонный кадр с таймкодом, записываем его картинкой и печатаем
/// числа. Дальше в дело вступает чужая программа: `tools\\check.cmd` просит
/// ffmpeg распаковать нашу картинку обратно в пиксели, а `verify-raw` читает
/// из них номер кадра. Своим же кодом проверять свою запись — значит
/// не заметить ошибки, сделанной в обе стороны одинаково.
fn shotSmoke(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8, index: u32) !u8 {
    const screen = zigrec.testbench.Screen.init(384, 64, 60) catch {
        try w.writeAll("[shot] ПРОВАЛ: кадр меньше таймкода\n");
        return 1;
    };

    const frame = try allocator.alloc(u8, screen.frameBytes());
    defer allocator.free(frame);
    try screen.render(frame, index);

    const stride = @as(usize, screen.width) * 4;
    const bytes = zigrec.png.fromBgra(allocator, frame, screen.width, screen.height, stride) catch |err| {
        try w.print("[shot] ПРОВАЛ: картинка не собралась: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(bytes);

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = bytes }) catch |err| {
        try w.print("[shot] ПРОВАЛ: не записывается {s}: {s}\n", .{ path, @errorName(err) });
        return 1;
    };

    try w.print("[shot] кадр {d}x{d}, номер {d}\n", .{ screen.width, screen.height, index });
    try w.print("[shot] пикселей {d} байт, картинка {d} байт\n", .{ frame.len, bytes.len });

    // Сжатие без пользы означало бы, что мы записали не то, что думали.
    if (bytes.len >= frame.len) {
        try w.writeAll("[shot] ПРОВАЛ: картинка не меньше кадра\n");
        return 1;
    }
    // Восемь байт подписи узнают все: если их нет, это не PNG.
    if (bytes.len < 8 or !std.mem.eql(u8, bytes[0..8], &zigrec.png.signature)) {
        try w.writeAll("[shot] ПРОВАЛ: у файла не та подпись\n");
        return 1;
    }
    try w.print("[shot] СНИМОК ЗАПИСАН: {s}\n", .{std.fs.path.basename(path)});
    return 0;
}

/// Самопроверка кадра: числа, по которым видно, как лежит картинка в памяти.
///
/// Появился после того, как кадр с камеры расползся косыми полосами,
/// а два предположения о шаге строки подряд оказались неверными. Мерить
/// надо, а не догадываться.
fn frameSmoke(allocator: std.mem.Allocator, w: anytype, path: []const u8, seconds: u32, max_width: u32) !u8 {
    const started = zigrec.win32.nowNs();
    // Высоту не задаём отдельно: просим уместиться в квадрат по ширине,
    // а соотношение сторон сохранит сам пересчёт.
    var p = zigrec.player.Player.openScaled(allocator, path, max_width, max_width) catch |err| {
        try w.print("[frame] ПРОВАЛ: {s} — {s}\n", .{ std.fs.path.basename(path), @errorName(err) });
        return 1;
    };
    defer p.close();

    const opened_ns = zigrec.win32.nowNs() -| started;
    try w.print("[frame] {s}: кадр {d}x{d}, длительность {d:.2} с\n", .{
        std.fs.path.basename(path),
        p.width,
        p.height,
        @as(f64, @floatFromInt(p.duration_ns)) / @as(f64, std.time.ns_per_s),
    });
    if (max_width > 0) {
        try w.print("[frame] просили не шире {d}: {s}\n", .{
            max_width,
            if (p.scaled) "декодер согласился уменьшать" else "декодер отказался, кадр как в файле",
        });
    }
    try w.print("[frame] открытие {d:.0} мс\n", .{
        @as(f64, @floatFromInt(opened_ns)) / @as(f64, std.time.ns_per_ms),
    });

    const before_show = zigrec.win32.nowNs();
    p.showAt(@as(u64, seconds) * std.time.ns_per_s) catch |err| {
        try w.print("[frame] ПРОВАЛ на кадре: {s}\n", .{@errorName(err)});
        return 1;
    };
    if (!p.ready) {
        try w.writeAll("[frame] ПРОВАЛ: кадр не получен\n");
        return 1;
    }
    try w.print("[frame] перемотка и раскодирование {d:.0} мс\n", .{
        @as(f64, @floatFromInt(zigrec.win32.nowNs() -| before_show)) / @as(f64, std.time.ns_per_ms),
    });

    const row_bytes = @as(usize, p.width) * 4;
    const measured = if (p.height > 0) p.last_length / p.height else 0;
    try w.print("[frame] строка по ширине {d} байт, шаг из типа {d}, длина буфера {d}\n", .{
        row_bytes,
        p.stride,
        p.last_length,
    });
    try w.print("[frame] длина делить на высоту: {d}, остаток {d}\n", .{
        measured,
        if (p.height > 0) p.last_length % p.height else 0,
    });
    try w.print("[frame] шаг взят: {s}\n", .{switch (p.route) {
        1 => "у исходного буфера кадра",
        2 => "у склеенного буфера",
        3 => "из типа (двумерный доступ не дали)",
        else => "никак: кадра нет",
    }});
    try w.print("[frame] строки {s} вверх, время кадра {d:.3} с\n", .{
        if (p.bottom_up) "снизу" else "сверху",
        @as(f64, @floatFromInt(p.at_ns)) / @as(f64, std.time.ns_per_s),
    });

    // Кадр не должен быть пустым: чёрное поле означает, что декодер ничего
    // не отдал, а мы этого не заметили.
    var non_zero: usize = 0;
    for (p.pixels) |b| {
        if (b != 0) non_zero += 1;
    }
    try w.print("[frame] ненулевых байт {d} из {d}\n", .{ non_zero, p.pixels.len });
    if (non_zero * 20 < p.pixels.len) {
        try w.writeAll("[frame] ПРОВАЛ: кадр почти пустой\n");
        return 1;
    }
    try w.writeAll("[frame] КАДР ПОЛУЧЕН\n");
    return 0;
}

/// Самопроверка архива проекта `.zigrec`.
///
/// Собираем архив с разметкой и с исходником внутри, пишем на диск, читаем
/// обратно своим кодом и сверяем. А в `check.cmd` тот же архив открывает
/// ЧУЖАЯ программа — питон умеет ZIP из коробки: ZIP мы пишем сами, и если
/// мы ошиблись в заголовках, наш же читатель ошибётся так же и ничего
/// не заметит.
fn packSmoke(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8) !u8 {
    const timeline = zigrec.timeline;
    const pack = zigrec.project_pack;

    const made = try allocator.create(timeline.Project);
    defer allocator.destroy(made);
    made.* = .{};

    const src = try made.addSource("D:\\\\видео\\\\моя запись 2026.mp4", 60 * std.time.ns_per_s);
    _ = try made.addTrack(.video, "Видео");
    _ = try made.addTrack(.audio, "Микрофон ведущего");
    const link = made.newLink();
    try made.placeLinked(0, src, 0, 10 * std.time.ns_per_s, link);
    try made.placeLinked(1, src, 0, 10 * std.time.ns_per_s, link);
    try made.split(0, 4 * std.time.ns_per_s);

    // Вместо настоящего видео кладём узнаваемый кусок: проверяем оболочку,
    // а не кодеки.
    const payload = "это не видео, а метка для проверки: " ** 64;
    const media = [_]pack.Media{.{ .path = "D:\\\\видео\\\\моя запись 2026.mp4", .data = payload }};

    const bytes = pack.write(allocator, made, zigrec.version.VERSION, &media) catch |err| {
        try w.print("[pack] ПРОВАЛ: архив не собрался: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(bytes);

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = bytes }) catch |err| {
        try w.print("[pack] ПРОВАЛ: не записывается {s}: {s}\n", .{ path, @errorName(err) });
        return 1;
    };
    try w.print("[pack] собран {s}: {d} байт, внутри исходник на {d} байт\n", .{
        std.fs.path.basename(path),
        bytes.len,
        payload.len,
    });

    const back = try allocator.create(timeline.Project);
    defer allocator.destroy(back);
    back.* = .{};

    const opened = pack.readMarkup(allocator, io, path, back) catch |err| {
        try w.print("[pack] ПРОВАЛ: архив не читается: {s}\n", .{@errorName(err)});
        return 1;
    };
    try w.print("[pack] прочитан: сделан версией {s}, исходников внутри {d}\n", .{
        opened.madeBy(),
        opened.media,
    });

    if (!std.mem.eql(u8, opened.madeBy(), zigrec.version.VERSION)) {
        try w.writeAll("[pack] ПРОВАЛ: метка не та\n");
        return 1;
    }
    if (opened.media != 1) {
        try w.writeAll("[pack] ПРОВАЛ: исходник внутри не нашёлся\n");
        return 1;
    }
    if (back.track_count != made.track_count) {
        try w.print("[pack] ПРОВАЛ: дорожек было {d}, стало {d}\n", .{ made.track_count, back.track_count });
        return 1;
    }
    for (made.trackList(), back.trackList()) |a, b| {
        if (a.kind != b.kind or a.count != b.count or !std.mem.eql(u8, a.title(), b.title())) {
            try w.writeAll("[pack] ПРОВАЛ: дорожка не сошлась\n");
            return 1;
        }
        for (a.list(), b.list()) |x, y| {
            if (x.source != y.source or x.in_ns != y.in_ns or x.len_ns != y.len_ns or
                x.at_ns != y.at_ns or x.link != y.link)
            {
                try w.writeAll("[pack] ПРОВАЛ: клип не сошёлся\n");
                return 1;
            }
        }
    }
    try w.print("[pack] дорожки и клипы сошлись: дорожек {d}\n", .{back.track_count});

    // Распаковка исходников: архив на то и собирали.
    var dir_buf: [1024]u8 = undefined;
    const dir = std.fmt.bufPrint(&dir_buf, "{s}.распаковано", .{path}) catch path;
    zigrec.paths.ensureDir(dir);
    const unpacked = pack.unpackMedia(io, path, dir) catch |err| {
        try w.print("[pack] ПРОВАЛ: исходники не распаковались: {s}\n", .{@errorName(err)});
        return 1;
    };
    if (unpacked != 1) {
        try w.print("[pack] ПРОВАЛ: распаковано {d} вместо одного\n", .{unpacked});
        return 1;
    }

    var check_buf: [1024]u8 = undefined;
    const copy = pack.sourcePath(&check_buf, made.sourceList()[0].fullPath(), dir, true);
    const got = std.Io.Dir.cwd().readFileAlloc(io, copy, allocator, .limited(1 << 20)) catch |err| {
        try w.print("[pack] ПРОВАЛ: распакованное не читается: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(got);
    if (!std.mem.eql(u8, got, payload)) {
        try w.writeAll("[pack] ПРОВАЛ: распакованное не совпало с положенным\n");
        return 1;
    }
    try w.print("[pack] исходник распакован и совпал байт в байт ({d} байт)\n", .{got.len});

    try w.writeAll("[pack] АРХИВ СОШЁЛСЯ\n");
    return 0;
}

/// Самопроверка файла проекта: собрать, записать на диск, прочитать, сверить.
///
/// Тесты проверяют запись и чтение в памяти. Этот стенд добавляет диск:
/// путь с русскими буквами, перевод строк, кодировку файла — всё то, что
/// в памяти не проверишь.
fn projectSmoke(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8) !u8 {
    const timeline = zigrec.timeline;
    const pf = zigrec.project_file;

    const made = try allocator.create(timeline.Project);
    defer allocator.destroy(made);
    made.* = .{};

    const src = try made.addSource("D:\\видео\\моя запись 2026.mp4", 60 * std.time.ns_per_s);
    _ = try made.addTrack(.video, "Видео");
    _ = try made.addTrack(.audio, "Микрофон ведущего");
    // Видео и звук кладём одной связкой — так их кладёт и редактор,
    // когда открывают обычный mp4.
    const link = made.newLink();
    try made.placeLinked(0, src, 0, 10 * std.time.ns_per_s, link);
    try made.placeLinked(1, src, 0, 10 * std.time.ns_per_s, link);
    try made.split(0, 4 * std.time.ns_per_s);
    try made.setMuted(1, true);

    // Метки: они принадлежат проекту, а не дорожке, и должны пережить
    // запись вместе с цветом и подписью.
    _ = try made.addMark(2 * std.time.ns_per_s, .red, "тут переснять");
    // Комментарий — отдельной строкой в файле, потому что имя уже заняло
    // весь остаток строки метки. Значит, и проверять его надо отдельно.
    try made.setMarkComment(0, "свет с другой стороны, микрофон ближе");
    // Метка бывает и диапазоном: длина идёт отдельной строкой, а значит
    // и проверять её надо отдельно от самой метки.
    try made.setMarkLength(0, 3 * std.time.ns_per_s);
    _ = try made.addMark(7 * std.time.ns_per_s, .violet, "сюда заставку");

    try w.print("[project] собран проект: дорожек {d}, клипов {d}\n", .{
        made.track_count,
        made.trackList()[0].list().len + made.trackList()[1].list().len,
    });

    var text: [64 * 1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&text);
    try pf.write(made, &writer, "");
    const bytes = writer.buffered();

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = bytes }) catch |err| {
        try w.print("[project] ПРОВАЛ: не записывается {s}: {s}\n", .{ path, @errorName(err) });
        return 1;
    };
    try w.print("[project] записано {d} байт в {s}\n", .{ bytes.len, std.fs.path.basename(path) });

    const back_data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1 << 22)) catch |err| {
        try w.print("[project] ПРОВАЛ: не читается обратно: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(back_data);

    const back = try allocator.create(timeline.Project);
    defer allocator.destroy(back);
    back.* = .{};
    pf.read(back, back_data, "") catch |err| {
        try w.print("[project] ПРОВАЛ: {s}\n", .{pf.explain(err)});
        return 1;
    };

    if (back.track_count != made.track_count or back.source_count != made.source_count) {
        try w.writeAll("[project] ПРОВАЛ: дорожек или исходников стало не столько\n");
        return 1;
    }
    if (!std.mem.eql(u8, back.sourceList()[0].fullPath(), made.sourceList()[0].fullPath())) {
        try w.writeAll("[project] ПРОВАЛ: путь к исходнику не совпал\n");
        return 1;
    }
    for (made.trackList(), back.trackList()) |a, b| {
        if (a.kind != b.kind or a.muted != b.muted or a.count != b.count) {
            try w.writeAll("[project] ПРОВАЛ: дорожка изменилась\n");
            return 1;
        }
        if (!std.mem.eql(u8, a.title(), b.title())) {
            try w.writeAll("[project] ПРОВАЛ: имя дорожки не совпало\n");
            return 1;
        }
        for (a.list(), b.list()) |x, y| {
            if (x.source != y.source or x.in_ns != y.in_ns or x.len_ns != y.len_ns or x.at_ns != y.at_ns) {
                try w.writeAll("[project] ПРОВАЛ: клип изменился\n");
                return 1;
            }
            if (x.link != y.link) {
                try w.writeAll("[project] ПРОВАЛ: связка не пережила запись\n");
                return 1;
            }
        }
    }

    if (back.marks.count != made.marks.count) {
        try w.print("[project] ПРОВАЛ: меток было {d}, стало {d}\n", .{
            made.marks.count,
            back.marks.count,
        });
        return 1;
    }
    for (made.marks.list(), back.marks.list()) |a, b| {
        if (a.at_ns != b.at_ns or a.colour != b.colour or !std.mem.eql(u8, a.title(), b.title())) {
            try w.writeAll("[project] ПРОВАЛ: метка не пережила запись целиком\n");
            return 1;
        }
        if (a.len_ns != b.len_ns) {
            try w.print("[project] ПРОВАЛ: длина метки была {d}, стала {d}\n", .{ a.len_ns, b.len_ns });
            return 1;
        }
        if (!std.mem.eql(u8, a.comment(), b.comment())) {
            try w.print("[project] ПРОВАЛ: комментарий метки был «{s}», стал «{s}»\n", .{
                a.comment(),
                b.comment(),
            });
            return 1;
        }
    }
    try w.print("[project] метки целы: {d}, первая «{s}» ({s}), комментарий «{s}»\n", .{
        back.marks.count,
        back.marks.items[0].title(),
        back.marks.items[0].colour.label(),
        back.marks.items[0].comment(),
    });
    // Комментарий у второй метки не появился: пустое должно оставаться пустым.
    if (back.marks.items[1].comment().len != 0) {
        try w.writeAll("[project] ПРОВАЛ: у метки без комментария он откуда-то взялся\n");
        return 1;
    }
    // И точка осталась точкой, а не стала диапазоном нулевой длины.
    if (back.marks.items[1].isSpan()) {
        try w.writeAll("[project] ПРОВАЛ: точка после чтения оказалась диапазоном\n");
        return 1;
    }
    try w.print("[project] первая метка — диапазон {d:.1} с, вторая — точка\n", .{
        @as(f64, @floatFromInt(back.marks.items[0].len_ns)) / @as(f64, std.time.ns_per_s),
    });

    try w.print("[project] прочитано обратно: дорожек {d}, пути и имена целы\n", .{back.track_count});

    // Связка должна не просто сохраниться числом, а работать после чтения:
    // двигаем видео и смотрим, пошёл ли за ним звук. Совпадение номеров
    // ничего не стоит, если по ним никто не ходит.
    const left_link = back.tracks[0].clips[0].link;
    if (left_link == 0) {
        try w.writeAll("[project] ПРОВАЛ: после чтения клипы оказались сами по себе\n");
        return 1;
    }
    const sound_was = back.tracks[1].clips[0].at_ns;
    try back.move(0, 0, 0, 3 * std.time.ns_per_s);
    const sound_now = back.tracks[1].clips[0].at_ns;
    if (sound_now != sound_was + 3 * std.time.ns_per_s) {
        try w.print("[project] ПРОВАЛ: звук не пошёл за картинкой: было {d}, стало {d}\n", .{
            sound_was,
            sound_now,
        });
        return 1;
    }
    try w.print("[project] связка цела: сдвинули видео на 3 с — звук ушёл на 3 с\n", .{});

    // И развязанное должно оставаться развязанным.
    try back.unlink(0, 0);
    try back.move(0, 0, 0, 0);
    if (back.tracks[1].clips[0].at_ns != sound_now) {
        try w.writeAll("[project] ПРОВАЛ: развязанный звук всё равно поехал\n");
        return 1;
    }
    try w.writeAll("[project] развязанный звук остался на месте\n");
    try w.writeAll("[project] ПРОЕКТ СОШЁЛСЯ\n");
    return 0;
}

/// Сказать, если просят больше кадров, чем экран показывает.
///
/// Захват отдаёт кадр тогда, когда рабочий стол его показал. Больше разных
/// кадров, чем обновлений экрана, взяться неоткуда; кодировщик добьёт файл
/// до постоянной частоты повторами. Файл будет правильным и заиграет везде,
/// но человек должен знать, за что платит битрейтом.
fn warnAboutFps(allocator: std.mem.Allocator, w: anytype, monitor: u32, fps: u32) !void {
    const list = zigrec.source.listMonitors(allocator) catch return;
    defer allocator.free(list);

    var hz: u32 = 0;
    for (list) |m| {
        if (m.index == monitor) hz = m.refresh_hz;
    }
    if (hz == 0 or fps <= hz) return;

    try w.print(
        "[rec] экран обновляется {d} раз(а) в секунду: разных кадров больше {d} в секунду\n",
        .{ hz, hz },
    );
    try w.writeAll("[rec] взяться неоткуда, и кодировщик добьёт файл повторами\n");
}

/// Что внутри файла: дорожки, длительность, кодеки.
///
/// Первое, что нужно редактору: показать открытый файл ещё до того, как он
/// научится его проигрывать. Декодер для этого не нужен — всё написано
/// в заголовке.
fn fileInfo(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8) !u8 {
    const info = zigrec.media.read(io, allocator, path) catch |err| {
        try w.print("[info] ПРОВАЛ: {s} — {s}\n", .{
            std.fs.path.basename(path),
            zigrec.media.explain(err),
        });
        return 1;
    };

    try w.print("[info] {s}: {s}, {d:.2} с, дорожек {d}\n", .{
        std.fs.path.basename(path),
        info.format.label(),
        info.seconds(),
        info.list().len,
    });

    for (info.list(), 0..) |t, i| {
        if (t.kind == .video) {
            try w.print("[info]  {d}. {s}: {s}, {d}x{d}, {d:.1} кадр/с, {d:.2} с\n", .{
                i + 1, t.kind.label(), t.codec, t.width, t.height, t.fps, t.seconds(),
            });
        } else if (t.sample_rate > 0) {
            try w.print("[info]  {d}. {s}: {s}, {d} Гц, каналов {d}, {d:.2} с\n", .{
                i + 1, t.kind.label(), t.codec, t.sample_rate, t.channels, t.seconds(),
            });
        } else {
            try w.print("[info]  {d}. {s}: {s}, {d:.2} с\n", .{
                i + 1, t.kind.label(), t.codec, t.seconds(),
            });
        }
    }
    if (info.list().len == 0) try w.writeAll("[info] дорожек не нашлось\n");
    return 0;
}

/// Проверка микрофона без окна: видно, слышно ли, и не занят ли вход.
fn micCheck(w: anytype, seconds: u32) !u8 {
    var cap = zigrec.mic.Capture{};
    cap.start() catch |err| {
        try w.print("[mic] ПРОВАЛ: {s}\n", .{explain(err)});
        return 1;
    };
    defer cap.stop();

    // Первым делом ждём, пока поток поднимется и скажет формат.
    zigrec.win32.c.Sleep(300);
    if (cap.failure) |err| {
        try w.print("[mic] ПРОВАЛ: {s}\n", .{explain(err)});
        return 1;
    }
    try w.print("[mic] устройство: {d} Гц, каналов {d}\n", .{ cap.sample_rate, cap.channels });
    try w.flush();

    var loud: u32 = 0;
    var i: u32 = 0;
    while (i < seconds * 4) : (i += 1) {
        zigrec.win32.c.Sleep(250);
        const level = cap.ring.level();
        if (!level.isSilent()) loud += 1;

        // Столбик из символов: видно и в консоли, и в журнале.
        var bar: [40]u8 = @splat(' ');
        const filled = @min(@as(usize, @intFromFloat(level.peak * 40)), 40);
        for (bar[0..filled]) |*ch| ch.* = '#';
        try w.print("[mic] {s} пик {d:6.1} дБ{s}\n", .{
            bar,
            level.dbfs(),
            if (level.isClipping()) "  ПЕРЕГРУЗ" else if (level.isSilent()) "  тишина" else "",
        });
        try w.flush();
    }

    if (loud == 0) {
        try w.writeAll("[mic] за всё время ни звука: проверьте, тот ли вход выбран и не выключен ли микрофон\n");
        return 1;
    }
    try w.print("[mic] СЛЫШНО: звук был в {d} замерах из {d}\n", .{ loud, i });
    return 0;
}

/// Самопроверка слоя событий (#88): известный путь курсора, клики, клавиша
/// и смена окна пишутся в файл, читаются обратно и сходятся по числу и
/// содержанию. Файл остаётся: его перечитает сторонний читатель
/// `tools/check_events.py` — своим же читателем свою запись не проверяют.
fn eventsSmoke(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8) !u8 {
    const events = zigrec.events;
    const ms = std.time.ns_per_ms;
    {
        var buf: [1 << 14]u8 = undefined;
        var file = try std.Io.Dir.cwd().createFile(io, path, .{});
        defer file.close(io);
        var fw = file.writer(io, &buf);
        var ev = try events.Writer.init(&fw.interface);
        try ev.area(0, 100, 50, 640, 360);
        var i: u64 = 0;
        while (i < 30) : (i += 1) {
            try ev.move(i * 33 * ms, 120 + @as(i32, @intCast(i)) * 10, 80 + @as(i32, @intCast(i)) * 4);
        }
        // Движения кончаются на 957 мс — дальше время только растёт: первый
        // заход стенда поставил щелчок на 400 мс, и оба читателя честно
        // отказались от файла со временем назад.
        try ev.down(1000 * ms, .left, 240, 128);
        try ev.up(1080 * ms, .left, 240, 128);
        try ev.wheel(1200 * ms, -120, 300, 150);
        try ev.key(1300 * ms, 0x41);
        try ev.focus(1400 * ms, "Блокнот — заметки");
        try ev.area(1500 * ms, 140, 50, 640, 360);
        try fw.interface.flush();
        try w.print("[events] записано {d} событий в {s}\n", .{ ev.count, path });
    }

    const data = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1 << 20));
    defer allocator.free(data);
    var got = events.read(allocator, data) catch |err| {
        try w.print("[events] ПРОВАЛ: обратно не читается: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer got.deinit(allocator);
    try w.print("[events] прочитано {d}: area {d}, move {d}, down {d}, up {d}, wheel {d}, key {d}, focus {d}\n", .{
        got.list().len,
        got.count(.area),
        got.count(.move),
        got.count(.down),
        got.count(.up),
        got.count(.wheel),
        got.count(.key),
        got.count(.focus),
    });
    if (got.list().len != 37 or got.count(.move) != 30 or got.count(.area) != 2) {
        try w.writeAll("[events] ПРОВАЛ: число событий не сошлось с записанным\n");
        return 1;
    }
    const at_half = got.cursorAt(500 * ms) orelse {
        try w.writeAll("[events] ПРОВАЛ: указатель на полсекунде не найден\n");
        return 1;
    };
    // На 500 мс последний move — пятнадцатый (495 мс): 120+150, 80+60.
    if (at_half.x != 270 or at_half.y != 140) {
        try w.print("[events] ПРОВАЛ: указатель на полсекунде {d},{d}, ждали 270,140\n", .{ at_half.x, at_half.y });
        return 1;
    }
    if (got.recentDown(1050 * ms, 100 * ms) == null or got.recentDown(1300 * ms, 100 * ms) != null) {
        try w.writeAll("[events] ПРОВАЛ: вспышка клика не там, где нажатие\n");
        return 1;
    }
    if (got.areaAt(1550 * ms).?.x != 140) {
        try w.writeAll("[events] ПРОВАЛ: сдвиг области не прочитался\n");
        return 1;
    }
    try w.writeAll("[events] СЛОЙ ПИШЕТСЯ И ЧИТАЕТСЯ\n");
    return 0;
}

/// Самопроверка автопанорамы (#29): прогоняем правило по нарисованному
/// пути курсора — рывок вправо, пауза, уход в угол — и сверяем: в зоне
/// покоя область стоит, за зоной едет не быстрее предела, у края экрана
/// останавливается. Без настоящей мыши: дёргать её во время проверки
/// нельзя, а правило от неё и не зависит.
fn panSmoke(w: anytype) !u8 {
    const pan = zigrec.pan;
    const area = zigrec.capture_types.Rect{ .x = 100, .y = 100, .width = 640, .height = 360 };
    var f = pan.Follower.init(area);
    const dt: u64 = 33 * std.time.ns_per_ms;
    var worst_step: f32 = 0;
    var last = area;
    var bad: u8 = 0;

    // Курсор в центре области: полсекунды покоя.
    var i: usize = 0;
    while (i < 15) : (i += 1) {
        const r = f.update(420, 280, 640, 360, 1920, 1080, dt);
        if (r.x != area.x or r.y != area.y) bad = 1;
    }
    try w.print("[pan] курсор в центре: область {s}\n", .{if (bad == 0) "стоит" else "ДЁРНУЛАСЬ"});
    if (bad != 0) return 1;

    // Рывок вправо-вниз: область догоняет, но не быстрее предела.
    i = 0;
    while (i < 90) : (i += 1) {
        const r = f.update(1700, 900, 640, 360, 1920, 1080, dt);
        const dx: f32 = @floatFromInt(r.x - last.x);
        const dy: f32 = @floatFromInt(r.y - last.y);
        worst_step = @max(worst_step, @sqrt(dx * dx + dy * dy));
        last = r;
    }
    const limit = f.max_speed * 0.033 + 1;
    try w.print("[pan] самый большой шаг за кадр: {d:.1} точек при пределе {d:.1}; область пришла в {d},{d}\n", .{ worst_step, limit, last.x, last.y });
    if (worst_step > limit) {
        try w.writeAll("[pan] ПРОВАЛ: область прыгнула быстрее предела скорости\n");
        return 1;
    }
    // Курсор 1700,900; зона — центральная половина: x от last.x+160 до last.x+480.
    if (last.x + 480 < 1700 - 1 or last.y + 270 < 900 - 1) {
        try w.writeAll("[pan] ПРОВАЛ: область не догнала курсор за три секунды\n");
        return 1;
    }

    // В угол: область упирается в край экрана и не вылезает.
    i = 0;
    while (i < 90) : (i += 1) last = f.update(1919, 1079, 640, 360, 1920, 1080, dt);
    try w.print("[pan] в углу экрана область стоит в {d},{d} (край {d},{d})\n", .{ last.x, last.y, 1920 - 640, 1080 - 360 });
    if (last.x != 1920 - 640 or last.y != 1080 - 360) {
        try w.writeAll("[pan] ПРОВАЛ: область вышла за край экрана или не дошла до него\n");
        return 1;
    }
    try w.writeAll("[pan] АВТОПАНОРАМА ПЛАВНАЯ И В ПРЕДЕЛАХ ЭКРАНА\n");
    return 0;
}

/// Самопроверка экспорта (#27): проект из одного исходника — клип со
/// второго ключевого кадра до конца, положенный в ноль. Без --offkey
/// начало на ключевом — ждём путь без перекодирования; с --offkey начало
/// сдвинуто на полсекунды — ждём перекодирование. Длину и кадры готового
/// файла сверяем нашим читателем; ffmpeg раскодирует его в check.cmd.
fn exportSmoke(allocator: std.mem.Allocator, w: anytype, src_path: []const u8, out_path: []const u8, off_key: bool, burn: bool, annot: bool) !u8 {
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const keys = zigrec.keyframes.read(io, allocator, src_path) catch |err| {
        try w.print("[export] ПРОВАЛ: ключевые кадры исходника не прочитались: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(keys);
    if (keys.len < 2) {
        try w.print("[export] ПРОВАЛ: в исходнике {d} ключевых кадров, нужно хотя бы два\n", .{keys.len});
        return 1;
    }
    const info = try zigrec.media.read(io, allocator, src_path);

    const project = try allocator.create(zigrec.timeline.Project);
    defer allocator.destroy(project);
    project.* = .{};
    const src = try project.addSource(src_path, info.duration_ns);
    const vt = try project.addTrack(.video, "видео");
    const at = try project.addTrack(.audio, "звук");
    const shift: u64 = if (off_key) 500 * std.time.ns_per_ms else 0;
    const in_ns: u64 = keys[1] + shift;
    if (in_ns >= info.duration_ns) {
        try w.writeAll("[export] ПРОВАЛ: второй ключевой кадр за концом файла\n");
        return 1;
    }
    const len_ns = info.duration_ns - in_ns;
    try project.place(vt, src, 0, len_ns);
    project.tracks[vt].clips[0].in_ns = in_ns;
    try project.place(at, src, 0, len_ns);
    project.tracks[at].clips[0].in_ns = in_ns;

    var audio = zigrec.audio_read.read(allocator, src_path) catch zigrec.audio_read.Audio{};
    defer audio.deinit(allocator);
    const sources = [_]zigrec.mixdown.SourceAudio{.{ .rate = audio.rate, .samples = audio.samples }};

    const key_lists = [_][]const u64{keys};

    // Курсор из слоя (#91): рядом с исходником кладём слой с курсором
    // в известной точке — потом ffmpeg вынет кадр, и pixel-check найдёт
    // там стрелку. Область — весь кадр исходника с нуля.
    var layer: ?zigrec.events.Events = null;
    defer if (layer) |*l| l.deinit(allocator);
    if (burn) {
        // Размер кадра — у декодера: быстрое чтение заголовка его не знает
        // (первый заход стенда положил область 0x0, и курсор не впечатался —
        // молча; теперь область без размера — тоже провал).
        var probe = zigrec.player.Player.openScaled(allocator, src_path, 0, 0) catch |err| {
            try w.print("[export] ПРОВАЛ: кадр исходника не открылся: {s}\n", .{@errorName(err)});
            return 1;
        };
        const fw: u32 = probe.width;
        const fh: u32 = probe.height;
        probe.close();
        if (fw == 0 or fh == 0) {
            try w.writeAll("[export] ПРОВАЛ: размер кадра исходника неизвестен\n");
            return 1;
        }
        var text_buf: [512]u8 = undefined;
        const text = try std.fmt.bufPrint(&text_buf, "zigrec-events 1\n0 area 0 0 {d} {d}\n0 move 300 200\n{d} down L 300 200\n", .{ fw, fh, in_ns + 500 * std.time.ns_per_ms });
        layer = try zigrec.events.read(allocator, text);
        try w.print("[export] слой для впечатывания: курсор в 300,200 на кадре {d}x{d}\n", .{ fw, fh });
    }
    const layers = [_]?zigrec.events.Events{layer};

    // Аннотация (#28): жёлтая надпись в середине кадра на всё время клипа —
    // ffmpeg вынет кадр, pixel-color найдёт подложку.
    if (annot) {
        _ = try project.addAnnotation(.{ .at_ns = 0, .len_ns = len_ns, .kind = .text, .x = 500, .y = 500, .colour = .yellow });
        try project.setAnnotationText(0, "Проверка");
        try w.writeAll("[export] аннотация: жёлтая надпись «Проверка» в 500,500 тысячных\n");
    }

    const decided = zigrec.export_mp4.planWith(project, &key_lists, &layers, burn);
    const want: zigrec.export_mp4.Mode = if (off_key or burn or annot) .reencode else .passthrough;
    try w.print("[export] план: {s}, клипов {d}, не с ключевого {d}\n", .{ decided.mode.label(), decided.clips, decided.off_key });
    if (decided.mode != want) {
        try w.print("[export] ПРОВАЛ: ждали путь «{s}»\n", .{want.label()});
        return 1;
    }

    const started = zigrec.win32.nowNs();
    const summary = zigrec.export_mp4.runWith(allocator, project, &key_lists, if (audio.samples.len > 0) &sources else &.{}, &layers, burn, out_path) catch |err| {
        try w.print("[export] ПРОВАЛ: экспорт не удался: {s}\n", .{@errorName(err)});
        return 1;
    };
    const took_ms = (zigrec.win32.nowNs() - started) / std.time.ns_per_ms;
    try w.print("[export] готово за {d} мс: {d} кадров, {d} мс, звук {d} отсчётов\n", .{
        took_ms,
        summary.frames,
        summary.duration_ns / std.time.ns_per_ms,
        summary.audio_samples,
    });

    // Готовый файл — нашим читателем: длина сходится с клипом до кадра-двух.
    const back = zigrec.media.read(io, allocator, out_path) catch |err| {
        try w.print("[export] ПРОВАЛ: готовый файл не читается: {s}\n", .{@errorName(err)});
        return 1;
    };
    // Длину берём по звуковой дорожке: она равна клипу до отсчёта. У видео
    // в заголовке дорожки писатель прибавляет задержку перестановки кадров
    // (до секунды при B-кадрах) — ffmpeg и плееры считают по отсчётам и
    // показывают ровно клип; наш читатель берёт заголовок. Видео проверяем
    // только снизу: не короче клипа больше чем на кадры.
    var audio_ms: u64 = 0;
    var video_ms: u64 = 0;
    for (back.list()) |t| {
        if (t.fps > 0) video_ms = t.duration_ns / std.time.ns_per_ms else audio_ms = t.duration_ns / std.time.ns_per_ms;
    }
    const want_ms = len_ns / std.time.ns_per_ms;
    const got_ms = if (audio_ms > 0) audio_ms else video_ms;
    try w.print("[export] длина: клип {d} мс, звук {d} мс, видео по заголовку {d} мс, дорожек {d}\n", .{ want_ms, audio_ms, video_ms, back.count });
    const gap = if (got_ms > want_ms) got_ms - want_ms else want_ms - got_ms;
    if (gap > 150) {
        try w.writeAll("[export] ПРОВАЛ: длина звука разошлась с клипом больше чем на 150 мс\n");
        return 1;
    }
    if (video_ms + 150 < want_ms) {
        try w.writeAll("[export] ПРОВАЛ: видео короче клипа\n");
        return 1;
    }
    if (summary.frames == 0) {
        try w.writeAll("[export] ПРОВАЛ: ни одного кадра не записано\n");
        return 1;
    }
    try w.print("[export] ЭКСПОРТ {s} ПРОХОДИТ\n", .{if (annot) "С АННОТАЦИЕЙ" else if (burn) "С КУРСОРОМ ИЗ СЛОЯ" else if (off_key) "С ПЕРЕКОДИРОВАНИЕМ" else "БЕЗ ПЕРЕКОДИРОВАНИЯ"});
    return 0;
}

/// Резкость кадра — средний модуль лапласиана по яркости: у мыла он мал,
/// у чёткого текста велик. Это не «читаемость» словами, а её числовой
/// заменитель: две записи одного экрана сравнимы по нему, а разные — нет.
fn sharpness(pixels: []const u8, stride: usize, width: u32, height: u32) f64 {
    if (width < 3 or height < 3) return 0;
    var sum: f64 = 0;
    var n: u64 = 0;
    var y: usize = 1;
    while (y + 1 < height) : (y += 1) {
        var x: usize = 1;
        while (x + 1 < width) : (x += 1) {
            const c0 = luma(pixels, stride, x, y);
            const l = luma(pixels, stride, x - 1, y) + luma(pixels, stride, x + 1, y) + luma(pixels, stride, x, y - 1) + luma(pixels, stride, x, y + 1) - 4 * c0;
            sum += @abs(l);
            n += 1;
        }
    }
    return if (n == 0) 0 else sum / @as(f64, @floatFromInt(n));
}

fn luma(pixels: []const u8, stride: usize, x: usize, y: usize) f64 {
    const at = y * stride + x * 4;
    const b: f64 = @floatFromInt(pixels[at]);
    const g: f64 = @floatFromInt(pixels[at + 1]);
    const r: f64 = @floatFromInt(pixels[at + 2]);
    return 0.114 * b + 0.587 * g + 0.299 * r;
}

/// Чистая частота кадров захвата без кодирования (#30): раздражитель
/// перерисовывается 60 раз в секунду, цикл только зовёт `next` и считает.
/// Разница с частотой записи — цена кодирования; разница с 60 — цена
/// самого захвата на этой машине.
fn captureRate(w: anytype, seconds: u32, backend: zigrec.capture.Backend, fps: u32) !u8 {
    var stim = zigrec.stimulus.Stimulus{};
    stim.start(.{}) catch |err| try w.print("[rate] раздражитель не поднялся: {s}\n", .{@errorName(err)});
    defer stim.stop();
    var cap = zigrec.capture.Capturer.open(std.heap.page_allocator, .{
        .backend = backend,
        .area = if (backend == .gdi) zigrec.capture_types.Rect{ .x = 0, .y = 0, .width = 1920, .height = 1080 } else null,
        .always_frames = false,
    }) catch |err| {
        try w.print("[rate] ПРОВАЛ: захват не открылся: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer cap.deinit();
    // Заказанный темп (#104): ноль — снимать всё, что даёт экран.
    _ = cap.setRate(fps);
    switch (cap.which) {
        .dxgi => |*d| try w.print("[rate] адаптер «{s}», выход {s}, {d}x{d}\n", .{ d.adapterName(), d.outputName(), d.width, d.height }),
        .gdi, .wgc => {},
    }
    const started = zigrec.win32.nowNs();
    const until = started + @as(u64, seconds) * std.time.ns_per_s;
    var got: u64 = 0;
    var calls: u64 = 0;
    var in_next_ns: u64 = 0;
    var accumulated: u64 = 0;
    while (zigrec.win32.nowNs() < until) {
        const t0 = zigrec.win32.nowNs();
        const frame = cap.next(200) catch |err| {
            try w.print("[rate] ПРОВАЛ на захвате: {s}\n", .{@errorName(err)});
            return 1;
        };
        in_next_ns += zigrec.win32.nowNs() - t0;
        calls += 1;
        if (frame) |f| {
            got += 1;
            accumulated += f.accumulated;
        }
    }
    const secs = @as(f64, @floatFromInt(zigrec.win32.nowNs() - started)) / @as(f64, std.time.ns_per_s);
    const st = cap.stats();
    if (fps > 0) {
        const want = @as(f64, @floatFromInt(fps));
        const got_per_s = @as(f64, @floatFromInt(got)) / secs;
        try w.print("[rate] заказано {d} в секунду, вышло {d:.1}\n", .{ fps, got_per_s });
        // Темп обязан попадать в заказ: он для того и сделан, чтобы не снимать
        // лишнего. Ниже восьмидесяти процентов — не экономия, а недобор.
        if (got_per_s < want * 0.8 or got_per_s > want * 1.2) {
            try w.print("[rate] ПРОВАЛ: заказанный темп не выдержан (нужно {d:.1}–{d:.1})\n", .{ want * 0.8, want * 1.2 });
            return 1;
        }
    }
    try w.print("[rate] {s}: кадров {d} за {d:.1} с — {d:.1} в секунду; вызовов {d}, в next {d:.1} мс в среднем; простоев {d}, накоплено системой {d}; раздражитель {d} перерисовок\n", .{
        cap.backend().label(), got, secs, @as(f64, @floatFromInt(got)) / secs, calls, @as(f64, @floatFromInt(in_next_ns)) / @as(f64, @floatFromInt(@max(calls, 1))) / 1e6, st.idle, accumulated, stim.repaints(),
    });
    return 0;
}

/// Жив ли DXGI на этой машине: ждём от него кадр до секунды. Desktop
/// Duplication молчит после сеанса RDP или на некоторых связках двух видеокарт
/// — тогда честный путь GDI. Чужая проверка того же: `ffmpeg -f lavfi -i ddagrab`.
fn probeBackend(w: anytype) !zigrec.capture.Backend {
    var cap = zigrec.capture.Capturer.open(std.heap.page_allocator, .{ .backend = .dxgi }) catch |err| {
        try w.print("[bench] DXGI не открылся ({s}) — GDI\n", .{@errorName(err)});
        return .gdi;
    };
    defer cap.deinit();
    var waited: u32 = 0;
    while (waited < 5) : (waited += 1) {
        if (cap.next(200) catch null) |_| return .dxgi;
    }
    try w.writeAll("[bench] DXGI за секунду не отдал ни кадра при движении на экране — GDI\n");
    return .gdi;
}

/// Время процессора нашего процесса в секундах (ядро + пользователь).
fn processCpuSeconds() f64 {
    const c = zigrec.win32.c;
    var created: c.FILETIME = undefined;
    var exited: c.FILETIME = undefined;
    var kernel: c.FILETIME = undefined;
    var user: c.FILETIME = undefined;
    if (c.GetProcessTimes(c.GetCurrentProcess(), &created, &exited, &kernel, &user) == 0) return 0;
    const k: u64 = (@as(u64, kernel.dwHighDateTime) << 32) | kernel.dwLowDateTime;
    const u: u64 = (@as(u64, user.dwHighDateTime) << 32) | user.dwLowDateTime;
    return @as(f64, @floatFromInt(k + u)) / 10_000_000.0;
}

/// Самопроверка паузы записи (#95) — на настоящем `Recorder`, том же, что
/// крутит окно.
///
/// Зачем отдельная: захват GDI снимает в своём потоке, и кадр, снятый в
/// начале паузы, дожидается в нём возобновления. Его время за вычетом паузы
/// меньше, чем у кадра до паузы, а писатель такую метку принимает молча —
/// ни ошибки, ни падения, просто кадр «из прошлого» в кодировщике. Поймать
/// это можно только счётчиком самого рекордера.
///
/// Пауз две. Длинную (секунда) закрывают сразу две защиты — сброс на
/// возобновлении и предел возраста кадра. Короткую закрывает только сброс:
/// кадр ещё «свежий» по возрасту, и без `Capturer.flush` время уходит назад.
/// Короткая пауза меряется не временем, а состоянием: ждём, пока рекордер
/// её заметит, и сразу возобновляем — иначе она могла бы проскочить между
/// итерациями цикла записи, и проверка прошла бы, ничего не проверив.
/// Ровный тон в колонки на всё время стенда.
///
/// Стенды звука раньше слушали то, что в колонках окажется само: тихо —
/// проверка пропускалась, а если звук начинался или кончался посреди замера,
/// стенд объявлял брак и был прав по-своему — только виноват был не рекордер.
/// Поймано в `check.cmd`, где перед этим стендом играет свой тон другой шаг.
/// Теперь стенд сам держит звук ровным от начала до конца.
const Tone = struct {
    /// Громкость. По умолчанию та же, что была у всех стендов; тише нужно
    /// только снимку для страницы: громкий тон микрофон принимает в упор,
    /// волна упирается в край поля и выглядит не волной, а полосой.
    amplitude: f32 = 0.2,
    /// Как часто тон «дышит», в герцах. Ноль — ровный тон, как было.
    ///
    /// Нужно это снимку для страницы: осциллограф показывает сами отсчёты,
    /// и ровные четыреста сорок герц на всю ширину поля сливаются в сплошную
    /// полосу — волны не видно. Медленное изменение громкости рисует ту
    /// самую форму, ради которой на волну и смотрят.
    breath_hz: f32 = 0,
    stop: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,
    started: bool = false,

    fn start(self: *Tone) void {
        self.thread = std.Thread.spawn(.{}, run, .{self}) catch null;
        // Колонкам нужно время подняться: без этого первые кадры записи
        // застали бы тишину.
        if (self.thread != null) zigrec.win32.c.Sleep(300);
    }

    fn finish(self: *Tone) void {
        self.stop.store(true, .release);
        if (self.thread) |t| t.join();
        self.thread = null;
    }

    fn run(self: *Tone) void {
        var out = zigrec.play.Renderer.open() catch return;
        defer out.close();
        // Устройство надо ещё и запустить: без `start` отсчёты уходят в буфер,
        // но не звучат — первый заход стенда так и намерил тишину.
        out.start() catch return;
        defer out.stop();
        self.started = true;
        var phase: f32 = 0;
        var breath: f32 = 0;
        const breath_step: f32 = 2.0 * std.math.pi * self.breath_hz / @as(f32, @floatFromInt(out.rate));
        const step: f32 = 2.0 * std.math.pi * 440.0 / @as(f32, @floatFromInt(out.rate));
        var chunk: [1024]f32 = undefined;
        while (!self.stop.load(.acquire)) {
            const padding = out.padding() catch break;
            const room = @min(out.room(padding), chunk.len);
            if (room == 0) {
                zigrec.win32.c.Sleep(5);
                continue;
            }
            for (chunk[0..room]) |*v| {
                const swell: f32 = if (self.breath_hz > 0)
                    0.15 + 0.85 * @abs(@sin(breath))
                else
                    1.0;
                v.* = self.amplitude * swell * @sin(phase);
                breath += breath_step;
                phase += step;
                if (phase > 2.0 * std.math.pi) phase -= 2.0 * std.math.pi;
            }
            out.writeMono(chunk[0..room]) catch break;
        }
    }
};

fn pauseSmoke(allocator: std.mem.Allocator, w: anytype, out_path: []const u8) !u8 {
    const segment_ms: u32 = 1200;
    const long_pause_ms: u32 = 1000;
    // Сколько часам записи позволено сдвинуться за паузу: такт-другой цикла.
    const clock_slack_ns: u64 = 150 * std.time.ns_per_ms;
    // Частота звуковой дорожки рекордера (`encode.AudioSettings` по умолчанию).
    const pause_audio_rate: u64 = 48_000;
    // На сколько звук вправе быть короче картинки: захват поднимается около
    // четверти секунды. Пауза в проверке — секунда, с допуском не спутать.
    const pause_audio_slack_ms: u64 = 400;
    // Сколько отсчётов правка дрейфа вправе тронуть: 50 мс на две паузы.
    // Выброс на паузе идёт не отсчёт в отсчёт — кусок, пойманный до паузы, но
    // ещё не отданный устройством, уходит вместе с ней, — и остаток (замерено
    // 9–21 мс) добирает она. Пауза, не вычтенная из времени устройства, даёт
    // тысячи отсчётов: с допуском не спутать.
    const pause_drift_slack: u64 = 2400;
    const c = zigrec.win32.c;
    // Самопроверка читает итог рекордера по-русски («готово…»), поэтому язык
    // здесь всегда русский, что бы ни стояло в ключе `--lang` (#100).
    zigrec.lang.force(.ru);

    try w.print("[pause] пишем {s}: отрезок, пауза {d} мс, отрезок, короткая пауза, отрезок\n", .{ out_path, long_pause_ms });
    var stim = zigrec.stimulus.Stimulus{};
    stim.start(.{}) catch |err| try w.print("[pause] раздражитель не поднялся: {s}\n", .{@errorName(err)});
    defer stim.stop();

    // Свой тон на всё время стенда: звук в колонках не должен быть случайным.
    var tone = Tone{};
    tone.start();
    defer tone.finish();

    var rec = zigrec.recorder.Recorder.init(allocator);
    // Со звуком колонок (#98): то, что поймано за паузу, в файл идти не должно.
    // Микрофон не берём — на стенде его может не быть, а комнату писать незачем.
    rec.start(out_path, .{ .area = .{ .x = 0, .y = 0, .width = 1280, .height = 720 } }, .{ .fps = 60, .system_sound = true }) catch |err| {
        try w.print("[pause] ПРОВАЛ: запись не началась: {s}\n", .{@errorName(err)});
        return 1;
    };
    var stopped = false;
    defer if (!stopped) rec.stop();

    // Отсчёт — от первого кадра: до него рекордер выбирает путь захвата.
    var waited: u32 = 0;
    while (rec.snapshot().frames == 0 and rec.isBusy() and waited < 8000) : (waited += 10) c.Sleep(10);
    if (rec.snapshot().frames == 0) {
        try w.print("[pause] ПРОВАЛ: за {d} мс ни одного кадра. {s}\n", .{ waited, rec.snapshot().message_text() });
        return 1;
    }
    c.Sleep(segment_ms);

    // Длинная пауза.
    rec.pause();
    waited = 0;
    while (rec.state() != .paused and waited < 1000) : (waited += 5) c.Sleep(5);
    if (rec.state() != .paused) {
        try w.writeAll("[pause] ПРОВАЛ: рекордер не встал на паузу\n");
        return 1;
    }
    const at_pause = rec.snapshot();
    c.Sleep(long_pause_ms);
    const in_pause = rec.snapshot();
    rec.pause();
    c.Sleep(segment_ms);
    const after_long = rec.snapshot();

    // Короткая пауза: по состоянию, а не по времени.
    rec.pause();
    waited = 0;
    while (rec.state() != .paused and waited < 1000) : (waited += 1) c.Sleep(1);
    const short_seen = rec.state() == .paused;
    rec.pause();
    c.Sleep(segment_ms);
    const at_end = rec.snapshot();

    rec.stop();
    stopped = true;
    const final = rec.snapshot();

    const grew_in_pause = in_pause.frames - at_pause.frames;
    const clock_in_pause = in_pause.elapsed_ns -| at_pause.elapsed_ns;
    try w.print("[pause] кадров: до паузы {d}, за паузу +{d}, после неё +{d}, после короткой +{d}\n", .{
        at_pause.frames,
        grew_in_pause,
        after_long.frames - in_pause.frames,
        at_end.frames - after_long.frames,
    });
    try w.print("[pause] часы записи за паузу {d} мс сдвинулись на {d} мс; время кадра уходило назад {d} раз\n", .{
        long_pause_ms,
        clock_in_pause / std.time.ns_per_ms,
        final.time_went_back,
    });

    try w.print("[pause] рекордер: {s}\n", .{final.message_text()});

    var failed = false;
    // Итог и сбой рекордер кладёт в одно поле словами: удачный начинается
    // с «готово», всё остальное — не то, чего ждали.
    if (!std.mem.startsWith(u8, final.message_text(), "готово")) {
        try w.writeAll("[pause] ПРОВАЛ: запись не дошла до конца штатно\n");
        failed = true;
    }
    if (grew_in_pause != 0) {
        try w.writeAll("[pause] ПРОВАЛ: на паузе в файл шли кадры\n");
        failed = true;
    }
    if (clock_in_pause > clock_slack_ns) {
        try w.writeAll("[pause] ПРОВАЛ: часы записи шли на паузе — пауза попала бы в файл\n");
        failed = true;
    }
    if (after_long.frames == in_pause.frames or at_end.frames == after_long.frames) {
        try w.writeAll("[pause] ПРОВАЛ: после паузы запись не возобновилась\n");
        failed = true;
    }
    if (!short_seen) {
        try w.writeAll("[pause] ПРОВАЛ: короткую паузу рекордер не заметил — проверять было нечего\n");
        failed = true;
    }
    if (final.time_went_back != 0) {
        try w.writeAll("[pause] ПРОВАЛ: время кадра ушло назад — кадр, снятый до паузы, попал в запись после неё\n");
        failed = true;
    }
    // Звук (#98). Дорожка считает время по отсчётам, часы записи — за вычетом
    // пауз; разойтись они могут только на разгон звука в начале. Секунда
    // паузы, попавшая в дорожку, видна сразу.
    if (final.audio_samples == 0) {
        try w.writeAll("[pause] звука нет (колонки молчат или их нет) — звук на паузе не проверен\n");
    } else {
        const audio_ms = final.audio_samples * 1000 / pause_audio_rate;
        const video_ms = final.elapsed_ns / std.time.ns_per_ms;
        try w.print("[pause] звука {d} мс при {d} мс записи\n", .{ audio_ms, video_ms });
        const apart = if (audio_ms > video_ms) audio_ms - video_ms else video_ms - audio_ms;
        if (apart > pause_audio_slack_ms) {
            try w.writeAll("[pause] ПРОВАЛ: звук и картинка разошлись по длине — пауза попала в звуковую дорожку или звук потерян\n");
            failed = true;
        }
        // За пять секунд настоящему дрейфу набежать неоткуда. Если правка
        // дрейфа работала — значит, пауза попала в её время устройства, и она
        // «догоняла» то, что выброшено нарочно.
        try w.print("[pause] правка дрейфа тронула {d} отсчётов, потеряно {d}\n", .{ final.audio_drift_fixed, final.audio_lost });
        if (final.audio_drift_fixed > pause_drift_slack) {
            try w.writeAll("[pause] ПРОВАЛ: правка дрейфа приняла паузу за отставание звука\n");
            failed = true;
        }
        if (final.audio_lost != 0) {
            try w.writeAll("[pause] ПРОВАЛ: звук терялся — очередь не успевали забирать\n");
            failed = true;
        }
    }
    if (failed) return 1;
    try w.writeAll("[pause] ПАУЗА ЧИСТАЯ\n");
    return 0;
}

/// Самопроверка: заголовок окна читается, пока поток окна занят (#101).
///
/// Выпуск 1.0.0.0 зависал намертво на «Стоп». Поток окна вставал в `join` и
/// ждал поток записи, а тот на каждом кадре спрашивал заголовок переднего
/// окна через `GetWindowTextW`. Для окна своего процесса этот вызов шлёт
/// `WM_GETTEXT` потоку окна и ждёт ответа — от потока, который сам ждёт.
/// Нужны были три условия разом: наше окно на переднем плане, движение в
/// кадре и «Стоп» из окна; самопроверки держат окно в трее и не ловили.
///
/// Здесь то же самое без рекордера и без переднего плана: окно заводит
/// главный поток и сообщений не разбирает, заголовок читает второй поток.
/// Вернулся за отведённое время — значит, читает без участия владельца.
fn titleSmoke(w: anytype) !u8 {
    // Сколько ждём чтения: оно занимает микросекунды, секунда — с огромным запасом.
    const wait_ms: u32 = 1000;
    const c = zigrec.win32.c;
    const title = "zigrec title-smoke";
    const hwnd = c.CreateWindowExW(
        0,
        std.unicode.utf8ToUtf16LeStringLiteral("STATIC"),
        std.unicode.utf8ToUtf16LeStringLiteral(title),
        c.WS_OVERLAPPED,
        0,
        0,
        200,
        100,
        null,
        null,
        @ptrCast(c.GetModuleHandleW(null)),
        null,
    ) orelse {
        try w.writeAll("[title] ПРОВАЛ: окно не создалось\n");
        return 1;
    };
    defer _ = c.DestroyWindow(hwnd);

    const Reader = struct {
        hwnd: c.HWND,
        done: std.atomic.Value(bool) = .init(false),
        buf: [256]u8 = undefined,
        len: usize = 0,

        fn run(self: *@This()) void {
            const got = zigrec.event_tap.titleOf(self.hwnd, &self.buf);
            self.len = got.len;
            self.done.store(true, .release);
        }
    };
    // Читатель живёт в куче и не освобождается при провале: зависший поток
    // держит на него ссылку, а процесс всё равно выходит.
    const reader = try std.heap.page_allocator.create(Reader);
    reader.* = .{ .hwnd = hwnd };
    const thread = try std.Thread.spawn(.{}, Reader.run, .{reader});

    // Главный поток владеет окном и нарочно не разбирает сообщения — как
    // поток окна, вставший в `join`.
    var waited: u32 = 0;
    while (!reader.done.load(.acquire) and waited < wait_ms) : (waited += 5) c.Sleep(5);
    if (!reader.done.load(.acquire)) {
        try w.print("[title] ПРОВАЛ: заголовок не прочитан за {d} мс — чтение ждёт поток окна; со «Стоп» это зависание намертво\n", .{wait_ms});
        try w.flush();
        // Поток висит в вызове Windows, дождаться его нельзя: выходим процессом.
        thread.detach();
        std.process.exit(1);
    }
    thread.join();
    defer std.heap.page_allocator.destroy(reader);
    const got = reader.buf[0..reader.len];
    try w.print("[title] заголовок «{s}» прочитан за {d} мс, поток окна не понадобился\n", .{ got, waited });
    if (!std.mem.eql(u8, got, title)) {
        try w.print("[title] ПРОВАЛ: ждали «{s}»\n", .{title});
        return 1;
    }
    try w.writeAll("[title] ЗАГОЛОВОК ЧИТАЕТСЯ БЕЗ ВЛАДЕЛЬЦА ОКНА\n");
    return 0;
}

/// Самопроверка звука поверх неподвижного экрана (#98).
///
/// Рассказ поверх слайда: кадров нет, а звук идёт. Пока звук сливался в файл
/// только вместе с кадром, очередь на четыре секунды переполнялась, и из
/// тринадцати секунд записи в файле оставалось пять с половиной. Снимаем
/// угол экрана без раздражителя шесть секунд — дольше очереди — и сверяем
/// длину звука с часами записи. Если в углу что-то шевелится, проверка
/// пройдёт, ничего не доказав, — поэтому число кадров печатается.
fn stillSmoke(allocator: std.mem.Allocator, w: anytype, out_path: []const u8) !u8 {
    // Дольше очереди звука (`track.capacity` — четыре секунды).
    const record_ms: u32 = 6000;
    const audio_rate: u64 = 48_000;
    // Захват звука поднимается около четверти секунды.
    const slack_ms: u64 = 400;
    const c = zigrec.win32.c;
    // Самопроверка читает итог рекордера по-русски («готово…»), поэтому язык
    // здесь всегда русский, что бы ни стояло в ключе `--lang` (#100).
    zigrec.lang.force(.ru);

    // Свой тон: иначе стенд зависит от того, что играет в колонках.
    var tone = Tone{};
    tone.start();
    defer tone.finish();

    var rec = zigrec.recorder.Recorder.init(allocator);
    rec.start(out_path, .{ .area = .{ .x = 0, .y = 0, .width = 64, .height = 64 } }, .{ .fps = 30, .system_sound = true, .cursor = false }) catch |err| {
        try w.print("[still] ПРОВАЛ: запись не началась: {s}\n", .{@errorName(err)});
        return 1;
    };
    c.Sleep(record_ms);
    rec.stop();
    const final = rec.snapshot();

    try w.print("[still] рекордер: {s}\n", .{final.message_text()});
    if (!std.mem.startsWith(u8, final.message_text(), "готово")) {
        try w.writeAll("[still] ПРОВАЛ: запись не дошла до конца штатно\n");
        return 1;
    }
    if (final.audio_samples == 0) {
        try w.writeAll("[still] звука нет (колонки молчат или их нет) — проверять нечего\n");
        return 0;
    }
    const audio_ms = final.audio_samples * 1000 / audio_rate;
    const video_ms = final.elapsed_ns / std.time.ns_per_ms;
    try w.print("[still] кадров {d}, звука {d} мс при {d} мс записи, потеряно отсчётов {d}\n", .{ final.frames, audio_ms, video_ms, final.audio_lost });
    var failed = false;
    if (final.audio_lost != 0) {
        try w.writeAll("[still] ПРОВАЛ: звук терялся — на неподвижном экране его не забирали\n");
        failed = true;
    }
    if (audio_ms + slack_ms < video_ms or audio_ms > video_ms + slack_ms) {
        try w.writeAll("[still] ПРОВАЛ: длина звука разошлась с часами записи\n");
        failed = true;
    }
    if (failed) return 1;
    try w.writeAll("[still] ЗВУК НЕ ЗАВИСИТ ОТ КАДРОВ\n");
    return 0;
}

/// Наша сторона сравнения с CamStudio и OBS (#30): пишем 1920x1080 столько-то
/// секунд с такой-то частотой, меряем себя тем же, чем меряют чужих
/// (`tools/bench_process.py`): время процессора, потери кадров, размер
/// файла, резкость кадра. Строка таблицы — в файл рядом с записью.
fn benchRun(io: std.Io, allocator: std.mem.Allocator, w: anytype, seconds: u32, fps: u32, out_path: []const u8, width: u32, height: u32, strict: bool) !u8 {
    var opt = RecordArgs{
        .seconds = seconds,
        .fps = fps,
        .area = .{ .x = 0, .y = 0, .width = width, .height = height },
        .preset = .text_ui,
    };
    try w.print("[bench] пишем {d}x{d} при {d} к/с {d} с: {s}\n", .{ width, height, fps, seconds, out_path });
    // Раздражитель: без движения на экране DXGI отдаёт один кадр, и замер
    // ничего не меряет. Своё время процессора он тоже тратит — оно входит в
    // наш итог, и у OBS с CamStudio при том же раздражителе входит так же.
    var stim = zigrec.stimulus.Stimulus{};
    stim.start(.{}) catch |err| try w.print("[bench] раздражитель не поднялся: {s} — экран будет неподвижным\n", .{@errorName(err)});
    // Путь захвата выбираем до записи, а не в ней: «авто» ждёт DXGI полторы
    // секунды и только потом берёт GDI — эти полторы секунды испортили бы
    // замер. Пробуем DXGI при работающем раздражителе; молчит — GDI.
    opt.backend = probeBackend(w) catch .gdi;
    try w.print("[bench] путь захвата: {s}\n", .{opt.backend.label()});
    const cpu0 = processCpuSeconds();
    const t0 = zigrec.win32.nowNs();
    const code = try record(io, allocator, w, out_path, opt);
    const wall = @as(f64, @floatFromInt(zigrec.win32.nowNs() - t0)) / @as(f64, std.time.ns_per_s);
    const cpu = processCpuSeconds() - cpu0;
    stim.stop();
    try w.print("[bench] раздражитель перерисовался {d} раз\n", .{stim.repaints()});
    if (code == 1 or code == 2) {
        try w.writeAll("[bench] ПРОВАЛ: запись не удалась\n");
        return 1;
    }

    const size = blk: {
        const f = std.Io.Dir.cwd().openFile(io, out_path, .{}) catch break :blk @as(u64, 0);
        defer f.close(io);
        break :blk f.length(io) catch 0;
    };
    // Резкость — по кадру из середины записи, раскодированному нашим плеером.
    var sharp: f64 = 0;
    if (zigrec.player.Player.openScaled(allocator, out_path, 0, 0)) |opened| {
        var p = opened;
        defer p.close();
        p.showAt(@as(u64, seconds) * std.time.ns_per_s / 2) catch {};
        sharp = sharpness(p.pixels, p.stride, p.width, p.height);
    } else |_| {}

    const cores: f64 = @floatFromInt(std.Thread.getCpuCount() catch 1);
    const one_core = cpu / @max(wall, 0.001) * 100.0;
    const kbit = if (last_record.seconds > 0) @as(f64, @floatFromInt(size)) * 8.0 / 1000.0 / last_record.seconds else 0;
    try w.print("[bench] процессор: {d:.1} с за {d:.1} с стены — {d:.1}% одного ядра, {d:.1}% машины ({d:.0} ядер)\n", .{ cpu, wall, one_core, one_core / cores, cores });
    try w.print("[bench] кадров {d}, потерь {d}, простоев {d}; файл {d} КБ, {d:.0} кбит/с; резкость {d:.2}\n", .{
        last_record.written, last_record.dropped, last_record.idle, size / 1024, kbit, sharp,
    });
    const per_frame = @as(f64, @floatFromInt(@max(last_record.written, 1)));
    try w.print("[bench] на кадр: захват {d:.1} мс, кодирование {d:.1} мс, всего {d:.1} мс\n", .{
        @as(f64, @floatFromInt(last_record.capture_ns)) / per_frame / 1e6,
        @as(f64, @floatFromInt(last_record.encode_ns)) / per_frame / 1e6,
        last_record.seconds * 1000.0 / per_frame,
    });

    // Строка таблицы — рядом с записью; README и вики берут её отсюда.
    var md_buf: [1024]u8 = undefined;
    const md_path = zigrec.events.sidecarPath(&md_buf, out_path);
    var md_full: [1024]u8 = undefined;
    const md = std.fmt.bufPrint(&md_full, "{s}.md", .{md_path[0 .. md_path.len - zigrec.events.extension.len]}) catch out_path;
    if (std.Io.Dir.cwd().createFile(io, md, .{})) |*file| {
        defer file.close(io);
        var fbuf: [2048]u8 = undefined;
        var fw = file.writer(io, &fbuf);
        fw.interface.print("| Zig-Rec Studio {s} ({s}) | {d}x{d} @ {d} | {d:.1} % одного ядра ({d:.1} % машины) | {d} из {d} | {d} КБ ({d:.0} кбит/с) | {d:.2} |\n", .{
            zigrec.version.VERSION, opt.backend.label(), width, height, fps, one_core, one_core / cores, last_record.dropped, last_record.written + last_record.dropped, size / 1024, kbit, sharp,
        }) catch {};
        fw.interface.flush() catch {};
        try w.print("[bench] строка таблицы: {s}\n", .{md});
    } else |_| {}
    // Стенд сам себя проверяет: движение было, кадры пошли, недобор до
    // цели не больше десятой части — иначе замер ни о чём не говорит.
    // Недобор считаем от цели (секунды × кадров в секунду), а не по
    // счётчику потерь захвата: DXGI считает каждый кадр стола, который мы
    // не забрали, — при цели 30 на столе в 60 Гц это половина кадров и
    // норма; GDI потерь не видит вовсе. Цель — одна мера на оба пути.
    const expected: u64 = @as(u64, seconds) * fps;
    const shortfall: u64 = expected -| last_record.written;
    try w.print("[bench] цель {d} кадров, записано {d}, недобор {d}\n", .{ expected, last_record.written, shortfall });
    if (stim.repaints() < @as(u64, seconds) * 10) {
        try w.print("[bench] ПРОВАЛ: раздражитель перерисовался лишь {d} раз за {d} с\n", .{ stim.repaints(), seconds });
        return 1;
    }
    if (last_record.written < @as(u64, seconds) * 10) {
        try w.print("[bench] ПРОВАЛ: записано лишь {d} кадров за {d} с — захват не видел движения\n", .{ last_record.written, seconds });
        return 1;
    }
    // Недобор — это про скорость машины и сборки, а не про сам стенд.
    // Отладочная сборка тратит на кадр своё время и до тридцати не дотягивает;
    // объявлять это провалом проверки значило бы мерить не то. Мерило скорости
    // включается ключом `--strict` — им пользуется релизный замер (#30, #104).
    if (shortfall * 10 > expected) {
        const word = if (strict) "ПРОВАЛ" else "ВНИМАНИЕ";
        try w.print("[bench] {s}: недобор {d} из {d} — больше десятой части; до {d} к/с на этом пути не дотягиваем\n", .{ word, shortfall, expected, fps });
        if (strict) return 1;
    }
    try w.writeAll("[bench] ЗАМЕР ГОТОВ\n");
    return 0;
}

/// Того ли цвета точка сырого кадра BGRA от ffmpeg: допуск 40 на канал —
/// сжатие H.264 и цветовое пространство красят на глаз так же, а по
/// числам чуть иначе.
fn pixelColor(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8, width: u32, height: u32, x: u32, y: u32, r: u32, g: u32, b: u32) !u8 {
    const data = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1 << 28));
    defer allocator.free(data);
    if (data.len < @as(usize, width) * height * 4 or x >= width or y >= height) {
        try w.writeAll("[pixel] ПРОВАЛ: кадр меньше, чем сказано, или точка за кадром\n");
        return 1;
    }
    const at: usize = (@as(usize, y) * width + x) * 4;
    const got_b: i32 = data[at];
    const got_g: i32 = data[at + 1];
    const got_r: i32 = data[at + 2];
    try w.print("[pixel] в {d},{d}: R{d} G{d} B{d}, ждали R{d} G{d} B{d}\n", .{ x, y, got_r, got_g, got_b, r, g, b });
    const tol: i32 = 40;
    if (@abs(got_r - @as(i32, @intCast(r))) > tol or @abs(got_g - @as(i32, @intCast(g))) > tol or @abs(got_b - @as(i32, @intCast(b))) > tol) {
        try w.writeAll("[pixel] ПРОВАЛ: цвет не тот\n");
        return 1;
    }
    try w.writeAll("[pixel] ЦВЕТ СОШЁЛСЯ\n");
    return 0;
}

/// Есть ли в квадрате 5x5 вокруг точки цвета курсора — белый и чёрный
/// (после кодирования H.264 — «почти»: не темнее 200 и не светлее 60).
/// Кадр — сырой BGRA от ffmpeg: сторонний декодер, не наш.
fn pixelCheck(io: std.Io, allocator: std.mem.Allocator, w: anytype, path: []const u8, width: u32, height: u32, x: u32, y: u32) !u8 {
    const data = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1 << 28));
    defer allocator.free(data);
    if (data.len < @as(usize, width) * height * 4) {
        try w.print("[pixel] ПРОВАЛ: в файле {d} байт, для {d}x{d} нужно {d}\n", .{ data.len, width, height, @as(usize, width) * height * 4 });
        return 1;
    }
    var white: u32 = 0;
    var black: u32 = 0;
    var dy: i32 = -2;
    while (dy <= 2) : (dy += 1) {
        var dx: i32 = -2;
        while (dx <= 2) : (dx += 1) {
            const px: i64 = @as(i64, x) + dx;
            const py: i64 = @as(i64, y) + dy;
            if (px < 0 or py < 0 or px >= width or py >= height) continue;
            const at: usize = (@as(usize, @intCast(py)) * width + @as(usize, @intCast(px))) * 4;
            const b = data[at];
            const g = data[at + 1];
            const r = data[at + 2];
            if (b > 200 and g > 200 and r > 200) white += 1;
            if (b < 60 and g < 60 and r < 60) black += 1;
        }
    }
    try w.print("[pixel] вокруг {d},{d}: белых {d}, чёрных {d} из 25\n", .{ x, y, white, black });
    if (white == 0 or black == 0) {
        try w.writeAll("[pixel] ПРОВАЛ: стрелки курсора (белое с чёрной каймой) в этом месте нет\n");
        return 1;
    }
    try w.writeAll("[pixel] КУРСОР В КАДРЕ\n");
    return 0;
}

/// Самопроверка ключевых кадров (#24): наш разбор `stss`/`stts` против
/// списка I-кадров, который ffmpeg напечатал через `showinfo`
/// (`pts_time:` в каждой строке). Число должно сойтись, время — до кадра.
fn keyframesSmoke(allocator: std.mem.Allocator, w: anytype, path: []const u8, list_path: []const u8) !u8 {
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const ours = zigrec.keyframes.read(io, allocator, path) catch |err| {
        try w.print("[keys] ПРОВАЛ: ключевые кадры не прочитались: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(ours);

    const text = try std.Io.Dir.cwd().readFileAlloc(io, list_path, allocator, .limited(1 << 24));
    defer allocator.free(text);
    var theirs: std.ArrayList(u64) = .empty;
    defer theirs.deinit(allocator);
    var rest = text;
    while (std.mem.indexOf(u8, rest, "pts_time:")) |at| {
        rest = rest[at + 9 ..];
        const end = std.mem.indexOfAny(u8, rest, " \r\n") orelse rest.len;
        const secs = std.fmt.parseFloat(f64, rest[0..end]) catch continue;
        try theirs.append(allocator, @intFromFloat(secs * @as(f64, std.time.ns_per_s)));
    }

    try w.print("[keys] у нас {d} ключевых, у ffmpeg {d} I-кадров\n", .{ ours.len, theirs.items.len });
    if (ours.len == 0 or ours.len != theirs.items.len) {
        try w.writeAll("[keys] ПРОВАЛ: число ключевых кадров не сошлось\n");
        return 1;
    }
    var worst: u64 = 0;
    for (ours, theirs.items, 0..) |a, b, i| {
        const gap = if (a > b) a - b else b - a;
        if (gap > worst) worst = gap;
        // Первые расхождения — словами: по ним видно, сдвиг это или сбой.
        if (gap > 40 * std.time.ns_per_ms and i < 8) {
            try w.print("[keys]   #{d}: у нас {d} мс, у ffmpeg {d} мс\n", .{ i, a / std.time.ns_per_ms, b / std.time.ns_per_ms });
        }
    }
    try w.print("[keys] самое большое расхождение времени: {d} мс\n", .{worst / std.time.ns_per_ms});
    // Кадр при 30 к/с — 33 мс; ffmpeg округляет pts до микросекунд.
    if (worst > 40 * std.time.ns_per_ms) {
        try w.writeAll("[keys] ПРОВАЛ: время ключевых кадров разошлось больше чем на кадр\n");
        return 1;
    }
    try w.writeAll("[keys] КЛЮЧЕВЫЕ КАДРЫ СОШЛИСЬ С FFMPEG\n");
    return 0;
}

/// Источник для стенда часов: тон 440 Гц.
fn clockTone(userdata: ?*anyopaque, from: usize, out: []i16) void {
    _ = userdata;
    for (out, 0..) |*v, i| {
        const t = @as(f32, @floatFromInt(from + i)) / 48_000.0;
        v.* = @intFromFloat(@sin(t * 440.0 * 2.0 * std.math.pi) * 8000.0);
    }
}

/// Самопроверка часов плеера (#23): полторы секунды тона через тот же
/// путь, что у редактора; время по отсчётам не идёт назад и к концу
/// сходится с длиной. Без колонок — честно пропускаем.
fn clockSmoke(w: anytype) !u8 {
    const c = zigrec.win32.c;
    const rate: u32 = 48_000;
    const total: usize = rate * 3 / 2;
    var player = zigrec.clock_play.Player{};
    player.start(rate, 0, total, clockTone, null) catch |err| {
        try w.print("[clock] не завёлся ({s}) — проверка пропущена\n", .{zigrec.play.explain(err)});
        return 0;
    };
    c.Sleep(200);
    if (player.failure) |err| {
        player.stop();
        try w.print("[clock] колонок нет ({s}) — проверка пропущена\n", .{zigrec.play.explain(err)});
        return 0;
    }

    var last: u64 = 0;
    var went_back = false;
    var waited: u32 = 0;
    while (player.isRunning() and waited < 5000) : (waited += 50) {
        c.Sleep(50);
        const now = player.playedNs();
        if (now < last) went_back = true;
        last = now;
    }
    player.stop();
    const final_ms = player.playedNs() / std.time.ns_per_ms;
    try w.print("[clock] отзвучало {d} мс при длине 1500 мс, дошли до конца: {s}\n", .{
        final_ms,
        if (player.hasEnded()) "да" else "нет",
    });
    if (went_back) {
        try w.writeAll("[clock] ПРОВАЛ: время пошло назад\n");
        return 1;
    }
    if (!player.hasEnded()) {
        try w.writeAll("[clock] ПРОВАЛ: плеер не дошёл до конца за пять секунд\n");
        return 1;
    }
    if (final_ms < 1400 or final_ms > 1600) {
        try w.writeAll("[clock] ПРОВАЛ: часы разошлись с длиной больше чем на сто миллисекунд\n");
        return 1;
    }
    try w.writeAll("[clock] ЧАСЫ ИДУТ ПО ЗВУКУ\n");
    return 0;
}

/// Самопроверка списка микрофонов: список читается, номера непустые
/// и не повторяются, у каждого есть имя. Без микрофонов — честный ноль,
/// это не поломка: сборочная машина бывает без входа.
fn devicesSmoke(w: anytype) !u8 {
    const devices = zigrec.devices;
    var out: [devices.max_devices]devices.Device = undefined;
    const got = devices.list(&out);
    try w.print("[devices] устройств ввода: {d}\n", .{got.len});
    for (got, 0..) |*d, i| {
        try w.print("[devices]   {s}  —  {s}\n", .{ d.deviceName(), d.deviceId() });
        if (d.deviceName().len == 0 or d.deviceId().len == 0) {
            try w.writeAll("[devices] ПРОВАЛ: устройство без имени или номера\n");
            return 1;
        }
        if (devices.indexOf(got, d.deviceId()) != i) {
            try w.writeAll("[devices] ПРОВАЛ: номер повторяется\n");
            return 1;
        }
    }
    try w.print("[devices] по умолчанию зовётся «{s}»\n", .{devices.nameFor(got, "")});
    try w.writeAll("[devices] СПИСОК ЧИТАЕТСЯ\n");
    return 0;
}

/// Самопроверка пробы: тот же путь, что у кнопки — микрофон в кольцо,
/// кольцо в буфер, буфер в колонки. Сверяем число отсчётов с временем
/// и время воспроизведения с длиной. Без микрофона или колонок проверка
/// честно пропускается.
fn probeSmoke(allocator: std.mem.Allocator, w: anytype, seconds: u32) !u8 {
    const c = zigrec.win32.c;
    const rate: u32 = 48_000;
    const ring = try allocator.create(zigrec.track.Track);
    defer allocator.destroy(ring);
    ring.* = .{};

    var cap = zigrec.mic.Capture{ .track = ring, .track_rate = rate };
    var probe = zigrec.mic_probe.Probe{};
    const started = zigrec.win32.nowNs();
    probe.start(started);
    cap.start() catch |err| {
        try w.print("[probe] микрофона нет ({s}) — проверка пропущена\n", .{explain(err)});
        return 0;
    };
    c.Sleep(300);
    if (cap.failure) |err| {
        cap.stop();
        try w.print("[probe] микрофон не поднялся ({s}) — проверка пропущена\n", .{explain(err)});
        return 0;
    }

    var samples: std.ArrayList(i16) = .empty;
    defer samples.deinit(allocator);
    var chunk: [4096]i16 = undefined;
    const want_ns: u64 = @as(u64, seconds) * std.time.ns_per_s;
    const t0 = zigrec.win32.nowNs();
    while (zigrec.win32.nowNs() - t0 < want_ns) {
        c.Sleep(50);
        while (true) {
            const got = ring.pop(&chunk);
            if (got == 0) break;
            probe.feed(chunk[0..got]);
            try samples.appendSlice(allocator, chunk[0..got]);
        }
    }
    cap.stop();
    while (true) {
        const got = ring.pop(&chunk);
        if (got == 0) break;
        probe.feed(chunk[0..got]);
        try samples.appendSlice(allocator, chunk[0..got]);
    }

    // Считаем от старта захвата, а не от конца разгона: микрофон пишет
    // и те триста миллисекунд, что мы ждали его формат.
    const elapsed_ns = zigrec.win32.nowNs() - started;
    const expected: usize = @intCast(@as(u64, rate) * elapsed_ns / std.time.ns_per_s);
    try w.print("[probe] записано {d} отсчётов за {d} мс, ждали около {d}; пик {d:.1} дБ\n", .{
        samples.items.len,
        elapsed_ns / std.time.ns_per_ms,
        expected,
        probe.peakDb(),
    });
    // Пятнадцать процентов: первые кусочки теряются на подъёме потока,
    // а больше — уже дыра во времени, которую слышно.
    if (samples.items.len < expected * 85 / 100 or samples.items.len > expected * 115 / 100) {
        try w.writeAll("[probe] ПРОВАЛ: отсчётов не столько, сколько времени прошло\n");
        return 1;
    }

    // Итог пробы — как в окне: тишина — не удалась, звук — слушаем.
    probe.recorded(zigrec.win32.nowNs());
    var status_buf: [160]u8 = undefined;
    try w.print("[probe] {s}\n", .{probe.status(&status_buf, zigrec.win32.nowNs())});

    // Играем всегда, даже тишину: проверяем путь до колонок, а не голос.
    const p0 = zigrec.win32.nowNs();
    zigrec.play.playSamples(samples.items, rate) catch |err| {
        try w.print("[probe] колонок нет ({s}) — воспроизведение пропущено\n", .{zigrec.play.explain(err)});
        return 0;
    };
    const played_ms = (zigrec.win32.nowNs() - p0) / std.time.ns_per_ms;
    const want_ms: u64 = @as(u64, samples.items.len) * 1000 / rate;
    try w.print("[probe] сыграно за {d} мс, длина {d} мс\n", .{ played_ms, want_ms });
    if (played_ms < want_ms) {
        try w.writeAll("[probe] ПРОВАЛ: воспроизведение кончилось раньше, чем звук\n");
        return 1;
    }
    if (played_ms > want_ms + 1500) {
        try w.writeAll("[probe] ПРОВАЛ: воспроизведение тянулось дольше звука на секунды \n");
        return 1;
    }
    try w.writeAll("[probe] ПРОБА ПРОХОДИТ\n");
    return 0;
}

fn explain(err: anyerror) []const u8 {
    return zigrec.errors.explain(err);
}

/// Сервер MCP для Claude Code.
///
/// Сам ничего не записывает: он труба между Claude Code и открытым окном
/// Zig-Rec Studio. Записывает по-прежнему окно — то самое, которое видит
/// человек. Иначе получились бы две программы, снимающие экран одновременно.
///
/// Рукопожатие и список инструментов отвечаем сами, не заглядывая в окно:
/// клиент должен уметь подключиться и увидеть, что мы умеем, даже когда окно
/// закрыто. Иначе Claude Code при запуске решит, что сервера нет вовсе.
fn mcpBridge(io: std.Io, allocator: std.mem.Allocator, port: u32) !u8 {
    const net = std.Io.net;

    var in_buf: [64 * 1024]u8 = undefined;
    var out_buf: [64 * 1024]u8 = undefined;
    var stdin: Io.File.Reader = .init(.stdin(), io, &in_buf);
    var stdout: Io.File.Writer = .init(.stdout(), io, &out_buf);
    const r = &stdin.interface;
    const w = &stdout.interface;

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();

    while (true) {
        // `takeDelimiter` сдвигается за перевод строки; `...Exclusive`
        // оставляет его, и следующая строка приходит пустой.
        const line = (r.takeDelimiter('\n') catch break) orelse break;
        if (line.len == 0) continue;
        _ = arena_state.reset(.retain_capacity);

        var session = zigrec.mcp.parse(arena_state.allocator(), line);
        defer session.deinit();
        const got = session.result;

        if (got.fault) |fault| {
            try zigrec.mcp.writeFault(w, got.id, fault);
            try w.writeByte('\n');
            try w.flush();
            continue;
        }
        const request = got.request orelse continue;
        switch (request) {
            // Уведомление ответа не требует: лишний ответ строгий клиент
            // считает ошибкой протокола.
            .initialized, .ignore => continue,
            .ping => {
                try zigrec.mcp.writePong(w, got.id);
                try w.writeByte('\n');
                try w.flush();
                continue;
            },
            .initialize => |req| {
                try zigrec.mcp.writeInitialize(w, got.id, zigrec.version.VERSION, req.protocol);
                try w.writeByte('\n');
                try w.flush();
                continue;
            },
            .list_tools => {
                try zigrec.mcp.writeToolList(w, got.id);
                try w.writeByte('\n');
                try w.flush();
                continue;
            },
            else => {},
        }

        // Остальное умеет только окно.
        var addr = net.IpAddress.parseLiteral("127.0.0.1:1") catch unreachable;
        addr.setPort(@intCast(port));
        const stream = addr.connect(io, .{ .mode = .stream, .protocol = .tcp }) catch {
            // Не молчим и не падаем: человек должен прочитать, что делать.
            try zigrec.mcp.writeToolText(
                w,
                got.id,
                "окно Zig-Rec Studio не отвечает. Откройте его и нажмите кнопку «Сервер MCP» — рядом загорится зелёная лампочка.",
                true,
            );
            try w.writeByte('\n');
            try w.flush();
            continue;
        };
        defer stream.close(io);

        var sock_out: [64 * 1024]u8 = undefined;
        var sock_in: [64 * 1024]u8 = undefined;
        var sock_w = stream.writer(io, &sock_out);
        var sock_r = stream.reader(io, &sock_in);
        try sock_w.interface.writeAll(line);
        try sock_w.interface.writeByte('\n');
        try sock_w.interface.flush();

        const reply = (sock_r.interface.takeDelimiter('\n') catch null) orelse {
            try zigrec.mcp.writeToolText(w, got.id, "окно приняло просьбу, но не ответило", true);
            try w.writeByte('\n');
            try w.flush();
            continue;
        };
        try w.writeAll(reply);
        try w.writeByte('\n');
        try w.flush();
    }
    return 0;
}

/// Самопроверка сервера: настоящий разговор с окном и сверка ответов.
///
/// Проверяем не «поднялся ли порт», а то, ради чего сервер сделан: что на той
/// стороне отвечает работающее окно и что ответы — годный JSON с ожидаемым
/// содержимым. Окно к этому времени должно быть запущено с ключом `--server`.
fn mcpSmoke(allocator: std.mem.Allocator, w: anytype, port: u32) !u8 {
    const net = std.Io.net;
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    try w.print("[mcp] стучимся в 127.0.0.1:{d}\n", .{port});
    try w.flush();

    // Проект для правки (#110): текстовый файл, который мы же и пишем
    // своим писателем проектов — не руками, иначе стенд проверял бы не тот
    // формат, что читает программа. Ссылается на запись, которую стенд
    // сделает следом; в момент резки она уже будет на месте.
    const proj_path = ".check\\mcp-proj.zrs";
    {
        var threaded_proj: std.Io.Threaded = .init(allocator, .{});
        defer threaded_proj.deinit();
        const pio = threaded_proj.io();
        const project = try allocator.create(zigrec.timeline.Project);
        defer allocator.destroy(project);
        project.* = .{};
        const src = try project.addSource(".check\\mcp-rec.mp4", 4 * std.time.ns_per_s);
        const track = try project.addTrack(.video, "видео");
        try project.place(track, src, 0, 4 * std.time.ns_per_s);
        var file = try std.Io.Dir.cwd().createFile(pio, proj_path, .{});
        defer file.close(pio);
        var pbuf: [16 * 1024]u8 = undefined;
        var pw = file.writer(pio, &pbuf);
        try zigrec.project_file.write(project, &pw.interface, ".check");
        try pw.interface.flush();
    }

    // Записывать будем не угол стола, а раздражитель: окно с бегущей
    // полосой (#30). Иначе на неподвижном экране кадров не будет вовсе —
    // первый заход стенда именно так и «записал» пустоту и уронил окно
    // на закрытии файла (это оказалось настоящим дефектом, см. encode.zig).
    var stim = zigrec.stimulus.Stimulus{};
    const stim_box = zigrec.stimulus.Box{ .x = 40, .y = 40, .w = 960, .h = 540 };
    const moving = if (stim.start(stim_box)) |_| true else |err| blk: {
        try w.print("[mcp] раздражитель не поднялся: {s}\n", .{@errorName(err)});
        break :blk false;
    };
    defer if (moving) stim.stop();
    var area_buf: [64]u8 = undefined;
    const area_text = try std.fmt.bufPrint(&area_buf, "{d},{d},{d},{d}", .{ stim_box.x + 20, stim_box.y + 20, stim_box.w - 40, stim_box.h - 40 });
    var start_buf: [512]u8 = undefined;
    const start_line = try std.fmt.bufPrint(
        &start_buf,
        "{{\"jsonrpc\":\"2.0\",\"id\":20,\"method\":\"tools/call\",\"params\":{{\"name\":\"start_recording\"," ++
            "\"arguments\":{{\"area\":\"{s}\",\"seconds\":120,\"name\":\"mcp-rec.mp4\",\"dir\":\".check\",\"quality\":\"video\",\"clicks\":false,\"fps\":15,\"backend\":\"gdi\"}}}}}}",
        .{area_text},
    );

    var addr = net.IpAddress.parseLiteral("127.0.0.1:1") catch unreachable;
    addr.setPort(@intCast(port));
    const stream = addr.connect(io, .{ .mode = .stream, .protocol = .tcp }) catch |err| {
        try w.print("[mcp] ПРОВАЛ: окно не отвечает ({s})\n", .{@errorName(err)});
        return 1;
    };
    defer stream.close(io);

    var out_buf: [16 * 1024]u8 = undefined;
    var in_buf: [64 * 1024]u8 = undefined;
    var sock_w = stream.writer(io, &out_buf);
    var sock_r = stream.reader(io, &in_buf);

    // Спросить и дождаться ответа одной строкой — для проверок, которые
    // не укладываются в «послал, сверил подстроку».
    const Ask = struct {
        fn go(sw: *std.Io.Writer, sr: *std.Io.Reader, line: []const u8) ![]const u8 {
            try sw.writeAll(line);
            try sw.writeByte('\n');
            try sw.flush();
            return (try sr.takeDelimiter('\n')) orelse error.ConnectionClosed;
        }
    };

    const Step = struct {
        what: []const u8,
        line: []const u8,
        /// Что должно встретиться в ответе.
        expect: []const u8,
        /// Строка, которую шлём перед этой и на которую ответа быть НЕ
        /// должно. Так проверяется молчание без часов и таймаутов: лишний
        /// ответ на уведомление пришёл бы первым и не совпал бы с `expect`.
        silent_before: ?[]const u8 = null,
        /// Чего в ответе быть не должно.
        forbid: ?[]const u8 = null,
        /// Подождать столько перед шагом: записи нужно время на кадры.
        wait_ms: u32 = 0,
    };
    const steps = [_]Step{
        .{
            .what = "рукопожатие",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}",
            .expect = "protocolVersion",
        },
        .{
            // Клиент вправе просить версию постарше; мы обязаны назвать её же.
            .what = "рукопожатие с версией клиента",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\"}}",
            .expect = "\"protocolVersion\":\"2025-06-18\"",
        },
        .{
            .what = "ping",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"ping\"}",
            .expect = "\"result\":{}",
            .forbid = "error",
        },
        .{
            // Уведомление ответа не получает: получило бы — оно пришло бы
            // первым, и списка инструментов в ответе не оказалось бы.
            .what = "уведомление остаётся без ответа",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":13,\"method\":\"tools/list\"}",
            .expect = "start_recording",
            .silent_before = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/cancelled\",\"params\":{\"requestId\":1}}",
            .forbid = "error",
        },
        .{
            .what = "список инструментов",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}",
            .expect = "start_recording",
        },
        .{
            .what = "состояние записи",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"recording_status\"}}",
            .expect = "состояние",
        },
        .{
            .what = "список мониторов",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"list_monitors\"}}",
            .expect = "точке",
        },
        .{
            // Список окон — то же, что показывает кнопка «Выбрать окно…».
            // Если сервер о нём не знает, «найди и запиши моё окно» через
            // MCP становится невозможным, а обещано оно в описании.
            .what = "список окон",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"list_windows\"}}",
            .expect = "точке",
        },
        .{
            .what = "инструмент событий в списке",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/list\"}",
            .expect = "recording_events",
        },
        .{
            // Запись со всем, что умеет просьба: своя папка и своё имя,
            // качество, свой срок. Срок велик нарочно — останавливаем сами,
            // а в состоянии проверяем, что обратный отсчёт виден.
            .what = "запись с именем, папкой, качеством и сроком",
            .line = start_line,
            .expect = "запись пошла",
        },
        .{
            .what = "пауза",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":21,\"method\":\"tools/call\",\"params\":{\"name\":\"pause_recording\",\"arguments\":{\"on\":true}}}",
            .expect = "пауза",
        },
        .{
            .what = "снятие паузы",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":22,\"method\":\"tools/call\",\"params\":{\"name\":\"pause_recording\",\"arguments\":{\"on\":false}}}",
            .expect = "продолжаем запись",
        },
        .{
            .what = "надпись во время записи",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":23,\"method\":\"tools/call\",\"params\":{\"name\":\"annotate_now\",\"arguments\":{\"text\":\"проба МЦП\",\"colour\":\"green\",\"seconds\":2}}}",
            .expect = "легла в слой событий",
        },
        .{
            // Пауза и надпись уже позади; дадим записи набрать кадров.
            .what = "секунда записи",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":240,\"method\":\"ping\"}",
            .expect = "result",
            .wait_ms = 1200,
        },
        .{
            .what = "состояние записи подробно",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":24,\"method\":\"tools/call\",\"params\":{\"name\":\"recording_status\"}}",
            .expect = "остановится сама через",
        },
        .{
            .what = "остановка записи",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":25,\"method\":\"tools/call\",\"params\":{\"name\":\"stop_recording\"}}",
            .expect = "готово:",
        },
        .{
            // Слой событий в MCP (#92) — события только что остановленной
            // записи стенда: первое событие любой записи — её область. Прежде
            // шаг стоял до записи и ждал «записи ещё не было», но после #127
            // окно при запуске берёт последнюю запись из «Недавних» человека,
            // и стенд получал его события (#135).
            .what = "события своей последней записи",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"recording_events\",\"arguments\":{\"from\":0,\"to\":5}}}",
            .expect = "область",
        },
        .{
            // Сторож против падения на пустой записи: угол стола неподвижен,
            // кадров может не быть вовсе. Раньше на «стоп» такая запись
            // роняла окно целиком (двойное освобождение писателя), и стенд
            // ловит это тем, что после неё окно ещё отвечает.
            .what = "запись неподвижного угла",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":30,\"method\":\"tools/call\",\"params\":{\"name\":\"start_recording\"," ++
                "\"arguments\":{\"area\":\"0,0,8,8\",\"name\":\"mcp-still.mp4\",\"dir\":\".check\",\"fps\":5,\"backend\":\"gdi\"}}}",
            .expect = "запись пошла",
        },
        .{
            .what = "остановка пустой записи не роняет окно",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":31,\"method\":\"tools/call\",\"params\":{\"name\":\"stop_recording\"}}",
            .expect = "jsonrpc",
            .wait_ms = 300,
        },
        .{
            .what = "окно живо после пустой записи",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":32,\"method\":\"tools/call\",\"params\":{\"name\":\"recording_status\"}}",
            .expect = "состояние:",
        },
        .{
            .what = "надпись без записи отвергается",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":26,\"method\":\"tools/call\",\"params\":{\"name\":\"annotate_now\",\"arguments\":{\"text\":\"поздно\"}}}",
            .expect = "а запись не идёт",
        },
        .{
            // Снимок кладём в .check и НЕ убираем: следом его читает ffmpeg —
            // чужой глаз на наш png (шаг в check.cmd).
            .what = "снимок экрана",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":60,\"method\":\"tools/call\",\"params\":{\"name\":\"take_screenshot\"," ++
                "\"arguments\":{\"area\":\"60,60,640,360\",\"path\":\".check\\\\mcp-shot.png\"}}}",
            .expect = "снимок: .check",
        },
        .{
            .what = "недавние записи",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":61,\"method\":\"tools/call\",\"params\":{\"name\":\"recent_recordings\"}}",
            .expect = "недавн",
        },
        .{
            .what = "что внутри записи",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":62,\"method\":\"tools/call\",\"params\":{\"name\":\"media_info\",\"arguments\":{\"path\":\".check\\\\mcp-rec.mp4\"}}}",
            .expect = "быстрый старт: да",
        },
        .{
            .what = "сведения о том, чего нет",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":63,\"method\":\"tools/call\",\"params\":{\"name\":\"media_info\",\"arguments\":{\"path\":\".check\\\\нетакого.mp4\"}}}",
            .expect = "не читается",
        },
        .{
            .what = "что в проекте",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":73,\"method\":\"tools/call\",\"params\":{\"name\":\"project_info\",\"arguments\":{\"path\":\".check\\\\mcp-proj.zrs\"}}}",
            .expect = "дорожек: 1",
        },
        .{
            // Разрез на второй секунде: из одного куска должно выйти два.
            .what = "разрезать проект",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":74,\"method\":\"tools/call\",\"params\":{\"name\":\"project_edit\"," ++
                "\"arguments\":{\"path\":\".check\\\\mcp-proj.zrs\",\"action\":\"split\",\"at\":2}}}",
            .expect = "кусков там теперь 2",
        },
        .{
            .what = "убрать кусок",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":75,\"method\":\"tools/call\",\"params\":{\"name\":\"project_edit\"," ++
                "\"arguments\":{\"path\":\".check\\\\mcp-proj.zrs\",\"action\":\"delete\",\"at\":2.5}}}",
            .expect = "кусков там теперь 1",
        },
        .{
            // Правка легла в файл, а не осталась в памяти окна: читаем заново.
            .what = "правка сохранилась в файле проекта",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":76,\"method\":\"tools/call\",\"params\":{\"name\":\"project_info\",\"arguments\":{\"path\":\".check\\\\mcp-proj.zrs\"}}}",
            .expect = "длительность: 2.00 с",
        },
        .{
            .what = "поставить метку в проекте",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":80,\"method\":\"tools/call\",\"params\":{\"name\":\"project_mark\"," ++
                "\"arguments\":{\"path\":\".check\\\\mcp-proj.zrs\",\"action\":\"add\",\"at\":1,\"colour\":\"green\",\"text\":\"вот тут\"}}}",
            .expect = "меток теперь 1",
        },
        .{
            .what = "надпись поверх кадра в проекте",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":81,\"method\":\"tools/call\",\"params\":{\"name\":\"project_annotate\"," ++
                "\"arguments\":{\"path\":\".check\\\\mcp-proj.zrs\",\"action\":\"add\",\"at\":0.5,\"seconds\":2,\"kind\":\"text\",\"x\":400,\"y\":500,\"colour\":\"yellow\",\"text\":\"смотри сюда\"}}}",
            .expect = "аннотаций теперь 1",
        },
        .{
            // Всё это должно лежать в файле, а не в памяти окна: читаем заново.
            .what = "метка и надпись сохранились в проекте",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":82,\"method\":\"tools/call\",\"params\":{\"name\":\"project_info\",\"arguments\":{\"path\":\".check\\\\mcp-proj.zrs\"}}}",
            .expect = "меток: 1, аннотаций: 1",
        },
        .{
            .what = "список надписей",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":83,\"method\":\"tools/call\",\"params\":{\"name\":\"project_annotate\",\"arguments\":{\"path\":\".check\\\\mcp-proj.zrs\",\"action\":\"list\"}}}",
            .expect = "«смотри сюда»",
        },
        .{
            .what = "резать не проект — отказ",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":77,\"method\":\"tools/call\",\"params\":{\"name\":\"project_edit\"," ++
                "\"arguments\":{\"path\":\".check\\\\mcp-rec.mp4\",\"action\":\"split\",\"at\":1}}}",
            .expect = "только проект .zrs",
        },
        .{
            .what = "что в записи как в проекте",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":70,\"method\":\"tools/call\",\"params\":{\"name\":\"project_info\",\"arguments\":{\"path\":\".check\\\\mcp-rec.mp4\"}}}",
            .expect = "экспорт пойдёт",
        },
        .{
            .what = "экспорт заданием",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":71,\"method\":\"tools/call\",\"params\":{\"name\":\"export_mp4\"," ++
                "\"arguments\":{\"path\":\".check\\\\mcp-rec.mp4\",\"out\":\".check\\\\mcp-export.mp4\"}}}",
            .expect = "экспорт пошёл",
        },
        .{
            // Путь захвата словами: чужое слово должно отлетать, а wgc без
            // окна — объяснять, чего не хватает (#104, WGC).
            .what = "чужой путь захвата отвергается",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":90,\"method\":\"tools/call\",\"params\":{\"name\":\"start_recording\",\"arguments\":{\"backend\":\"телепатия\"}}}",
            .expect = "путь захвата бывает",
        },
        .{
            .what = "wgc без окна отвергается",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":91,\"method\":\"tools/call\",\"params\":{\"name\":\"start_recording\",\"arguments\":{\"backend\":\"wgc\"}}}",
            .expect = "назовите window",
        },
        .{
            .what = "волна движения включается просьбой",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":92,\"method\":\"tools/call\",\"params\":{\"name\":\"set_settings\",\"arguments\":{\"motion_wave\":true}}}",
            .expect = "волна движения в редакторе: да",
        },
        .{
            .what = "и выключается обратно",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":93,\"method\":\"tools/call\",\"params\":{\"name\":\"set_settings\",\"arguments\":{\"motion_wave\":false}}}",
            .expect = "волна движения в редакторе: нет",
        },
        .{
            .what = "список микрофонов",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":40,\"method\":\"tools/call\",\"params\":{\"name\":\"list_microphones\"}}",
            .expect = "микрофонов:",
        },
        .{
            // Проба может и не удаться — микрофона может не быть вовсе.
            // Проверяем, что инструмент отвечает про пробу, а не молчит.
            .what = "проба микрофона отзывается",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":41,\"method\":\"tools/call\",\"params\":{\"name\":\"probe_microphone\"}}",
            .expect = "проба",
        },
        .{
            .what = "неизвестный инструмент",
            .line = "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"полетели\"}}",
            .expect = "-32601",
        },
    };

    for (steps) |step| {
        if (step.wait_ms > 0) zigrec.win32.c.Sleep(step.wait_ms);
        if (step.silent_before) |quiet| {
            try sock_w.interface.writeAll(quiet);
            try sock_w.interface.writeByte('\n');
        }
        try sock_w.interface.writeAll(step.line);
        try sock_w.interface.writeByte('\n');
        try sock_w.interface.flush();

        const reply = (sock_r.interface.takeDelimiter('\n') catch |err| {
            try w.print("[mcp] ПРОВАЛ на «{s}»: ответа нет ({s})\n", .{ step.what, @errorName(err) });
            return 1;
        }) orelse {
            try w.print("[mcp] ПРОВАЛ на «{s}»: связь оборвалась\n", .{step.what});
            return 1;
        };

        // Ответ обязан быть годным JSON: клиент разбирает его строго.
        const doc = std.json.parseFromSlice(std.json.Value, allocator, reply, .{}) catch {
            // Показываем сам ответ: без него остаётся только гадать,
            // а гадать про чужой протокол — долго.
            try w.print("[mcp] ПРОВАЛ на «{s}»: ответ не разбирается как JSON\n", .{step.what});
            try w.print("[mcp] длина ответа {d}, начало: {s}\n", .{
                reply.len,
                reply[0..@min(reply.len, 200)],
            });
            return 1;
        };
        defer doc.deinit();

        if (std.mem.indexOf(u8, reply, step.expect) == null) {
            try w.print("[mcp] ПРОВАЛ на «{s}»: в ответе нет «{s}»\n", .{ step.what, step.expect });
            try w.print("[mcp] пришло: {s}\n", .{reply[0..@min(reply.len, 200)]});
            return 1;
        }
        if (step.forbid) |bad| {
            if (std.mem.indexOf(u8, reply, bad) != null) {
                try w.print("[mcp] ПРОВАЛ на «{s}»: в ответе есть «{s}», а не должно быть\n", .{ step.what, bad });
                try w.print("[mcp] пришло: {s}\n", .{reply[0..@min(reply.len, 200)]});
                return 1;
            }
        }
        try w.print("[mcp] {s} — ответ получен\n", .{step.what});
        try w.flush();
    }

    // Экспорт идёт своим потоком (#110): ждём его, спрашивая job_status.
    // Ждём с пределом: висящее задание — такой же провал, как и неудачное.
    var waited: u32 = 0;
    var job_said: []const u8 = "";
    while (waited < 60) : (waited += 1) {
        job_said = try Ask.go(&sock_w.interface, &sock_r.interface, "{\"jsonrpc\":\"2.0\",\"id\":72,\"method\":\"tools/call\",\"params\":{\"name\":\"job_status\"}}");
        if (std.mem.indexOf(u8, job_said, "идёт") == null) break;
        zigrec.win32.c.Sleep(500);
    }
    if (std.mem.indexOf(u8, job_said, "готово") == null) {
        try w.print("[mcp] ПРОВАЛ: экспорт не кончился добром: {s}\n", .{job_said[0..@min(job_said.len, 300)]});
        return 1;
    }
    try w.writeAll("[mcp] экспорт заданием дошёл до конца\n");

    // Настройки: прочитать, поменять, убедиться, вернуть как было (#108).
    // Возвращаем обязательно: стенд идёт на живой машине, и оставить после
    // себя чужие настройки другими — это не проверка, а вредительство.
    const before = try Ask.go(&sock_w.interface, &sock_r.interface, "{\"jsonrpc\":\"2.0\",\"id\":50,\"method\":\"tools/call\",\"params\":{\"name\":\"get_settings\"}}");
    const fps_mark = "кадров в секунду: ";
    const fps_at = std.mem.indexOf(u8, before, fps_mark) orelse {
        try w.writeAll("[mcp] ПРОВАЛ: в настройках нет строки про кадры в секунду\n");
        return 1;
    };
    const fps_tail = before[fps_at + fps_mark.len ..];
    const fps_end = std.mem.indexOfNone(u8, fps_tail, "0123456789") orelse fps_tail.len;
    const fps_was = std.fmt.parseInt(u32, fps_tail[0..fps_end], 10) catch {
        try w.writeAll("[mcp] ПРОВАЛ: кадры в секунду не разбираются как число\n");
        return 1;
    };
    const fps_try: u32 = if (fps_was == 24) 60 else 24;

    var set_buf: [256]u8 = undefined;
    const set_line = try std.fmt.bufPrint(&set_buf, "{{\"jsonrpc\":\"2.0\",\"id\":51,\"method\":\"tools/call\",\"params\":{{\"name\":\"set_settings\",\"arguments\":{{\"fps\":{d}}}}}}}", .{fps_try});
    const said = try Ask.go(&sock_w.interface, &sock_r.interface, set_line);
    if (std.mem.indexOf(u8, said, "сохранено") == null) {
        try w.print("[mcp] ПРОВАЛ: настройки не сохранились: {s}\n", .{said[0..@min(said.len, 200)]});
        return 1;
    }
    const after = try Ask.go(&sock_w.interface, &sock_r.interface, "{\"jsonrpc\":\"2.0\",\"id\":52,\"method\":\"tools/call\",\"params\":{\"name\":\"get_settings\"}}");
    var want_buf: [64]u8 = undefined;
    const want_text = try std.fmt.bufPrint(&want_buf, "кадров в секунду: {d}", .{fps_try});
    if (std.mem.indexOf(u8, after, want_text) == null) {
        try w.print("[mcp] ПРОВАЛ: поменяли на {d}, а настройки говорят другое\n", .{fps_try});
        return 1;
    }
    var back_buf: [256]u8 = undefined;
    const back_line = try std.fmt.bufPrint(&back_buf, "{{\"jsonrpc\":\"2.0\",\"id\":53,\"method\":\"tools/call\",\"params\":{{\"name\":\"set_settings\",\"arguments\":{{\"fps\":{d}}}}}}}", .{fps_was});
    _ = try Ask.go(&sock_w.interface, &sock_r.interface, back_line);
    const restored = try Ask.go(&sock_w.interface, &sock_r.interface, "{\"jsonrpc\":\"2.0\",\"id\":54,\"method\":\"tools/call\",\"params\":{\"name\":\"get_settings\"}}");
    var was_buf: [64]u8 = undefined;
    const was_text = try std.fmt.bufPrint(&was_buf, "кадров в секунду: {d}", .{fps_was});
    if (std.mem.indexOf(u8, restored, was_text) == null) {
        try w.print("[mcp] ПРОВАЛ: настройки не вернулись к {d}\n", .{fps_was});
        return 1;
    }
    try w.print("[mcp] настройки: было {d} кадр/с, поставили {d}, вернули {d}\n", .{ fps_was, fps_try, fps_was });

    // Просьбы исполнены — теперь проверяем то, что от них осталось на диске
    // (#107). Ответ словами «запись пошла» ничего не доказывает: файл должен
    // лежать там, где просили, называться так, как просили, играться с начала
    // и нести в слое ту самую надпись.
    // Ввод-вывод здесь уже есть — тот же, на котором шёл разговор.
    const made = ".check\\mcp-rec.mp4";
    var boxes: [64]zigrec.mp4.Box = undefined;
    const layout = zigrec.mp4.inspect(io, allocator, made, &boxes) catch |err| {
        try w.print("[mcp] ПРОВАЛ: файла {s} нет или он не разбирается: {s}\n", .{ made, @errorName(err) });
        return 1;
    };
    if (!layout.playable() or !layout.fastStart()) {
        try w.print("[mcp] ПРОВАЛ: {s} без данных или без быстрого старта\n", .{made});
        return 1;
    }
    var side_buf: [1024]u8 = undefined;
    const side = zigrec.events.sidecarPath(&side_buf, made);
    const layer = std.Io.Dir.cwd().readFileAlloc(io, side, allocator, .limited(1 << 20)) catch |err| {
        try w.print("[mcp] ПРОВАЛ: слой событий {s} не читается: {s}\n", .{ side, @errorName(err) });
        return 1;
    };
    defer allocator.free(layer);
    if (std.mem.indexOf(u8, layer, "проба МЦП") == null) {
        try w.print("[mcp] ПРОВАЛ: надписи из просьбы нет в слое {s}\n", .{side});
        return 1;
    }
    try w.print("[mcp] файл {s}: данных {d} байт, moov впереди, надпись в слое есть\n", .{ made, layout.mdat_size });
    std.Io.Dir.cwd().deleteFile(io, made) catch {};
    std.Io.Dir.cwd().deleteFile(io, side) catch {};
    std.Io.Dir.cwd().deleteFile(io, proj_path) catch {};
    // Пустая запись могла оставить огрызок файла — убираем и его.
    std.Io.Dir.cwd().deleteFile(io, ".check\\mcp-still.mp4") catch {};
    var still_buf: [1024]u8 = undefined;
    std.Io.Dir.cwd().deleteFile(io, zigrec.events.sidecarPath(&still_buf, ".check\\mcp-still.mp4")) catch {};

    try w.writeAll("[mcp] СЕРВЕР ОТВЕЧАЕТ\n");
    return 0;
}

/// Простукивает окно, пока идёт «Стоп»: `SendMessageTimeout(WM_NULL)` раз в
/// сто миллисекунд. Не ответило за четыреста — окно висело.
const Pinger = struct {
    const c = zigrec.win32.c;
    hwnd: c.HWND,
    stop: std.atomic.Value(bool) = .init(false),
    pings: u32 = 0,
    failures: u32 = 0,
    max_ms: u64 = 0,

    fn run(self: *Pinger) void {
        while (!self.stop.load(.acquire)) {
            const t0 = zigrec.win32.nowNs();
            var res: c.DWORD_PTR = 0;
            const ok = c.SendMessageTimeoutW(self.hwnd, c.WM_NULL, 0, 0, c.SMTO_ABORTIFHUNG | c.SMTO_BLOCK, 400, &res);
            const ms = (zigrec.win32.nowNs() - t0) / std.time.ns_per_ms;
            self.pings += 1;
            if (ok == 0) self.failures += 1;
            if (ms > self.max_ms) self.max_ms = ms;
            c.Sleep(100);
        }
    }
};

/// Текст ответа инструмента MCP: `result.content[0].text`.
fn toolText(doc: std.json.Value) ?[]const u8 {
    const result = (doc.object.get("result") orelse return null);
    if (result != .object) return null;
    const content = result.object.get("content") orelse return null;
    if (content != .array or content.array.items.len == 0) return null;
    const first = content.array.items[0];
    if (first != .object) return null;
    const text = first.object.get("text") orelse return null;
    return if (text == .string) text.string else null;
}

/// Окно не должно замирать на «Стоп» (#102). Через MCP просим начать запись
/// маленькой области, через две секунды — остановить; пока окно закрывает
/// файл (крючок `ZIGREC_SLOW_FINISH_MS` делает это долгим), отдельный поток
/// стучит в него `WM_NULL` с таймаутом. Хоть один стук без ответа — окно
/// висело, ПРОВАЛ. Ответ на «стоп» обязан прийти не раньше крючка: иначе
/// крючок не сработал и стенд ничего не проверил. Файл проверяем на быстрый
/// старт и убираем — это стенд, а не запись.
fn stopSmoke(allocator: std.mem.Allocator, w: anytype, port: u32) !u8 {
    const c = zigrec.win32.c;
    const net = std.Io.net;
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const hwnd = c.FindWindowW(std.unicode.utf8ToUtf16LeStringLiteral("ZigRecMain"), null) orelse {
        try w.writeAll("[stop] ПРОВАЛ: окно ZigRecMain не найдено\n");
        return 1;
    };
    var addr = net.IpAddress.parseLiteral("127.0.0.1:1") catch unreachable;
    addr.setPort(@intCast(port));
    const stream = addr.connect(io, .{ .mode = .stream, .protocol = .tcp }) catch |err| {
        try w.print("[stop] ПРОВАЛ: сервер не отвечает ({s})\n", .{@errorName(err)});
        return 1;
    };
    defer stream.close(io);
    var out_buf: [16 * 1024]u8 = undefined;
    var in_buf: [64 * 1024]u8 = undefined;
    var sock_w = stream.writer(io, &out_buf);
    var sock_r = stream.reader(io, &in_buf);

    const Ask = struct {
        fn go(sw: *std.Io.Writer, sr: *std.Io.Reader, line: []const u8) ![]const u8 {
            try sw.writeAll(line);
            try sw.writeAll("\n");
            try sw.flush();
            return (try sr.takeDelimiter('\n')) orelse error.ConnectionClosed;
        }
    };

    _ = try Ask.go(&sock_w.interface, &sock_r.interface, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}");
    const started = try Ask.go(&sock_w.interface, &sock_r.interface, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"start_recording\",\"arguments\":{\"area\":\"0,0,320,200\"}}}");
    if (std.mem.indexOf(u8, started, "запись пошла") == null) {
        try w.print("[stop] ПРОВАЛ: запись не началась: {s}\n", .{started[0..@min(started.len, 200)]});
        return 1;
    }
    try w.writeAll("[stop] запись пошла, две секунды…\n");
    try w.flush();
    c.Sleep(2000);

    var ping = Pinger{ .hwnd = hwnd };
    const ping_thread = try std.Thread.spawn(.{}, Pinger.run, .{&ping});
    const t0 = zigrec.win32.nowNs();
    const stopped = Ask.go(&sock_w.interface, &sock_r.interface, "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"stop_recording\",\"arguments\":{}}}") catch |err| {
        // Связь оборвалась или окно молчит: старый «Стоп» с join ронял
        // сервер вместе с окном — это тоже ПРОВАЛ, а не ошибка стенда.
        ping.stop.store(true, .release);
        ping_thread.join();
        try w.print("[stop] ПРОВАЛ: на «стоп» нет ответа, связь с окном оборвалась ({s}); стуков {d}, без ответа {d}\n", .{ @errorName(err), ping.pings, ping.failures });
        return 1;
    };
    const stop_ms = (zigrec.win32.nowNs() - t0) / std.time.ns_per_ms;
    ping.stop.store(true, .release);
    ping_thread.join();

    try w.print("[stop] «стоп» занял {d} мс; стуков {d}, без ответа {d}, самый долгий {d} мс\n", .{ stop_ms, ping.pings, ping.failures, ping.max_ms });
    var bad = false;
    if (stop_ms < 1000) {
        try w.writeAll("[stop] ПРОВАЛ: «стоп» прошёл быстрее секунды — крючок ZIGREC_SLOW_FINISH_MS не сработал, окно не проверялось\n");
        bad = true;
    }
    if (ping.pings < 3) {
        try w.writeAll("[stop] ПРОВАЛ: стуков меньше трёх — простукивание не шло\n");
        bad = true;
    }
    if (ping.failures > 0 or ping.max_ms > 400) {
        try w.writeAll("[stop] ПРОВАЛ: окно не отвечало, пока закрывался файл\n");
        bad = true;
    }

    const doc = std.json.parseFromSlice(std.json.Value, allocator, stopped, .{}) catch {
        try w.writeAll("[stop] ПРОВАЛ: ответ на «стоп» не разбирается как JSON\n");
        return 1;
    };
    defer doc.deinit();
    const text = toolText(doc.value) orelse {
        try w.print("[stop] ПРОВАЛ: в ответе на «стоп» нет текста: {s}\n", .{stopped[0..@min(stopped.len, 200)]});
        return 1;
    };
    const marker = "файл ";
    const at = std.mem.indexOf(u8, text, marker) orelse {
        try w.print("[stop] ПРОВАЛ: в ответе нет имени файла: {s}\n", .{text});
        return 1;
    };
    const path = std.mem.trimEnd(u8, text[at + marker.len ..], " \n");
    var boxes: [64]zigrec.mp4.Box = undefined;
    const layout = zigrec.mp4.inspect(io, allocator, path, &boxes) catch |err| {
        try w.print("[stop] ПРОВАЛ: файл {s} не разбирается: {s}\n", .{ path, @errorName(err) });
        return 1;
    };
    if (!layout.fastStart() or !layout.playable()) {
        try w.print("[stop] ПРОВАЛ: файл {s} без быстрого старта или без данных\n", .{path});
        bad = true;
    } else {
        try w.print("[stop] файл {s}: moov впереди, данных {d} байт\n", .{ path, layout.mdat_size });
    }
    std.Io.Dir.cwd().deleteFile(io, path) catch {};
    var side_buf: [1024]u8 = undefined;
    std.Io.Dir.cwd().deleteFile(io, zigrec.events.sidecarPath(&side_buf, path)) catch {};

    if (bad) return 1;
    try w.writeAll("[stop] ОКНО ЖИВО НА «СТОП»\n");
    return 0;
}

test "версия ядра доступна из exe" {
    try std.testing.expect(zigrec.version.VERSION.len > 0);
    _ = zigrec.version.current();
}

test "разбор числового аргумента" {
    const args = [_][]const u8{ "zigrec", "record", "out.mp4", "12", "плохо" };
    try std.testing.expectEqual(@as(u32, 12), argInt(&args, 3, 5));
    try std.testing.expectEqual(@as(u32, 30), argInt(&args, 4, 30));
    try std.testing.expectEqual(@as(u32, 7), argInt(&args, 9, 7));
}

test "ключи записи: умолчания" {
    const a = try parseRecordArgs(&.{});
    try std.testing.expectEqual(@as(u32, 5), a.seconds);
    try std.testing.expectEqual(@as(u32, 30), a.fps);
    try std.testing.expectEqual(@as(u32, 0), a.monitor);
    try std.testing.expect(a.area == null);
    try std.testing.expect(a.window == null);
}

test "ключи записи: область и время" {
    const a = try parseRecordArgs(&.{ "--sec", "12", "--area", "10,20,640,480" });
    try std.testing.expectEqual(@as(u32, 12), a.seconds);
    try std.testing.expectEqual(@as(u32, 640), a.area.?.width);
}

test "ключи записи: окно по части заголовка" {
    const a = try parseRecordArgs(&.{ "--window", "Блокнот", "--fps", "60" });
    try std.testing.expectEqualStrings("Блокнот", a.window.?);
    try std.testing.expectEqual(@as(u32, 60), a.fps);
}

test "ключи записи: два источника сразу — ошибка" {
    try std.testing.expectError(
        ArgError.OneSourceOnly,
        parseRecordArgs(&.{ "--area", "0,0,10,10", "--window", "что-то" }),
    );
}

test "ключи записи: пропущенное значение и мусор" {
    try std.testing.expectError(ArgError.MissingValue, parseRecordArgs(&.{"--sec"}));
    try std.testing.expectError(ArgError.BadValue, parseRecordArgs(&.{ "--fps", "0" }));
    try std.testing.expectError(ArgError.BadValue, parseRecordArgs(&.{ "--fps", "999" }));
    try std.testing.expectError(ArgError.BadValue, parseRecordArgs(&.{ "--area", "плохо" }));
    try std.testing.expectError(ArgError.UnknownKey, parseRecordArgs(&.{"--луна"}));
}

test "ключи качества" {
    const a = try parseRecordArgs(&.{ "--preset", "max", "--gop", "30", "--bitrate", "8000" });
    try std.testing.expectEqual(zigrec.encode.Preset.max, a.preset);
    try std.testing.expectEqual(@as(u32, 30), a.gop);
    try std.testing.expectEqual(@as(u32, 8000), a.bitrate_kbps.?);
}

test "ключи качества: мусор отвергается" {
    try std.testing.expectError(ArgError.BadValue, parseRecordArgs(&.{ "--preset", "лучший" }));
    try std.testing.expectError(ArgError.BadValue, parseRecordArgs(&.{ "--bitrate", "10" }));
    try std.testing.expectError(ArgError.BadValue, parseRecordArgs(&.{ "--gop", "0" }));
}

test "ключи курсора" {
    const a = try parseRecordArgs(&.{ "--no-cursor", "--no-clicks" });
    try std.testing.expect(!a.cursor);
    try std.testing.expect(!a.clicks);
    const b = try parseRecordArgs(&.{});
    try std.testing.expect(b.cursor and b.clicks);
}

test "звук пишется только когда его попросили" {
    // Умолчание — без звука: запись экрана не должна начать слушать микрофон
    // сама по себе, об этом человек просит явно.
    const quiet = try parseRecordArgs(&.{});
    try std.testing.expect(!quiet.sound);
    const loud = try parseRecordArgs(&.{"--sound"});
    try std.testing.expect(loud.sound);
}

test "ключ --system включает системный звук и не трогает микрофон" {
    const both = try parseRecordArgs(&.{ "--sound", "--system" });
    try std.testing.expect(both.sound);
    try std.testing.expect(both.system);
    const only_system = try parseRecordArgs(&.{"--system"});
    try std.testing.expect(!only_system.sound);
    try std.testing.expect(only_system.system);
}
