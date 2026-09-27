//! Захват экрана: DXGI Desktop Duplication и запасной путь через GDI.
//!
//! Задача #13. DXGI — самый быстрый путь на Windows: кадры отдаются уже в
//! видеопамяти. Но у него есть условие, о котором молчат руководства: рабочий
//! стол должен **презентовать** кадры. Погашенный монитор, машина без дисплея,
//! удалённая работа — презентов нет, и `AcquireNextFrame` отдаёт таймаут вместо
//! картинки. Проверено на этой машине: за тридцать секунд с перерисовкой
//! видимого окна DXGI не отдал ни одного кадра, а GDI снял девять из десяти.
//!
//! Поэтому бэкендов два, и выбор между ними — не настройка для знатоков,
//! а поведение по умолчанию: `.auto` начинает с DXGI и, если тот **ни разу**
//! ничего не отдал, молча переходит на GDI. Однажды сработавший DXGI считается
//! рабочим и не понижается.
//!
//! Потеря доступа (смена разрешения, затемнение UAC, переключение пользователя,
//! полноэкранная игра) — не ошибка, а обычный режим: дубликация пересоздаётся
//! на месте.
const std = @import("std");
const lang = @import("../lang.zig");
const builtin = @import("builtin");
const win32 = @import("../win32.zig");
const c = win32.c;
const types = @import("capture_types.zig");
const gdi = @import("gdi.zig");
const wgc = @import("wgc.zig");

pub const Error = types.Error;
pub const Rect = types.Rect;
pub const Frame = types.Frame;
pub const Stats = types.Stats;
pub const GdiGrabber = gdi.Grabber;
pub const WindowCapture = wgc.WindowCapture;

pub const Backend = enum {
    /// Начать с DXGI, перейти на GDI, если тот не даёт кадров вовсе.
    auto,
    dxgi,
    gdi,
    /// Windows Graphics Capture: содержимое одного окна, даже перекрытого
    /// и на другом мониторе (см. `wgc.zig`). Только вместе с окном.
    wgc,

    pub fn label(self: Backend) []const u8 {
        return switch (self) {
            .auto => lang.t("авто"),
            .dxgi => "DXGI",
            .gdi => "GDI",
            .wgc => "WGC",
        };
    }
};

pub const Options = struct {
    backend: Backend = .auto,
    /// Индекс монитора для DXGI.
    output: u32 = 0,
    /// Область для GDI; `null` — весь экран.
    area: ?Rect = null,
    /// Сколько ждать первого кадра от DXGI, прежде чем перейти на GDI.
    ///
    /// Четыреста миллисекунд, а не полторы секунды (#136): полторы съедали
    /// короткую запись целиком — на машине, где дубликация молчит, просьба
    /// «запиши секунду» возвращала «0 кадров», хотя сразу после понижения
    /// запись идёт. Ждать долго незачем: на неподвижном экране GDI тоже
    /// ничего не отдаёт (он сравнивает кадры), так что раннее понижение
    /// ничего не портит — оно лишь не тратит время впустую.
    downgrade_after_ms: u32 = 400,
    /// GDI отдаёт кадр на каждый вызов, даже без изменений (#29, автопанорама).
    always_frames: bool = false,
    /// Окно для WGC. Другим бэкендам не нужно: они снимают стол.
    window: ?c.HWND = null,
    /// Точка рабочего стола, чей монитор снимать (#121). Задана — выход DXGI
    /// выбирается по ней, а не по `output`: окно и область лежат где угодно,
    /// а номер монитора человек для них не называет.
    at: ?Point = null,
};

pub const Point = struct { x: i32, y: i32 };

/// Лежит ли точка в прямоугольнике рабочего стола (правая и нижняя
/// границы — не включительно, как у `RECT` Windows).
pub fn contains(left: i32, top: i32, right: i32, bottom: i32, p: Point) bool {
    return p.x >= left and p.x < right and p.y >= top and p.y < bottom;
}

/// Больше выходов у одного адаптера не перебираем: это и так стенка мониторов.
const max_outputs: u32 = 16;

