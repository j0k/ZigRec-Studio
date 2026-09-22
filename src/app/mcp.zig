//! Разговор по протоколу MCP: запрос строкой — ответ строкой.
//!
//! Задача #41. Смысл в том, чтобы записью экрана можно было управлять не
//! только руками, но и из Claude Code: «сними это окно», «останови», «какой
//! получился файл».
//!
//! **Здесь нет ввода-вывода.** Ни сокетов, ни файлов, ни потоков: на входе
//! строка запроса, на выходе строка ответа. Только так протокол можно
//! проверять тестами, а не «запустить и посмотреть» — а требование цели
//! именно такое. Всё, что умеет разговаривать с миром, живёт снаружи.
//!
//! Обмен идёт по JSON-RPC 2.0. Нужны из него: рукопожатие, список
//! инструментов, вызов инструмента и `ping`.
const std = @import("std");

/// Версии протокола, на которых умеем говорить, от новой к старой.
///
/// Список сверен с тем, что знают клиенты: у SDK 1.29.0 (он стоит на машине
/// разработки) последняя — `2025-11-25`, и ниже те же, что здесь. Самая
/// старая, `2024-10-07`, нам не нужна: её не просит никто.
pub const supported_versions = [_][]const u8{ "2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05" };

/// Наша версия, если клиент своей не назвал.
pub const protocol_version = supported_versions[0];

/// О какой версии договорились.
///
/// Просьбу клиента исполняем, если такую знаем: он говорит первым и вправе
/// попросить старую. Не знаем — называем свою новую, и дальше решает он:
/// протокол разрешает клиенту на это разорвать связь. Раньше мы просьбу не
/// читали вовсе и всегда отвечали `2024-11-05` — четыре ревизии назад.
pub fn agreeVersion(asked: ?[]const u8) []const u8 {
    const want = asked orelse return protocol_version;
    for (supported_versions) |known| {
        if (std.mem.eql(u8, known, want)) return known;
    }
    return protocol_version;
}

pub const server_name = "zigrec";

/// Что попросили сделать. Разбор отделён от исполнения: разобрать просьбу
/// можно и проверить тестами, а исполнить её умеет только тот, у кого есть
/// экран и кодировщик.
/// Куда писать курсор (#92): в кадр (и в слой, слой пишется всегда)
/// или только в слой событий.
pub const Cursor = enum { burn, layer };

/// Качество записи — те же три, что в окне.
pub const Quality = enum {
    text_ui,
    video,
    max,

    pub fn parse(text: []const u8) ?Quality {
        if (std.mem.eql(u8, text, "text_ui") or std.mem.eql(u8, text, "text")) return .text_ui;
        if (std.mem.eql(u8, text, "video")) return .video;
        if (std.mem.eql(u8, text, "max")) return .max;
        return null;
    }
};

/// Пауза: включить, снять или переключить.
///
/// Именно состояние, а не переключатель: просьба «поставь на паузу»,
/// повторённая дважды, не должна снимать паузу. Переключение остаётся
/// для кнопки в окне и для просьбы без параметра.
pub const Pause = struct {
    on: ?bool = null,
};

/// Надпись в слой событий прямо во время записи (#28).
pub const Note = struct {
    /// Слова надписи. Пусто — берётся шаблон.
    text: ?[]const u8 = null,
    /// Шаблон 1..3: «Внимание», «Шаг», «Ошибка».
    template: ?u32 = null,
    /// Цвет по имени: yellow, red, orange, green, cyan, blue, violet, grey.
    colour: ?[]const u8 = null,
    /// Сколько секунд держать; ноль или нет — три.
    seconds: ?f64 = null,
};

/// События последней записи из слоя: отрезок в секундах, не больше `limit`.
pub const EventsAsk = struct {
    from_s: f64 = 0,
    /// Ноль — до конца.
    to_s: f64 = 0,
    limit: u32 = 200,
};

pub const Request = union(enum) {
    /// Рукопожатие вместе с версией, которую назвал клиент.
    initialize: Initialize,
    /// Клиент сообщает, что готов. Ответа не требует.
    initialized,
    /// Уведомление, которого мы не знаем: ответа не будет — и это не
    /// снисходительность, а правило JSON-RPC. На сообщение без номера
    /// отвечать нельзя ничем, даже ошибкой.
    ignore,
    /// «Ты живой?» — клиенты шлют, чтобы связь не считалась потерянной.
    ping,
    /// Какие есть инструменты.
    list_tools,
    /// Начать запись.
    start: Start,
    /// Остановить запись и отдать файл.
    stop,
    /// Идёт ли запись, сколько кадров и секунд.
    status,
    /// Какие есть мониторы.
    monitors,
    /// Какие есть окна.
    windows,
    /// События последней записи из слоя (#92).
    events: EventsAsk,
    /// Пауза записи и снятие паузы.
    pause: Pause,
    /// Надпись в слой событий во время записи.
    note: Note,

    pub const Initialize = struct {
        /// Версия протокола, которую назвал клиент; `null` — не назвал.
        protocol: ?[]const u8 = null,
    };

    pub const Start = struct {
        /// Что снимать: весь монитор, прямоугольник или окно по заголовку.
        monitor: ?u32 = null,
        area: ?[]const u8 = null,
        window: ?[]const u8 = null,
        sound: bool = false,
        /// Системный звук: то, что идёт в колонки.
        system: bool = false,
        /// Микрофон и колонки двумя дорожками.
        separate: bool = false,
        /// Область едет за курсором (#29); только с area.
        follow: bool = false,
        /// Курсор в кадр или только в слой (#92); без параметра — как
        /// галочка в окне.
        cursor: ?Cursor = null,
        /// Вспышки на клики; без параметра — как галочка в окне.
        clicks: ?bool = null,
        fps: ?u32 = null,
        /// Качество: текст и интерфейс, видео, максимум.
        quality: ?Quality = null,
        /// Поток в килобитах в секунду; без параметра — по качеству.
        bitrate_kbps: ?u32 = null,
        /// Через сколько кадров ставить ключевой.
        gop: ?u32 = null,
        /// Остановиться самой через столько секунд; без параметра — до просьбы.
        seconds: ?u32 = null,
        /// Имя файла этой записи: можно с `%d` `%t` `%n`, как в настройках.
        name: ?[]const u8 = null,
        /// Куда положить эту запись; без параметра — папка из настроек.
        dir: ?[]const u8 = null,
    };
};