/// Имя из DXGI (UTF-16 с нулём в конце) — в ASCII-буфер, чужие знаки как «?».
fn narrow(out: []u8, wide_name: []const u16) usize {
    var n: usize = 0;
    for (wide_name) |ch| {
        if (ch == 0 or n >= out.len) break;
        out[n] = if (ch < 128) @intCast(ch) else '?';
        n += 1;
    }
    return n;
}

/// Какую область выхода копировать (#104): обрезанную по его границам и с
/// чётными сторонами, как любит кодировщик. `null` — области не осталось.
///
/// Отдельной функцией, потому что проверить её можно без видеокарты, а
/// ошибка здесь — это копия за пределами текстуры: молчаливая порча памяти
/// или отказ драйвера в середине записи.
pub fn pickArea(want: Rect, out_w: u32, out_h: u32) ?Rect {
    if (out_w == 0 or out_h == 0) return null;
    const clamped = want.clampTo(out_w, out_h).evenSized();
    if (clamped.isEmpty()) return null;
    // После обрезки и чётности прямоугольник обязан лежать внутри выхода:
    // это то, на что смотрит драйвер, и проверять это надо здесь.
    if (clamped.x < 0 or clamped.y < 0) return null;
    const right = @as(i64, clamped.x) + clamped.width;
    const bottom = @as(i64, clamped.y) + clamped.height;
    if (right > out_w or bottom > out_h) return null;
    return clamped;
}