/// Разобранный запрос вместе с его номером: номер надо вернуть в ответе,
/// иначе клиент не поймёт, на что ему ответили.
pub const Parsed = struct {
    /// Номер запроса. `null` — уведомление, отвечать не нужно.
    id: ?Id = null,
    request: ?Request = null,
    /// Что не так с запросом, если он не разобрался.
    fault: ?Fault = null,
};

/// Номер запроса бывает и числом, и строкой — возвращаем его тем же, чем он
/// пришёл. Подменять число строкой нельзя: строгий клиент такого ответа
/// не признает своим.
pub const Id = union(enum) {
    number: i64,
    text: []const u8,
};

pub const Fault = enum {
    parse_error,
    invalid_request,
    method_not_found,
    invalid_params,

    pub fn code(self: Fault) i32 {
        return switch (self) {
            .parse_error => -32700,
            .invalid_request => -32600,
            .method_not_found => -32601,
            .invalid_params => -32602,
        };
    }

    /// Текст ошибки — словами и по-русски: его читает человек в журнале.
    pub fn message(self: Fault) []const u8 {
        return switch (self) {
            .parse_error => "запрос не разобрался: это не JSON",
            .invalid_request => "это не запрос JSON-RPC",
            .method_not_found => "нет такого метода",
            .invalid_params => "не хватает или не годятся параметры",
        };
    }
};

/// Разобранный запрос вместе с документом, внутрь которого он ссылается.
///
/// Владение здесь не формальность. Заголовок окна и строковый номер запроса —
/// это срезы внутрь разобранного JSON. Освободить документ и вернуть срезы
/// на него значит вернуть указатели в чужую память; поймано падением тестов.
pub const Session = struct {
    doc: ?std.json.Parsed(std.json.Value) = null,
    result: Parsed = .{},

    pub fn deinit(self: *Session) void {
        if (self.doc) |d| d.deinit();
        self.doc = null;
    }
};

/// Разобрать входящую строку. Полученное надо освободить: `defer s.deinit()`.
pub fn parse(allocator: std.mem.Allocator, line: []const u8) Session {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch {
        return .{ .result = .{ .fault = .parse_error } };
    };
    return .{ .doc = parsed, .result = parseValue(parsed.value) };
}