/// Захват одного выхода (монитора) через DXGI Desktop Duplication.
pub const Duplicator = struct {
    allocator: std.mem.Allocator,
    output_index: u32,
    device: *c.ID3D11Device = undefined,
    context: *c.ID3D11DeviceContext = undefined,
    dupl: *c.IDXGIOutputDuplication = undefined,
    staging: ?*c.ID3D11Texture2D = null,
    width: u32 = 0,
    height: u32 = 0,
    /// Где выход лежит на рабочем столе. Нужно, чтобы перевести координаты
    /// окна и области в координаты кадра: у второго монитора начало не в нуле.
    /// Какую часть выхода копируем в память (#104). `null` — весь выход.
    ///
    /// Копия всего выхода стоила дорого зря: ради области 1920x1080 с
    /// четырёхкилометрового стола в память шло 33 МБ вместо 8, и на кадр
    /// уходило 15 мс вместо четырёх — запись не дотягивала до шестидесяти
    /// кадров ни при каком процессоре.
    area: ?Rect = null,
    /// Размер кадра, который отдаём: область, если она задана, иначе выход.
    frame_w: u32 = 0,
    frame_h: u32 = 0,
    /// Не брать кадры чаще, чем раз в столько наносекунд (#104). Ноль — брать
    /// все. Проверяется до копии в память: лишний кадр не стоит ничего, кроме
    /// отказа от него.
    min_gap_ns: u64 = 0,
    last_taken_ns: u64 = 0,
    origin_x: i32 = 0,
    origin_y: i32 = 0,
    /// Кадр удерживается системой между `next` и `release`.
    holding: bool = false,
    mapped: bool = false,
    stats: Stats = .{},
    /// Какой адаптер и какой выход дублируем — для отчёта стенда: на машине
    /// с двумя видеокартами дубликация молчит, если устройство не на той.
    adapter_name: [128]u8 = @splat(0),
    adapter_len: usize = 0,
    output_name: [32]u8 = @splat(0),
    output_len: usize = 0,

    pub fn adapterName(self: *const Duplicator) []const u8 {
        return self.adapter_name[0..self.adapter_len];
    }

    pub fn outputName(self: *const Duplicator) []const u8 {
        return self.output_name[0..self.output_len];
    }

    pub fn init(allocator: std.mem.Allocator, output_index: u32) Error!Duplicator {
        if (builtin.os.tag != .windows) return Error.Unsupported;
        var self = Duplicator{ .allocator = allocator, .output_index = output_index };
        try self.createDevice();
        errdefer self.releaseDevice();
        try self.createDuplication();
        return self;
    }

    /// Дубликация того выхода, на котором лежит точка рабочего стола (#121).
    ///
    /// Номер выхода DXGI и номер монитора в `monitors` — разные нумерации,
    /// поэтому ищем по месту, а не по номеру. Нет такого выхода (точка между
    /// мониторами, монитор на другой видеокарте) — `NoOutput`.
    pub fn initAt(allocator: std.mem.Allocator, at: Point) Error!Duplicator {
        if (builtin.os.tag != .windows) return Error.Unsupported;
        var i: u32 = 0;
        while (i < max_outputs) : (i += 1) {
            var d = Duplicator.init(allocator, i) catch |err| switch (err) {
                Error.NoOutput => return Error.NoOutput,
                else => return err,
            };
            const right = d.origin_x + @as(i32, @intCast(d.width));
            const bottom = d.origin_y + @as(i32, @intCast(d.height));
            if (contains(d.origin_x, d.origin_y, right, bottom, at)) return d;
            d.deinit();
        }
        return Error.NoOutput;
    }

    pub fn deinit(self: *Duplicator) void {
        if (builtin.os.tag != .windows) return;
        self.releaseFrame();
        if (self.staging) |t| {
            _ = t.lpVtbl.*.Release.?(@ptrCast(t));
            self.staging = null;
        }
        _ = self.dupl.lpVtbl.*.Release.?(@ptrCast(self.dupl));
        self.releaseDevice();
    }

    fn releaseDevice(self: *Duplicator) void {
        _ = self.context.lpVtbl.*.Release.?(@ptrCast(self.context));
        _ = self.device.lpVtbl.*.Release.?(@ptrCast(self.device));
    }

    fn createDevice(self: *Duplicator) Error!void {
        var device: ?*c.ID3D11Device = null;
        var context: ?*c.ID3D11DeviceContext = null;
        var level: c.D3D_FEATURE_LEVEL = 0;
        // BGRA_SUPPORT: рабочий стол приходит именно в BGRA, а Direct2D для
        // отрисовки курсора и рамки потом потребует того же устройства.
        const flags: c.UINT = c.D3D11_CREATE_DEVICE_BGRA_SUPPORT;
        const hres = c.D3D11CreateDevice(
            null,
            c.D3D_DRIVER_TYPE_HARDWARE,
            null,
            flags,
            null,
            0,
            c.D3D11_SDK_VERSION,
            &device,
            &level,
            &context,
        );
        if (win32.failed(hres) or device == null or context == null) return Error.NoDevice;
        self.device = device.?;
        self.context = context.?;
    }

    fn createDuplication(self: *Duplicator) Error!void {
        var dxgi_device: ?*c.IDXGIDevice = null;
        if (win32.failed(self.device.lpVtbl.*.QueryInterface.?(
            @ptrCast(self.device),
            &c.IID_IDXGIDevice,
            @ptrCast(&dxgi_device),
        ))) return Error.NoDevice;
        defer _ = dxgi_device.?.lpVtbl.*.Release.?(@ptrCast(dxgi_device.?));

        var adapter: ?*c.IDXGIAdapter = null;
        if (win32.failed(dxgi_device.?.lpVtbl.*.GetAdapter.?(dxgi_device.?, &adapter))) return Error.NoDevice;
        defer _ = adapter.?.lpVtbl.*.Release.?(@ptrCast(adapter.?));
        var adesc: c.DXGI_ADAPTER_DESC = undefined;
        if (!win32.failed(adapter.?.lpVtbl.*.GetDesc.?(adapter.?, &adesc))) {
            self.adapter_len = narrow(&self.adapter_name, &adesc.Description);
        }

        var output: ?*c.IDXGIOutput = null;
        if (win32.failed(adapter.?.lpVtbl.*.EnumOutputs.?(adapter.?, self.output_index, &output))) return Error.NoOutput;
        defer _ = output.?.lpVtbl.*.Release.?(@ptrCast(output.?));

        var desc: c.DXGI_OUTPUT_DESC = undefined;
        if (win32.failed(output.?.lpVtbl.*.GetDesc.?(output.?, &desc))) return Error.NoOutput;
        self.output_len = narrow(&self.output_name, &desc.DeviceName);
        self.width = @intCast(desc.DesktopCoordinates.right - desc.DesktopCoordinates.left);
        self.height = @intCast(desc.DesktopCoordinates.bottom - desc.DesktopCoordinates.top);
        self.origin_x = desc.DesktopCoordinates.left;
        self.origin_y = desc.DesktopCoordinates.top;

        var output1: ?*c.IDXGIOutput1 = null;
        if (win32.failed(output.?.lpVtbl.*.QueryInterface.?(
            @ptrCast(output.?),
            &c.IID_IDXGIOutput1,
            @ptrCast(&output1),
        ))) return Error.NoOutput;
        defer _ = output1.?.lpVtbl.*.Release.?(@ptrCast(output1.?));

        var dupl: ?*c.IDXGIOutputDuplication = null;
        const hres = output1.?.lpVtbl.*.DuplicateOutput.?(output1.?, @ptrCast(self.device), &dupl);
        if (win32.failed(hres)) {
            return switch (win32.hrCode(hres)) {
                win32.hr.access_denied, win32.hr.e_access_denied => Error.AccessDenied,
                win32.hr.not_currently_available => Error.AccessDenied,
                else => Error.Failed,
            };
        }
        self.dupl = dupl.?;
    }

    /// Пересоздать дубликацию после потери доступа. Устройство переживает
    /// потерю, поэтому пересоздаём только дубликацию и staging.
    fn recover(self: *Duplicator) Error!void {
        self.releaseFrame();
        _ = self.dupl.lpVtbl.*.Release.?(@ptrCast(self.dupl));
        if (self.staging) |t| {
            _ = t.lpVtbl.*.Release.?(@ptrCast(t));
            self.staging = null;
        }
        // Экран после смены режима отдаёт дубликацию не мгновенно.
        var attempt: u32 = 0;
        while (attempt < 20) : (attempt += 1) {
            if (self.createDuplication()) |_| {
                self.stats.recoveries += 1;
                return;
            } else |err| switch (err) {
                Error.NoOutput, Error.AccessDenied, Error.Failed => c.Sleep(50),
                else => return err,
            }
        }
        return Error.Lost;
    }

    fn ensureStaging(self: *Duplicator, src: *c.ID3D11Texture2D) Error!void {
        var desc: c.D3D11_TEXTURE2D_DESC = undefined;
        src.lpVtbl.*.GetDesc.?(src, &desc);
        // Нужен размер кадра, а не выхода: с областью поверхность меньше (#104).
        const want_w: c.UINT = if (self.area) |a| a.width else desc.Width;
        const want_h: c.UINT = if (self.area) |a| a.height else desc.Height;
        if (self.staging) |t| {
            var have: c.D3D11_TEXTURE2D_DESC = undefined;
            t.lpVtbl.*.GetDesc.?(t, &have);
            if (have.Width == want_w and have.Height == want_h and have.Format == desc.Format) {
                self.frame_w = want_w;
                self.frame_h = want_h;
                return;
            }
            _ = t.lpVtbl.*.Release.?(@ptrCast(t));
            self.staging = null;
        }
        var sdesc = desc;
        sdesc.Width = want_w;
        sdesc.Height = want_h;
        sdesc.Usage = c.D3D11_USAGE_STAGING;
        sdesc.BindFlags = 0;
        sdesc.CPUAccessFlags = c.D3D11_CPU_ACCESS_READ;
        sdesc.MiscFlags = 0;
        sdesc.MipLevels = 1;
        sdesc.ArraySize = 1;
        sdesc.SampleDesc.Count = 1;
        sdesc.SampleDesc.Quality = 0;
        var tex: ?*c.ID3D11Texture2D = null;
        if (win32.failed(self.device.lpVtbl.*.CreateTexture2D.?(self.device, &sdesc, null, &tex))) return Error.OutOfMemory;
        self.staging = tex.?;
        // `width`/`height` — размер выхода, он задан при создании дубликации
        // и здесь не меняется: по нему выбирают область и считают координаты.
        self.frame_w = want_w;
        self.frame_h = want_h;
    }

    /// Не брать кадры чаще заказанного (#104). Ноль — без ограничения.
    pub fn setRate(self: *Duplicator, fps: u32) void {
        self.min_gap_ns = if (fps == 0) 0 else std.time.ns_per_s / fps;
    }

    /// Снимать только этот прямоугольник выхода (#104).
    ///
    /// Прямоугольник — в координатах выхода, от его левого верхнего угла:
    /// ровно так его считает цикл записи. Сдвиг при том же размере ничего не
    /// пересоздаёт — меняется только место, откуда копируем.
    pub fn focus(self: *Duplicator, want: Rect) Error!void {
        if (builtin.os.tag != .windows) return Error.Unsupported;
        const clamped = pickArea(want, self.width, self.height) orelse return Error.NoOutput;
        const same_size = if (self.area) |a| a.width == clamped.width and a.height == clamped.height else false;
        self.area = clamped;
        if (same_size) return;
        // Размер сменился — поверхность под кадр нужна другая. Освобождаем
        // её здесь, а заводит заново `ensureStaging` при следующем кадре:
        // держать в двух местах логику её размера — верный способ разойтись.
        self.releaseFrame();
        if (self.staging) |t| {
            _ = t.lpVtbl.*.Release.?(@ptrCast(t));
            self.staging = null;
        }
    }

    /// Отпустить кадр: система не отдаст следующий, пока держим текущий.
    pub fn release(self: *Duplicator) void {
        self.releaseFrame();
    }

    fn releaseFrame(self: *Duplicator) void {
        if (self.mapped) {
            if (self.staging) |t| self.context.lpVtbl.*.Unmap.?(self.context, @ptrCast(t), 0);
            self.mapped = false;
        }
        if (self.holding) {
            _ = self.dupl.lpVtbl.*.ReleaseFrame.?(self.dupl);
            self.holding = false;
        }
    }

    /// Следующий кадр или `null`, если за `timeout_ms` экран не презентовал новый.
    pub fn next(self: *Duplicator, timeout_ms: u32) Error!?Frame {
        if (builtin.os.tag != .windows) return Error.Unsupported;
        self.releaseFrame();

        var info: c.DXGI_OUTDUPL_FRAME_INFO = undefined;
        var resource: ?*c.IDXGIResource = null;
        const hres = self.dupl.lpVtbl.*.AcquireNextFrame.?(self.dupl, timeout_ms, &info, &resource);
        if (win32.failed(hres)) {
            return switch (win32.hrCode(hres)) {
                win32.hr.wait_timeout => blk: {
                    self.stats.idle += 1;
                    break :blk null;
                },
                win32.hr.access_lost => blk: {
                    try self.recover();
                    break :blk null;
                },
                win32.hr.access_denied, win32.hr.e_access_denied => Error.AccessDenied,
                else => Error.Failed,
            };
        }
        self.holding = true;
        defer if (resource) |r| {
            _ = r.lpVtbl.*.Release.?(@ptrCast(r));
        };

        // Только курсор шевельнулся: картинка та же, кодировать нечего.
        if (info.LastPresentTime.QuadPart == 0) {
            self.stats.idle += 1;
            self.releaseFrame();
            return null;
        }

        // Кадр раньше своего слота (#104): отпускаем, не копируя. Допуск —
        // четверть шага, иначе при кадрах чаще слота выходит перекос вниз.
        if (self.min_gap_ns > 0 and self.last_taken_ns > 0) {
            const now = win32.nowNs();
            const since = now -| self.last_taken_ns;
            if (since + self.min_gap_ns / 4 < self.min_gap_ns) {
                self.stats.paced += 1;
                self.releaseFrame();
                return null;
            }
        }

        var tex: ?*c.ID3D11Texture2D = null;
        if (win32.failed(resource.?.lpVtbl.*.QueryInterface.?(
            @ptrCast(resource.?),
            &c.IID_ID3D11Texture2D,
            @ptrCast(&tex),
        ))) return Error.Failed;
        defer _ = tex.?.lpVtbl.*.Release.?(@ptrCast(tex.?));

        try self.ensureStaging(tex.?);
        if (self.area) |a| {
            // Копируем только область (#104): вчетверо меньше памяти на кадр
            // при съёмке 1080p с четырёхкилометрового стола.
            var box = c.D3D11_BOX{
                .left = @intCast(a.x),
                .top = @intCast(a.y),
                .front = 0,
                .right = @intCast(a.x + @as(i32, @intCast(a.width))),
                .bottom = @intCast(a.y + @as(i32, @intCast(a.height))),
                .back = 1,
            };
            self.context.lpVtbl.*.CopySubresourceRegion.?(self.context, @ptrCast(self.staging.?), 0, 0, 0, 0, @ptrCast(tex.?), 0, &box);
        } else {
            self.context.lpVtbl.*.CopyResource.?(self.context, @ptrCast(self.staging.?), @ptrCast(tex.?));
        }

        var mapped: c.D3D11_MAPPED_SUBRESOURCE = undefined;
        if (win32.failed(self.context.lpVtbl.*.Map.?(
            self.context,
            @ptrCast(self.staging.?),
            0,
            c.D3D11_MAP_READ,
            0,
            &mapped,
        ))) return Error.Failed;
        self.mapped = true;

        const stride: u32 = mapped.RowPitch;
        const bytes: usize = @as(usize, stride) * self.frame_h;
        const ptr: [*]const u8 = @ptrCast(mapped.pData.?);

        const accumulated: u32 = info.AccumulatedFrames;
        self.last_taken_ns = win32.nowNs();
        self.stats.frames += 1;
        if (accumulated > 1) self.stats.dropped += accumulated - 1;

        return Frame{
            .pixels = ptr[0..bytes],
            .width = self.frame_w,
            .height = self.frame_h,
            .stride = stride,
            .timestamp_ns = win32.nowNs(),
            .accumulated = accumulated,
        };
    }
};