fn parseValue(root: std.json.Value) Parsed {
    if (root != .object) return .{ .fault = .invalid_request };
    const obj = root.object;

    var out = Parsed{};
    if (obj.get("id")) |raw| {
        out.id = switch (raw) {
            .integer => |n| Id{ .number = n },
            .string => |s| Id{ .text = s },
            else => null,
        };
    }

    // Нет номера — это уведомление, и отвечать на него нельзя ничем.
    // Клиенты шлют `notifications/cancelled`, когда человек передумал, и
    // получали в ответ ошибку с `"id":null` — мусор, который строгий клиент
    // считает поломкой протокола.
    const is_note = obj.get("id") == null;

    const method_value = obj.get("method") orelse return .{ .id = out.id, .fault = if (is_note) null else .invalid_request, .request = if (is_note) .ignore else null };
    if (method_value != .string) return .{ .id = out.id, .fault = if (is_note) null else .invalid_request, .request = if (is_note) .ignore else null };
    const method = method_value.string;

    if (std.mem.eql(u8, method, "notifications/initialized")) {
        out.request = .initialized;
        return out;
    }
    if (is_note) {
        out.request = .ignore;
        return out;
    }
    if (std.mem.eql(u8, method, "initialize")) {
        var init = Request.Initialize{};
        if (obj.get("params")) |params| {
            if (params == .object) {
                if (params.object.get("protocolVersion")) |v| {
                    if (v == .string) init.protocol = v.string;
                }
            }
        }
        out.request = .{ .initialize = init };
        return out;
    }
    if (std.mem.eql(u8, method, "ping")) {
        out.request = .ping;
        return out;
    }
    if (std.mem.eql(u8, method, "tools/list")) {
        out.request = .list_tools;
        return out;
    }
    if (!std.mem.eql(u8, method, "tools/call")) {
        return .{ .id = out.id, .fault = .method_not_found };
    }

    const params = obj.get("params") orelse return .{ .id = out.id, .fault = .invalid_params };
    if (params != .object) return .{ .id = out.id, .fault = .invalid_params };
    const name_value = params.object.get("name") orelse return .{ .id = out.id, .fault = .invalid_params };
    if (name_value != .string) return .{ .id = out.id, .fault = .invalid_params };
    const name = name_value.string;

    const args: ?std.json.ObjectMap = blk: {
        const raw = params.object.get("arguments") orelse break :blk null;
        if (raw != .object) break :blk null;
        break :blk raw.object;
    };

    if (std.mem.eql(u8, name, tool_start)) {
        var start = Request.Start{};
        if (args) |a| {
            if (a.get("monitor")) |v| if (v == .integer and v.integer >= 0) {
                start.monitor = @intCast(v.integer);
            };
            if (a.get("area")) |v| if (v == .string) {
                start.area = v.string;
            };
            if (a.get("window")) |v| if (v == .string) {
                start.window = v.string;
            };
            if (a.get("sound")) |v| if (v == .bool) {
                start.sound = v.bool;
            };
            if (a.get("system")) |v| if (v == .bool) {
                start.system = v.bool;
            };
            if (a.get("follow")) |v| if (v == .bool) {
                start.follow = v.bool;
            };
            if (a.get("cursor")) |v| if (v == .string) {
                if (std.mem.eql(u8, v.string, "burn")) start.cursor = .burn;
                if (std.mem.eql(u8, v.string, "layer")) start.cursor = .layer;
            };
            if (a.get("separate")) |v| if (v == .bool) {
                start.separate = v.bool;
            };
            if (a.get("fps")) |v| if (v == .integer and v.integer > 0) {
                start.fps = @intCast(v.integer);
            };
            if (a.get("clicks")) |v| if (v == .bool) {
                start.clicks = v.bool;
            };
            if (a.get("quality")) |v| if (v == .string) {
                start.quality = Quality.parse(v.string);
            };
            if (a.get("bitrate_kbps")) |v| if (v == .integer and v.integer > 0) {
                start.bitrate_kbps = @intCast(v.integer);
            };
            if (a.get("gop")) |v| if (v == .integer and v.integer > 0) {
                start.gop = @intCast(v.integer);
            };
            if (a.get("seconds")) |v| if (number(v)) |sec| if (sec > 0) {
                start.seconds = @intFromFloat(@min(sec, 24 * 60 * 60));
            };
            if (a.get("name")) |v| if (v == .string and v.string.len > 0) {
                start.name = v.string;
            };
            if (a.get("dir")) |v| if (v == .string and v.string.len > 0) {
                start.dir = v.string;
            };
        }
        // Источник должен быть один. Два сразу — это не «оба», это неясность,
        // и лучше сказать об этом сразу, чем снять не то.
        var sources: u8 = 0;
        if (start.area != null) sources += 1;
        if (start.window != null) sources += 1;
        if (sources > 1) return .{ .id = out.id, .fault = .invalid_params };
        out.request = .{ .start = start };
        return out;
    }
    if (std.mem.eql(u8, name, tool_stop)) {
        out.request = .stop;
        return out;
    }
    if (std.mem.eql(u8, name, tool_status)) {
        out.request = .status;
        return out;
    }
    if (std.mem.eql(u8, name, tool_monitors)) {
        out.request = .monitors;
        return out;
    }
    if (std.mem.eql(u8, name, tool_windows)) {
        out.request = .windows;
        return out;
    }
    if (std.mem.eql(u8, name, tool_pause)) {
        var pause = Pause{};
        if (args) |a| {
            if (a.get("on")) |v| if (v == .bool) {
                pause.on = v.bool;
            };
        }
        out.request = .{ .pause = pause };
        return out;
    }

    if (std.mem.eql(u8, name, tool_note)) {
        var note = Note{};
        if (args) |a| {
            if (a.get("text")) |v| if (v == .string and v.string.len > 0) {
                note.text = v.string;
            };
            if (a.get("template")) |v| if (v == .integer and v.integer > 0) {
                note.template = @intCast(v.integer);
            };
            if (a.get("colour")) |v| if (v == .string) {
                note.colour = v.string;
            };
            if (a.get("seconds")) |v| if (number(v)) |sec| {
                note.seconds = sec;
            };
        }
        out.request = .{ .note = note };
        return out;
    }

    if (std.mem.eql(u8, name, tool_events)) {
        var ask = EventsAsk{};
        if (args) |a| {
            if (a.get("from")) |v| ask.from_s = number(v) orelse 0;
            if (a.get("to")) |v| ask.to_s = number(v) orelse 0;
            if (a.get("limit")) |v| if (v == .integer and v.integer > 0) {
                ask.limit = @intCast(@min(v.integer, 10_000));
            };
        }
        out.request = .{ .events = ask };
        return out;
    }
    return .{ .id = out.id, .fault = .method_not_found };
}

pub const tool_start = "start_recording";
pub const tool_stop = "stop_recording";
pub const tool_status = "recording_status";
pub const tool_monitors = "list_monitors";
pub const tool_windows = "list_windows";
pub const tool_events = "recording_events";
pub const tool_pause = "pause_recording";
pub const tool_note = "annotate_now";

/// Число из JSON: клиенты шлют секунды и как 1, и как 1.5.
fn number(v: std.json.Value) ?f64 {
    return switch (v) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        else => null,
    };
}

/// Описание инструментов для клиента.
///
/// Описания на русском и по-человечески: их читает не программа, а модель,
/// и от того, насколько понятно написано, зависит, вызовет она нужное или нет.
pub const tools_json =
    \\[
    \\{"name":"start_recording",
    \\ "title":"Начать запись",
    \\ "annotations":{"title":"Начать запись","readOnlyHint":false,"destructiveHint":false,"idempotentHint":false,"openWorldHint":true},
    \\ "description":"Начать запись экрана в mp4. Записывает то самое окно Zig-Rec Studio, которое видит человек. Без параметров снимает весь экран.",
    \\ "inputSchema":{"type":"object","properties":{
    \\   "monitor":{"type":"integer","description":"Номер монитора; 0 — основной"},
    \\   "area":{"type":"string","description":"Прямоугольник рабочего стола: x,y,ширина,высота"},
    \\   "window":{"type":"string","description":"Часть заголовка окна; область поедет за окном"},
    \\   "sound":{"type":"boolean","description":"Писать ли звук с микрофона"},
    \\   "system":{"type":"boolean","description":"Писать ли системный звук — то, что идёт в колонки; сводится с микрофоном в одну дорожку"},
    \\   "separate":{"type":"boolean","description":"Микрофон и колонки — двумя дорожками в файле, а не одной сведённой"},
    \\   "follow":{"type":"boolean","description":"Область записи едет за курсором (только вместе с area)"},
    \\   "cursor":{"type":"string","enum":["burn","layer"],"description":"burn — курсор впечатывается в кадр (слой событий пишется всегда), layer — только слой; без параметра — как галочка «Курсор и клики» в окне"},
    \\   "fps":{"type":"integer","description":"Кадров в секунду"},
    \\   "clicks":{"type":"boolean","description":"Вспышки на клики мыши в кадре; без параметра — как галочка в окне"},
    \\   "quality":{"type":"string","enum":["text_ui","video","max"],"description":"text_ui — текст и интерфейс (по умолчанию), video — обычное видео, max — максимум качества"},
    \\   "bitrate_kbps":{"type":"integer","description":"Поток в килобитах в секунду; без параметра — по качеству"},
    \\   "gop":{"type":"integer","description":"Через сколько кадров ставить ключевой"},
    \\   "seconds":{"type":"integer","description":"Остановиться самой через столько секунд; без параметра — писать до просьбы остановить"},
    \\   "name":{"type":"string","description":"Имя файла этой записи; можно с %d — дата, %t — время, %n — номер"},
    \\   "dir":{"type":"string","description":"Куда положить эту запись; без параметра — папка из настроек"}}}},
    \\{"name":"pause_recording",
    \\ "title":"Пауза записи",
    \\ "annotations":{"title":"Пауза записи","readOnlyHint":false,"destructiveHint":false,"idempotentHint":true,"openWorldHint":true},
    \\ "description":"Поставить запись на паузу или снять паузу. Время паузы не попадает в файл: кадры после неё идут сразу за кадрами до неё.",
    \\ "inputSchema":{"type":"object","properties":{
    \\   "on":{"type":"boolean","description":"true — пауза, false — продолжить; без параметра — переключить"}}}},
    \\{"name":"annotate_now",
    \\ "title":"Надпись во время записи",
    \\ "annotations":{"title":"Надпись во время записи","readOnlyHint":false,"destructiveHint":false,"idempotentHint":false,"openWorldHint":true},
    \\ "description":"Оставить надпись в слое событий прямо во время записи — там, где сейчас курсор. В редакторе она станет аннотацией поверх кадра, а в экспорте её можно впечатать.",
    \\ "inputSchema":{"type":"object","properties":{
    \\   "text":{"type":"string","description":"Слова надписи"},
    \\   "template":{"type":"integer","description":"Готовая надпись: 1 — «Внимание», 2 — «Шаг», 3 — «Ошибка»"},
    \\   "colour":{"type":"string","enum":["yellow","red","orange","green","cyan","blue","violet","grey"],"description":"Цвет надписи; по умолчанию жёлтый"},
    \\   "seconds":{"type":"number","description":"Сколько секунд держать надпись; по умолчанию три"}}}},
    \\{"name":"stop_recording",
    \\ "title":"Остановить запись",
    \\ "annotations":{"title":"Остановить запись","readOnlyHint":false,"destructiveHint":false,"idempotentHint":true,"openWorldHint":true},
    \\ "description":"Остановить запись и вернуть путь к готовому файлу mp4.",
    \\ "inputSchema":{"type":"object","properties":{}}},
    \\{"name":"recording_status",
    \\ "title":"Состояние записи",
    \\ "annotations":{"title":"Состояние записи","readOnlyHint":true,"idempotentHint":true,"openWorldHint":false},
    \\ "description":"Идёт ли запись: состояние, сколько кадров и секунд, потери, путь захвата, размер кадра и путь к файлу.",
    \\ "inputSchema":{"type":"object","properties":{}}},
    \\{"name":"list_monitors",
    \\ "title":"Мониторы",
    \\ "annotations":{"title":"Мониторы","readOnlyHint":true,"idempotentHint":true,"openWorldHint":false},
    \\ "description":"Какие есть мониторы и их размеры.",
    \\ "inputSchema":{"type":"object","properties":{}}},
    \\{"name":"list_windows",
    \\ "title":"Окна",
    \\ "annotations":{"title":"Окна","readOnlyHint":true,"idempotentHint":false,"openWorldHint":true},
    \\ "description":"Какие есть видимые окна с заголовками.",
    \\ "inputSchema":{"type":"object","properties":{}}},
    \\{"name":"recording_events",
    \\ "title":"События последней записи",
    \\ "annotations":{"title":"События последней записи","readOnlyHint":true,"idempotentHint":true,"openWorldHint":false},
    \\ "description":"События последней записи из слоя рядом с ней: движения и клики мыши, клавиши, смена окна, область записи — со временем в секундах.",
    \\ "inputSchema":{"type":"object","properties":{
    \\   "from":{"type":"number","description":"С какой секунды записи"},
    \\   "to":{"type":"number","description":"По какую секунду; 0 или нет — до конца"},
    \\   "limit":{"type":"integer","description":"Не больше стольких событий (по умолчанию 200)"}}}}
    \\]