/// Захват поверх обоих бэкендов: наружу одинаковый кадр, внутри — выбор пути.
pub const Capturer = struct {
    which: union(enum) {
        dxgi: Duplicator,
        gdi: GdiGrabber,
        wgc: WindowCapture,
    },
    allocator: std.mem.Allocator,
    opt: Options,
    opened_ns: u64 = 0,
    downgraded: bool = false,
    /// Сколько ждали молчащий DXGI (#136).
    downgrade_wait_ms: u32 = 0,

    pub fn open(allocator: std.mem.Allocator, opt: Options) Error!Capturer {
        if (builtin.os.tag != .windows) return Error.Unsupported;
        return switch (opt.backend) {
            .wgc => .{
                .which = .{ .wgc = try WindowCapture.init(opt.window orelse return Error.NoOutput) },
                .allocator = allocator,
                .opt = opt,
                .opened_ns = win32.nowNs(),
            },
            .gdi => .{
                .which = .{ .gdi = try GdiGrabber.initWith(allocator, opt.area, opt.always_frames) },
                .allocator = allocator,
                .opt = opt,
                .opened_ns = win32.nowNs(),
            },
            .dxgi => .{
                .which = .{ .dxgi = try openDuplicator(allocator, opt) },
                .allocator = allocator,
                .opt = opt,
                .opened_ns = win32.nowNs(),
            },
            // DXGI может не создаться вовсе (нет адаптера, выход занят) —
            // это не повод отказываться от записи, если GDI справится.
            .auto => blk: {
                if (openDuplicator(allocator, opt)) |d| {
                    break :blk Capturer{
                        .which = .{ .dxgi = d },
                        .allocator = allocator,
                        .opt = opt,
                        .opened_ns = win32.nowNs(),
                    };
                } else |_| {
                    break :blk Capturer{
                        .which = .{ .gdi = try GdiGrabber.initWith(allocator, opt.area, opt.always_frames) },
                        .allocator = allocator,
                        .opt = opt,
                        .opened_ns = win32.nowNs(),
                        .downgraded = true,
                    };
                }
            },
        };
    }

    fn openDuplicator(allocator: std.mem.Allocator, opt: Options) Error!Duplicator {
        return if (opt.at) |p| Duplicator.initAt(allocator, p) else Duplicator.init(allocator, opt.output);
    }

    pub fn deinit(self: *Capturer) void {
        switch (self.which) {
            .dxgi => |*d| d.deinit(),
            .gdi => |*g| g.deinit(),
            .wgc => |*v| v.deinit(),
        }
    }

    pub fn backend(self: Capturer) Backend {
        return switch (self.which) {
            .dxgi => .dxgi,
            .gdi => .gdi,
            .wgc => .wgc,
        };
    }

    pub fn stats(self: Capturer) Stats {
        return switch (self.which) {
            .dxgi => |d| d.stats,
            .gdi => |g| g.stats,
            .wgc => |v| v.stats,
        };
    }

    pub fn frameSize(self: Capturer) Rect {
        return switch (self.which) {
            .dxgi => |d| .{ .x = d.origin_x, .y = d.origin_y, .width = d.width, .height = d.height },
            .gdi => |g| g.area,
            .wgc => |v| v.frameSize(),
        };
    }

    /// Снимать только область (#30, #104): умеют все пути.
    ///
    /// Возвращает, стал ли кадр самой областью — тогда его не режут, а берут
    /// с нуля. Ответ «нет» законен: не вышло — режем, как раньше.
    pub fn focus(self: *Capturer, area: Rect) bool {
        return switch (self.which) {
            .dxgi => |*d| blk: {
                d.focus(area) catch break :blk false;
                break :blk true;
            },
            // WGC и так отдаёт одно окно с нуля: резать нечего.
            .wgc => true,
            .gdi => |*g| blk: {
                g.focus(area) catch break :blk false;
                break :blk true;
            },
        };
    }

    /// Заказанный темп съёмки (#104): лишние кадры не снимаются и не
    /// копируются. Ноль — снимать всё, что даёт экран.
    ///
    /// Возвращает, держит ли путь темп сам. Это важнее, чем кажется: если
    /// темп держат оба — и захват, и цикл записи, — они спорят. Захват отдаёт
    /// кадр ровно в слот, у цикла свои часы, кадр приходит на пару миллисекунд
    /// «раньше срока», цикл его отвергает и ждёт следующего — целый слот
    /// впустую. Так тридцать заказанных превращались в двадцать пять.
    pub fn setRate(self: *Capturer, fps: u32) bool {
        switch (self.which) {
            .dxgi => |*d| {
                d.setRate(fps);
                return true;
            },
            .gdi => |*g| {
                g.setRate(fps);
                return true;
            },
            // WGC отдаёт кадры сам, по перерисовкам окна: темп за ним следит
            // цикл записи.
            .wgc => return false,
        }
    }

    pub fn release(self: *Capturer) void {
        switch (self.which) {
            .dxgi => |*d| d.release(),
            .gdi => |*g| g.release(),
            .wgc => |*v| v.release(),
        }
    }

    /// Снятое до этого момента не отдавать (#95). Зовут после паузы записи:
    /// у GDI кадр из потока захвата пережил бы паузу со старой меткой времени.
    /// DXGI кадров впрок не держит — ему сбрасывать нечего.
    pub fn flush(self: *Capturer) void {
        switch (self.which) {
            .dxgi, .wgc => {},
            .gdi => |*g| g.flush(),
        }
    }

    pub fn next(self: *Capturer, timeout_ms: u32) Error!?Frame {
        switch (self.which) {
            .gdi => |*g| return g.next(timeout_ms),
            .wgc => |*v| return v.next(timeout_ms),
            .dxgi => |*d| {
                const frame = try d.next(timeout_ms);
                if (frame != null) return frame;
                if (self.shouldDowngrade(d.*)) try self.downgrade();
                return null;
            },
        }
    }

    /// Понижаться только если DXGI не отдал НИ ОДНОГО кадра за отведённое время.
    /// Один отданный кадр означает, что путь рабочий, и дальше молчание —
    /// это просто неподвижный экран, а не поломка.
    fn shouldDowngrade(self: Capturer, d: Duplicator) bool {
        if (self.opt.backend != .auto or self.downgraded) return false;
        if (d.stats.frames > 0) return false;
        const waited = win32.nowNs() -| self.opened_ns;
        return waited > @as(u64, self.opt.downgrade_after_ms) * std.time.ns_per_ms;
    }

    /// Сколько времени ушло на молчащий DXGI, прежде чем перешли на GDI.
    /// Ноль — не понижались. Наружу: итог записи обязан сказать словами,
    /// почему первые кадры появились позже начала (#136).
    pub fn downgradeWaitMs(self: Capturer) u32 {
        return self.downgrade_wait_ms;
    }

    fn downgrade(self: *Capturer) Error!void {
        const kept = self.stats();
        self.downgrade_wait_ms = @intCast((win32.nowNs() -| self.opened_ns) / std.time.ns_per_ms);
        switch (self.which) {
            .dxgi => |*d| d.deinit(),
            .gdi, .wgc => return,
        }
        var g = try GdiGrabber.initWith(self.allocator, self.opt.area, self.opt.always_frames);
        // Простои DXGI не теряем: по ним видно, сколько времени ушло впустую.
        g.stats.idle = kept.idle;
        self.which = .{ .gdi = g };
        self.downgraded = true;
    }
};