;

/// Ответ на рукопожатие: версия, о которой договорились, и кто мы.
pub fn writeInitialize(w: *std.Io.Writer, id: ?Id, version: []const u8, asked: ?[]const u8) !void {
    try w.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try writeId(w, id);
    try w.print(
        ",\"result\":{{\"protocolVersion\":\"{s}\",\"capabilities\":{{\"tools\":{{}}}}," ++
            "\"serverInfo\":{{\"name\":\"{s}\",\"title\":\"Zig-Rec Studio\",\"version\":\"{s}\"}}}}}}",
        .{ agreeVersion(asked), server_name, version },
    );
}

/// Ответ на `ping`: пустой результат — только он и требуется.
pub fn writePong(w: *std.Io.Writer, id: ?Id) !void {
    try w.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try writeId(w, id);
    try w.writeAll(",\"result\":{}}");
}

pub fn writeToolList(w: *std.Io.Writer, id: ?Id) !void {
    try w.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try writeId(w, id);
    try w.writeAll(",\"result\":{\"tools\":");
    try writeOneLine(w, tools_json);
    try w.writeAll("}}");
}

/// Записать текст без переносов строк.
///
/// Список инструментов записан многострочным литералом — так его можно
/// читать. Но связь построчная: получатель читает до первого перевода
/// строки, и многострочный ответ доходит до него огрызком. Для JSON перенос
/// — законный пробел, поэтому убрать его можно без последствий; на месте
/// переноса остаётся отступ следующей строки, и слова не слипаются.
fn writeOneLine(w: *std.Io.Writer, text: []const u8) !void {
    var at: usize = 0;
    while (at < text.len) {
        const stop = std.mem.indexOfAnyPos(u8, text, at, "\r\n") orelse text.len;
        if (stop > at) try w.writeAll(text[at..stop]);
        at = stop + 1;
    }
}

/// Ответ инструмента — обычный текст. Модель читает его как текст, поэтому
/// он должен быть понятной фразой, а не набором полей.
pub fn writeToolText(w: *std.Io.Writer, id: ?Id, text: []const u8, failed: bool) !void {
    try w.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try writeId(w, id);
    try w.writeAll(",\"result\":{\"content\":[{\"type\":\"text\",\"text\":");
    try writeJsonString(w, text);
    try w.print("}}],\"isError\":{s}}}}}", .{if (failed) "true" else "false"});
}

pub fn writeFault(w: *std.Io.Writer, id: ?Id, fault: Fault) !void {
    try w.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try writeId(w, id);
    try w.print(",\"error\":{{\"code\":{d},\"message\":", .{fault.code()});
    try writeJsonString(w, fault.message());
    try w.writeAll("}}");
}

fn writeId(w: *std.Io.Writer, id: ?Id) !void {
    const value = id orelse {
        try w.writeAll("null");
        return;
    };
    switch (value) {
        .number => |n| try w.print("{d}", .{n}),
        .text => |s| try writeJsonString(w, s),
    }
}

/// Строка в кавычках с экранированием.
///
/// Своё, а не готовое: тексты у нас русские и с переносами строк, и именно
/// на них ломается наивное «обернуть в кавычки». Один непроэкранированный
/// перенос — и клиент получает битый JSON вместо ответа.
pub fn writeJsonString(w: *std.Io.Writer, text: []const u8) !void {
    try w.writeByte('"');
    for (text) |ch| {
        switch (ch) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            0x08 => try w.writeAll("\\b"),
            0x0C => try w.writeAll("\\f"),
            else => {
                if (ch < 0x20) {
                    try w.print("\\u{x:0>4}", .{ch});
                } else {
                    try w.writeByte(ch);
                }
            },
        }
    }
    try w.writeByte('"');
}

// ---------------------------------------------------------------- тесты

test "рукопожатие разбирается" {
    var s = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
    );
    defer s.deinit();
    try std.testing.expect(s.result.fault == null);
    try std.testing.expect(s.result.request.? == .initialize);
    try std.testing.expectEqual(@as(i64, 1), s.result.id.?.number);
}

test "уведомление о готовности не требует ответа" {
    var s = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","method":"notifications/initialized"}
    );
    defer s.deinit();
    try std.testing.expect(s.result.request.? == .initialized);
    try std.testing.expect(s.result.id == null);
}

test "номер запроса возвращается тем же, чем пришёл" {
    // Строгий клиент не признает своим ответ, где число подменили строкой.
    var num = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":7,"method":"tools/list"}
    );
    defer num.deinit();
    try std.testing.expectEqual(@as(i64, 7), num.result.id.?.number);

    var txt = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":"abc","method":"tools/list"}
    );
    defer txt.deinit();
    try std.testing.expectEqualStrings("abc", txt.result.id.?.text);
}

test "строковый номер переживает разбор" {
    // Тот самый случай, на котором разбор падал: срез указывал внутрь
    // документа, а документ к этому времени был уже освобождён.
    var s = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":"запрос-1","method":"tools/list"}
    );
    defer s.deinit();
    // Буфер с запасом: список инструментов длинный, и коротким буфером
    // проверялся бы его размер, а не сохранность номера.
    var buf: [16 * 1024]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writeToolList(&w, s.result.id);
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "запрос-1") != null);
}