test "точка в прямоугольнике: правая и нижняя границы не включительно" {
    try std.testing.expect(contains(3840, 0, 7680, 2160, .{ .x = 3851, .y = 10 }));
    try std.testing.expect(!contains(0, 0, 3840, 2160, .{ .x = 3840, .y = 10 }));
    try std.testing.expect(contains(0, 0, 3840, 2160, .{ .x = 3839, .y = 2159 }));
    try std.testing.expect(!contains(0, 0, 3840, 2160, .{ .x = 10, .y = 2160 }));
    try std.testing.expect(contains(-1920, 0, 0, 1080, .{ .x = -1, .y = 0 }));
}

test "названия бэкендов" {
    try std.testing.expectEqualStrings("DXGI", Backend.dxgi.label());
    try std.testing.expectEqualStrings("GDI", Backend.gdi.label());
    try std.testing.expectEqualStrings("WGC", Backend.wgc.label());
}

test "WGC без окна не открывается" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    try std.testing.expectError(Error.NoOutput, Capturer.open(std.testing.allocator, .{ .backend = .wgc }));
}

test "типы захвата переэкспортированы" {
    const r = (Rect{ .width = 1749, .height = 1009 }).evenSized();
    try std.testing.expectEqual(@as(u32, 1748), r.width);
}