test "вызов записи без параметров — весь экран" {
    var s = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"start_recording"}}
    );
    defer s.deinit();
    try std.testing.expect(s.result.fault == null);
    const start = s.result.request.?.start;
    try std.testing.expect(start.monitor == null);
    try std.testing.expect(start.area == null);
    try std.testing.expect(start.window == null);
    try std.testing.expect(!start.sound);
}

test "вызов записи с параметрами" {
    var s = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"start_recording",
        \\ "arguments":{"window":"Блокнот","sound":true,"fps":60}}}
    );
    defer s.deinit();
    try std.testing.expect(s.result.fault == null);
    const start = s.result.request.?.start;
    try std.testing.expectEqualStrings("Блокнот", start.window.?);
    try std.testing.expect(start.sound);
    try std.testing.expectEqual(@as(u32, 60), start.fps.?);
}

test "два источника сразу — это неясность, а не «оба»" {
    var s = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"start_recording",
        \\ "arguments":{"window":"Блокнот","area":"0,0,640,480"}}}
    );
    defer s.deinit();
    try std.testing.expectEqual(Fault.invalid_params, s.result.fault.?);
}

test "остальные инструменты разбираются" {
    var stop = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"stop_recording"}}
    );
    defer stop.deinit();
    try std.testing.expect(stop.result.request.? == .stop);

    var status = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"recording_status"}}
    );
    defer status.deinit();
    try std.testing.expect(status.result.request.? == .status);

    var mons = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"list_monitors"}}
    );
    defer mons.deinit();
    try std.testing.expect(mons.result.request.? == .monitors);

    var wins = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"list_windows"}}
    );
    defer wins.deinit();
    try std.testing.expect(wins.result.request.? == .windows);
}

test "битый JSON, не запрос и неизвестное имя — разные беды" {
    var bad = parse(std.testing.allocator, "это не json");
    defer bad.deinit();
    try std.testing.expectEqual(Fault.parse_error, bad.result.fault.?);

    var no_method = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":1}
    );
    defer no_method.deinit();
    try std.testing.expectEqual(Fault.invalid_request, no_method.result.fault.?);

    var wrong_method = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":1,"method":"чего-нибудь"}
    );
    defer wrong_method.deinit();
    try std.testing.expectEqual(Fault.method_not_found, wrong_method.result.fault.?);

    var wrong_tool = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"полетели"}}
    );
    defer wrong_tool.deinit();
    try std.testing.expectEqual(Fault.method_not_found, wrong_tool.result.fault.?);
}

test "у каждой беды свой код по стандарту" {
    try std.testing.expectEqual(@as(i32, -32700), Fault.parse_error.code());
    try std.testing.expectEqual(@as(i32, -32600), Fault.invalid_request.code());
    try std.testing.expectEqual(@as(i32, -32601), Fault.method_not_found.code());
    try std.testing.expectEqual(@as(i32, -32602), Fault.invalid_params.code());
}

test "русский текст с переносом и кавычкой не ломает ответ" {
    // Наивная сборка строки ломается именно здесь: один непроэкранированный
    // перенос — и клиент получает битый JSON вместо ответа.
    var buf: [512]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const text_in = "готово: 30 кадров\nфайл \"снимок\".mp4";
    try writeToolText(&w, .{ .number = 1 }, text_in, false);
    const out = w.buffered();

    try std.testing.expect(std.mem.indexOf(u8, out, "\\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\\\"") != null);

    const back = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, out, .{});
    defer back.deinit();
    const text = back.value.object.get("result").?.object
        .get("content").?.array.items[0].object.get("text").?.string;
    try std.testing.expectEqualStrings(text_in, text);
}

test "ответ рукопожатия — годный JSON с версией протокола" {
    var buf: [512]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writeInitialize(&w, .{ .number = 1 }, "0.1.19.0", null);

    const back = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, w.buffered(), .{});
    defer back.deinit();
    const result = back.value.object.get("result").?.object;
    try std.testing.expectEqualStrings(protocol_version, result.get("protocolVersion").?.string);
    try std.testing.expectEqualStrings("zigrec", result.get("serverInfo").?.object.get("name").?.string);
    try std.testing.expectEqualStrings("0.1.19.0", result.get("serverInfo").?.object.get("version").?.string);
}

test "список инструментов — годный JSON, и в нём все, что объявлены" {
    var buf: [16 * 1024]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writeToolList(&w, .{ .number = 2 });

    const back = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, w.buffered(), .{});
    defer back.deinit();
    const list = back.value.object.get("result").?.object.get("tools").?.array;
    // Имена объявлены рядом с разбором; в списке должны быть ровно они —
    // забытый в списке инструмент клиент не увидит и не вызовет никогда.
    const names = [_][]const u8{ tool_start, tool_stop, tool_status, tool_monitors, tool_windows, tool_events, tool_pause, tool_note };
    try std.testing.expectEqual(names.len, list.items.len);
    for (names) |want| {
        var found = false;
        for (list.items) |item| {
            if (std.mem.eql(u8, item.object.get("name").?.string, want)) found = true;
        }
        if (!found) {
            std.debug.print("инструмента {s} нет в списке\n", .{want});
            return error.TestUnexpectedResult;
        }
    }
    // У каждого инструмента должно быть человеческое описание: его читает
    // модель, и от него зависит, вызовет она нужное или нет.
    for (list.items) |item| {
        try std.testing.expect(item.object.get("name").?.string.len > 0);
        try std.testing.expect(item.object.get("description").?.string.len > 20);
        try std.testing.expect(item.object.get("inputSchema") != null);
    }
}