test "область копии обрезается по выходу и остаётся внутри него" {
    // Обычный случай: область целиком внутри — берётся как есть.
    const inside = pickArea(.{ .x = 100, .y = 50, .width = 1920, .height = 1080 }, 3840, 2160).?;
    try std.testing.expectEqual(@as(i32, 100), inside.x);
    try std.testing.expectEqual(@as(u32, 1920), inside.width);

    // Вылезает за правый край — обрезается, но не выходит за выход.
    const cut = pickArea(.{ .x = 3000, .y = 2000, .width = 1920, .height = 1080 }, 3840, 2160).?;
    try std.testing.expect(cut.x + @as(i32, @intCast(cut.width)) <= 3840);
    try std.testing.expect(cut.y + @as(i32, @intCast(cut.height)) <= 2160);

    // Нечётные стороны кодировщик не любит — округляются вниз.
    const even = pickArea(.{ .x = 0, .y = 0, .width = 641, .height = 481 }, 3840, 2160).?;
    try std.testing.expectEqual(@as(u32, 640), even.width);
    try std.testing.expectEqual(@as(u32, 480), even.height);

    // Целиком за пределами выхода — области не осталось.
    try std.testing.expect(pickArea(.{ .x = 5000, .y = 0, .width = 100, .height = 100 }, 3840, 2160) == null);
    // Пустая область и выход без размера — тоже ничего.
    try std.testing.expect(pickArea(.{ .x = 0, .y = 0, .width = 0, .height = 100 }, 3840, 2160) == null);
    try std.testing.expect(pickArea(.{ .x = 0, .y = 0, .width = 100, .height = 100 }, 0, 0) == null);
    // Весь выход — законная область.
    const whole = pickArea(.{ .x = 0, .y = 0, .width = 3840, .height = 2160 }, 3840, 2160).?;
    try std.testing.expectEqual(@as(u32, 3840), whole.width);
}