test "ответы уходят одной строкой" {
    // Связь построчная: получатель читает до первого перевода строки.
    // Многострочный ответ дошёл бы до него огрызком — поймано стендом,
    // который говорит с сервером по-настоящему, а не разбирает готовую строку.
    var buf: [16 * 1024]u8 = undefined;

    var w1 = std.Io.Writer.fixed(&buf);
    try writeToolList(&w1, .{ .number = 1 });
    try std.testing.expect(std.mem.indexOfAny(u8, w1.buffered(), "\r\n") == null);

    var w2 = std.Io.Writer.fixed(&buf);
    try writeInitialize(&w2, .{ .number = 1 }, "0.1.19.0", null);
    try std.testing.expect(std.mem.indexOfAny(u8, w2.buffered(), "\r\n") == null);

    var w3 = std.Io.Writer.fixed(&buf);
    try writeToolText(&w3, .{ .number = 1 }, "первая строка\nвторая строка", false);
    try std.testing.expect(std.mem.indexOfAny(u8, w3.buffered(), "\r\n") == null);

    var w4 = std.Io.Writer.fixed(&buf);
    try writeFault(&w4, .{ .number = 1 }, .parse_error);
    try std.testing.expect(std.mem.indexOfAny(u8, w4.buffered(), "\r\n") == null);
}

test "ответ об ошибке — годный JSON с кодом и словами" {
    var buf: [512]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writeFault(&w, .{ .number = 9 }, .method_not_found);

    const back = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, w.buffered(), .{});
    defer back.deinit();
    const err = back.value.object.get("error").?.object;
    try std.testing.expectEqual(@as(i64, -32601), err.get("code").?.integer);
    try std.testing.expect(err.get("message").?.string.len > 0);
}

test "просьба записать системный звук разбирается" {
    var s = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"start_recording",
        \\ "arguments":{"system":true}}}
    );
    defer s.deinit();
    const start = s.result.request.?.start;
    try std.testing.expect(start.system);
    // Просили только колонки — микрофон не включается сам.
    try std.testing.expect(!start.sound);
}

test "start понимает cursor, а recording_events — отрезок и предел" {
    const a = std.testing.allocator;
    var s = parse(a,
        \\{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"start_recording","arguments":{"cursor":"layer"}}}
    );
    defer s.deinit();
    try std.testing.expectEqual(Cursor.layer, s.result.request.?.start.cursor.?);

    var e = parse(a,
        \\{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"recording_events","arguments":{"from":1.5,"to":4,"limit":7}}}
    );
    defer e.deinit();
    const ask = e.result.request.?.events;
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), ask.from_s, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 4), ask.to_s, 0.001);
    try std.testing.expectEqual(@as(u32, 7), ask.limit);

    // Без аргументов — с начала до конца, двести штук.
    var bare = parse(a,
        \\{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"recording_events"}}
    );
    defer bare.deinit();
    try std.testing.expectEqual(@as(u32, 200), bare.result.request.?.events.limit);
}

test "версию протокола выбирает клиент, если мы такую знаем" {
    // Просит новую, которую знаем, — её и называем.
    try std.testing.expectEqualStrings("2025-06-18", agreeVersion("2025-06-18"));
    try std.testing.expectEqualStrings("2025-03-26", agreeVersion("2025-03-26"));
    // Просит старую, которую знаем, — тоже её: клиент вправе просить старую.
    try std.testing.expectEqualStrings("2024-11-05", agreeVersion("2024-11-05"));
    // Не назвал или назвал незнакомую — называем свою новую.
    try std.testing.expectEqualStrings(protocol_version, agreeVersion(null));
    try std.testing.expectEqualStrings(protocol_version, agreeVersion("2019-01-01"));
    try std.testing.expectEqualStrings(protocol_version, agreeVersion(""));
    // Наша новая — первая в списке, и список не пуст.
    try std.testing.expectEqualStrings(supported_versions[0], protocol_version);
    try std.testing.expect(supported_versions.len >= 4);
}

test "рукопожатие отвечает той версией, о которой попросил клиент" {
    var s = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{}}}
    );
    defer s.deinit();
    try std.testing.expectEqualStrings("2025-06-18", s.result.request.?.initialize.protocol.?);

    var buf: [512]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writeInitialize(&w, s.result.id, "1.0.3.0", s.result.request.?.initialize.protocol);
    const back = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, w.buffered(), .{});
    defer back.deinit();
    try std.testing.expectEqualStrings(
        "2025-06-18",
        back.value.object.get("result").?.object.get("protocolVersion").?.string,
    );
}

test "рукопожатие без params — наша версия" {
    var s = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":1,"method":"initialize"}
    );
    defer s.deinit();
    try std.testing.expect(s.result.request.?.initialize.protocol == null);
    try std.testing.expect(s.result.fault == null);
}

test "ping — пустой результат" {
    var s = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":7,"method":"ping"}
    );
    defer s.deinit();
    try std.testing.expect(s.result.request.? == .ping);
    try std.testing.expect(s.result.fault == null);

    var buf: [128]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writePong(&w, s.result.id);
    const back = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, w.buffered(), .{});
    defer back.deinit();
    try std.testing.expectEqual(@as(usize, 0), back.value.object.get("result").?.object.count());
    try std.testing.expectEqual(@as(i64, 7), back.value.object.get("id").?.integer);
}

test "на уведомление не отвечаем ничем — ни ответом, ни ошибкой" {
    // Клиенты шлют его, когда человек передумал ждать.
    var cancelled = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":1}}
    );
    defer cancelled.deinit();
    try std.testing.expect(cancelled.result.request.? == .ignore);
    try std.testing.expect(cancelled.result.fault == null);

    // Незнакомое уведомление — тоже молчим.
    var unknown = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","method":"notifications/чего-то-новенького"}
    );
    defer unknown.deinit();
    try std.testing.expect(unknown.result.request.? == .ignore);
    try std.testing.expect(unknown.result.fault == null);

    // Без метода вовсе — и то молчим: номера нет, отвечать некому.
    var no_method = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","params":{}}
    );
    defer no_method.deinit();
    try std.testing.expect(no_method.result.request.? == .ignore);
    try std.testing.expect(no_method.result.fault == null);

    // А вот с номером незнакомый метод — честная ошибка.
    var asked = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":3,"method":"чего-то-новенького"}
    );
    defer asked.deinit();
    try std.testing.expectEqual(Fault.method_not_found, asked.result.fault.?);
}

test "у каждого инструмента есть подпись и подсказки поведения" {
    const doc = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, tools_json, .{});
    defer doc.deinit();
    for (doc.value.array.items) |tool| {
        const o = tool.object;
        const name = o.get("name").?.string;
        try std.testing.expect(o.get("title") != null);
        const ann = o.get("annotations") orelse {
            std.debug.print("у инструмента {s} нет подсказок поведения\n", .{name});
            return error.TestUnexpectedResult;
        };
        try std.testing.expect(ann.object.get("readOnlyHint") != null);
        // Читающий инструмент ничего не меняет: у него нет destructiveHint.
        if (ann.object.get("readOnlyHint").?.bool) {
            try std.testing.expect(ann.object.get("destructiveHint") == null);
        }
    }
}

test "запись: качество, поток, ключевые кадры, клики, срок, имя и папка" {
    var s = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"start_recording",
        \\ "arguments":{"quality":"max","bitrate_kbps":9000,"gop":15,"clicks":false,
        \\ "seconds":12,"name":"урок-%n.mp4","dir":"D:\\видео"}}}
    );
    defer s.deinit();
    try std.testing.expect(s.result.fault == null);
    const start = s.result.request.?.start;
    try std.testing.expectEqual(Quality.max, start.quality.?);
    try std.testing.expectEqual(@as(u32, 9000), start.bitrate_kbps.?);
    try std.testing.expectEqual(@as(u32, 15), start.gop.?);
    try std.testing.expectEqual(false, start.clicks.?);
    try std.testing.expectEqual(@as(u32, 12), start.seconds.?);
    try std.testing.expectEqualStrings("урок-%n.mp4", start.name.?);
    try std.testing.expectEqualStrings("D:\\видео", start.dir.?);
}

test "качество: чужое слово не принимается молча" {
    try std.testing.expectEqual(Quality.text_ui, Quality.parse("text_ui").?);
    try std.testing.expectEqual(Quality.text_ui, Quality.parse("text").?);
    try std.testing.expectEqual(Quality.video, Quality.parse("video").?);
    try std.testing.expectEqual(Quality.max, Quality.parse("max").?);
    try std.testing.expect(Quality.parse("получше") == null);
    try std.testing.expect(Quality.parse("") == null);
}

test "срок записи: ноль и мусор не ставят срока" {
    var zero = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"start_recording","arguments":{"seconds":0}}}
    );
    defer zero.deinit();
    try std.testing.expect(zero.result.request.?.start.seconds == null);

    var words = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"start_recording","arguments":{"seconds":"чуть-чуть"}}}
    );
    defer words.deinit();
    try std.testing.expect(words.result.request.?.start.seconds == null);

    // Полминуты дробью — законная просьба: считаем в секундах вниз.
    var half = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"start_recording","arguments":{"seconds":1.5}}}
    );
    defer half.deinit();
    try std.testing.expectEqual(@as(u32, 1), half.result.request.?.start.seconds.?);
}

test "пауза: названная и переключаемая" {
    var on = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"pause_recording","arguments":{"on":true}}}
    );
    defer on.deinit();
    try std.testing.expectEqual(true, on.result.request.?.pause.on.?);

    var off = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"pause_recording","arguments":{"on":false}}}
    );
    defer off.deinit();
    try std.testing.expectEqual(false, off.result.request.?.pause.on.?);

    // Без параметра — переключить, как кнопка в окне.
    var toggle = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"pause_recording"}}
    );
    defer toggle.deinit();
    try std.testing.expect(toggle.result.request.?.pause.on == null);
}

test "надпись во время записи: слова, цвет, длительность, шаблон" {
    var words = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"annotate_now",
        \\ "arguments":{"text":"тут главное","colour":"red","seconds":2.5}}}
    );
    defer words.deinit();
    const note = words.result.request.?.note;
    try std.testing.expectEqualStrings("тут главное", note.text.?);
    try std.testing.expectEqualStrings("red", note.colour.?);
    try std.testing.expectEqual(@as(f64, 2.5), note.seconds.?);
    try std.testing.expect(note.template == null);

    var tpl = parse(std.testing.allocator,
        \\{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"annotate_now","arguments":{"template":2}}}
    );
    defer tpl.deinit();
    try std.testing.expectEqual(@as(u32, 2), tpl.result.request.?.note.template.?);
    try std.testing.expect(tpl.result.request.?.note.text == null);
}
