//! Захват ОКНА через Windows Graphics Capture (WGC).
//!
//! Зачем третий путь, когда есть DXGI и GDI. Оба снимают РАБОЧИЙ СТОЛ, и окно
//! для них — прямоугольник экрана: всё, что лежит поверх него, попадает в
//! кадр. Стенд СИТА 24–26.09.2026 писал окно визуализатора Aurora, пока человек
//! работал за той же машиной: из четырёх дублей по пять минут в кадре
//! оказались Проводник, браузер и терминал; `HWND_TOPMOST` не держался — сама
//! программа снимает с себя этот флаг. Второе: окно на втором мониторе DXGI
//! не находил вовсе («источник не определился»), потому что дублирует один
//! выход, а окно лежит на другом.
//!
//! WGC отдаёт содержимое самого окна, как его сочинил композитор: перекрытое
//! окно снимается целиком, на любом мониторе. Цена — WinRT: заголовков в
//! mingw нет, поэтому интерфейсы ниже объявлены вручную по IDL из Windows SDK
//! (`windows.graphics.capture.idl`), порядок методов в таблицах — тот же, и
//! он закреплён тестом на смещения.
//!
//! Кадр — клиентская область окна (без заголовка и рамки), размер фиксируется
//! при открытии: кодировщик не умеет менять его на ходу. Окно, растянутое во
//! время записи, режется по прежнему размеру.
const std = @import("std");
const builtin = @import("builtin");
const win32 = @import("../win32.zig");
const c = win32.c;
const types = @import("capture_types.zig");

const Error = types.Error;
const Frame = types.Frame;
const Stats = types.Stats;
const Rect = types.Rect;

// ------------------------------------------------------------ WinRT вручную

const HRESULT = c.HRESULT;
const GUID = c.GUID;
const HSTRING = ?*anyopaque;

fn guid(d1: u32, d2: u16, d3: u16, d4: [8]u8) GUID {
    return .{ .Data1 = d1, .Data2 = d2, .Data3 = d3, .Data4 = d4 };
}

/// IID из `windows.graphics.capture.interop.h`.
const IID_IGraphicsCaptureItemInterop = guid(0x3628E81B, 0x3CAC, 0x4C60, .{ 0xB7, 0xF4, 0x23, 0xCE, 0x0E, 0x0C, 0x33, 0x56 });
/// Остальные IID — из `windows.graphics.capture.idl`.
const IID_IGraphicsCaptureItem = guid(0x79C3F95B, 0x31F7, 0x4EC2, .{ 0xA4, 0x64, 0x63, 0x2E, 0xF5, 0xD3, 0x07, 0x60 });
const IID_IDirect3D11CaptureFramePoolStatics2 = guid(0x589B103F, 0x6BBC, 0x5DF5, .{ 0xA9, 0x91, 0x02, 0xE2, 0x8B, 0x3B, 0x66, 0xD5 });
const IID_IGraphicsCaptureSession2 = guid(0x2C39AE40, 0x7D2E, 0x5044, .{ 0x80, 0x4E, 0x8B, 0x67, 0x99, 0xD4, 0xCF, 0x9E });
const IID_IGraphicsCaptureSession3 = guid(0xF2CDD966, 0x22AE, 0x5EA1, .{ 0x95, 0x96, 0x3A, 0x28, 0x93, 0x44, 0xC3, 0xBE });
/// IID из `windows.graphics.directx.direct3d11.interop.h`.
const IID_IDirect3DDxgiInterfaceAccess = guid(0xA9B3D012, 0x3DF2, 0x4EE3, .{ 0xB8, 0xD1, 0x86, 0x95, 0xF4, 0x57, 0xD3, 0xC1 });
/// IID из `windows.foundation.idl`.
const IID_IClosable = guid(0x30D5A829, 0x7FA4, 0x4026, .{ 0x83, 0xBB, 0xD7, 0x5B, 0xAE, 0x4E, 0xA9, 0x9E });

/// `DirectXPixelFormat.B8G8R8A8UIntNormalized` — тот же порядок байт, что у DXGI и GDI.
const pixel_format_bgra8: i32 = 87;
/// Буферов в пуле: два — один у нас, один у композитора.
const pool_buffers: i32 = 2;
/// `RO_INIT_MULTITHREADED`: пул свободнопоточный, квартира не нужна.
const ro_init_multithreaded: i32 = 1;
/// Опрос пула: WGC кладёт кадры в пул сам, ждать их приходится нам.
const poll_ms: u32 = 2;
/// `DWMWA_EXTENDED_FRAME_BOUNDS`: границы окна без невидимой тени — ровно то,
/// что отдаёт WGC.
const dwmwa_extended_frame_bounds: c.DWORD = 9;

const SizeInt32 = extern struct { width: i32, height: i32 };

const IUnknownVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
    Release: *const fn (*anyopaque) callconv(.winapi) u32,
};

/// Голова таблицы любого `IInspectable`: IUnknown плюс три метода WinRT.
const InspectableHead = extern struct {
    unk: IUnknownVtbl,
    GetIids: *const anyopaque,
    GetRuntimeClassName: *const anyopaque,
    GetTrustLevel: *const anyopaque,
};

const IGraphicsCaptureItemInteropVtbl = extern struct {
    unk: IUnknownVtbl,
    CreateForWindow: *const fn (*anyopaque, c.HWND, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    CreateForMonitor: *const anyopaque,
};

const IGraphicsCaptureItemVtbl = extern struct {
    head: InspectableHead,
    get_DisplayName: *const anyopaque,
    get_Size: *const fn (*anyopaque, *SizeInt32) callconv(.winapi) HRESULT,
    add_Closed: *const anyopaque,
    remove_Closed: *const anyopaque,
};

const IFramePoolStatics2Vtbl = extern struct {
    head: InspectableHead,
    CreateFreeThreaded: *const fn (*anyopaque, *anyopaque, i32, i32, SizeInt32, *?*anyopaque) callconv(.winapi) HRESULT,
};

const IFramePoolVtbl = extern struct {
    head: InspectableHead,
    Recreate: *const anyopaque,
    TryGetNextFrame: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    add_FrameArrived: *const anyopaque,
    remove_FrameArrived: *const anyopaque,
    CreateCaptureSession: *const fn (*anyopaque, *anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    get_DispatcherQueue: *const anyopaque,
};

const ISessionVtbl = extern struct {
    head: InspectableHead,
    StartCapture: *const fn (*anyopaque) callconv(.winapi) HRESULT,
};

const ISession2Vtbl = extern struct {
    head: InspectableHead,
    get_IsCursorCaptureEnabled: *const anyopaque,
    put_IsCursorCaptureEnabled: *const fn (*anyopaque, u8) callconv(.winapi) HRESULT,
};

const ISession3Vtbl = extern struct {
    head: InspectableHead,
    get_IsBorderRequired: *const anyopaque,
    put_IsBorderRequired: *const fn (*anyopaque, u8) callconv(.winapi) HRESULT,
};

const IFrameVtbl = extern struct {
    head: InspectableHead,
    get_Surface: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    get_SystemRelativeTime: *const anyopaque,
    get_ContentSize: *const fn (*anyopaque, *SizeInt32) callconv(.winapi) HRESULT,
};

const IDxgiAccessVtbl = extern struct {
    unk: IUnknownVtbl,
    GetInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
};

const IClosableVtbl = extern struct {
    head: InspectableHead,
    Close: *const fn (*anyopaque) callconv(.winapi) HRESULT,
};

/// Таблица методов объекта COM: первое слово объекта — указатель на неё.
fn vt(comptime T: type, obj: *anyopaque) *const T {
    const p: *const *const T = @ptrCast(@alignCast(obj));
    return p.*;
}

fn releaseObj(obj: ?*anyopaque) void {
    if (obj) |o| _ = vt(IUnknownVtbl, o).Release(o);
}

fn query(obj: *anyopaque, iid: *const GUID) ?*anyopaque {
    var out: ?*anyopaque = null;
    if (win32.failed(vt(IUnknownVtbl, obj).QueryInterface(obj, iid, &out))) return null;
    return out;
}

/// Объекты WinRT, держащие ресурсы (пул, сессия, кадр), закрываются явно:
/// одно `Release` оставляет буфер композитора занятым до сборки мусора WinRT.
fn closeAndRelease(obj: *anyopaque) void {
    if (query(obj, &IID_IClosable)) |cl| {
        _ = vt(IClosableVtbl, cl).Close(cl);
        releaseObj(cl);
    }
    releaseObj(obj);
}

extern "api-ms-win-core-winrt-l1-1-0" fn RoInitialize(init_type: i32) callconv(.winapi) HRESULT;
extern "api-ms-win-core-winrt-l1-1-0" fn RoGetActivationFactory(class_id: HSTRING, iid: *const GUID, factory: *?*anyopaque) callconv(.winapi) HRESULT;
extern "api-ms-win-core-winrt-string-l1-1-0" fn WindowsCreateString(src: [*]const u16, len: u32, out: *HSTRING) callconv(.winapi) HRESULT;
extern "api-ms-win-core-winrt-string-l1-1-0" fn WindowsDeleteString(s: HSTRING) callconv(.winapi) HRESULT;
extern "d3d11" fn CreateDirect3D11DeviceFromDXGIDevice(dxgi: *anyopaque, out: *?*anyopaque) callconv(.winapi) HRESULT;

fn activationFactory(comptime class: []const u8, iid: *const GUID) Error!*anyopaque {
    const wide = std.unicode.utf8ToUtf16LeStringLiteral(class);
    var name: HSTRING = null;
    if (win32.failed(WindowsCreateString(wide, @intCast(wide.len), &name))) return Error.Failed;
    defer _ = WindowsDeleteString(name);
    var out: ?*anyopaque = null;
    // Нет класса — нет WGC: Windows старше 10 1903 или урезанная сборка.
    if (win32.failed(RoGetActivationFactory(name, iid, &out)) or out == null) return Error.Unsupported;
    return out.?;
}

// ------------------------------------------------------------ геометрия

/// Где клиентская область окна внутри кадра WGC.
///
/// WGC снимает окно целиком — с заголовком и рамкой, но без невидимой тени,
/// то есть ровно по `DWMWA_EXTENDED_FRAME_BOUNDS`. Клиентская область лежит
/// внутри со сдвигом, который и нужен, чтобы отрезать заголовок.
pub fn clientInFrame(frame_bounds: Rect, client: Rect) Rect {
    const r = Rect{
        .x = client.x - frame_bounds.x,
        .y = client.y - frame_bounds.y,
        .width = client.width,
        .height = client.height,
    };
    return r.clampTo(frame_bounds.width, frame_bounds.height).evenSized();
}

const Geometry = struct { frame: Rect, client: Rect };

fn windowGeometry(hwnd: c.HWND) Error!Geometry {
    if (c.IsIconic(hwnd) != 0) return Error.Failed;
    var fr: c.RECT = undefined;
    if (win32.failed(c.DwmGetWindowAttribute(hwnd, dwmwa_extended_frame_bounds, &fr, @sizeOf(c.RECT)))) {
        if (c.GetWindowRect(hwnd, &fr) == 0) return Error.Failed;
    }
    var cr: c.RECT = undefined;
    if (c.GetClientRect(hwnd, &cr) == 0) return Error.Failed;
    var origin = c.POINT{ .x = 0, .y = 0 };
    _ = c.ClientToScreen(hwnd, &origin);
    return .{
        .frame = .{
            .x = fr.left,
            .y = fr.top,
            .width = @intCast(@max(fr.right - fr.left, 0)),
            .height = @intCast(@max(fr.bottom - fr.top, 0)),
        },
        .client = .{
            .x = origin.x,
            .y = origin.y,
            .width = @intCast(@max(cr.right, 0)),
            .height = @intCast(@max(cr.bottom, 0)),
        },
    };
}

// ------------------------------------------------------------ захват

pub const WindowCapture = struct {
    hwnd: c.HWND,
    device: *c.ID3D11Device = undefined,
    context: *c.ID3D11DeviceContext = undefined,
    item: *anyopaque = undefined,
    pool: *anyopaque = undefined,
    session: *anyopaque = undefined,
    staging: ?*c.ID3D11Texture2D = null,
    mapped: bool = false,
    /// Клиентская область в координатах кадра WGC; её и отдаём.
    crop: Rect = .{ .width = 0, .height = 0 },
    /// Клиентская область на экране при открытии — для курсора и слоя событий.
    screen_origin: Rect = .{ .width = 0, .height = 0 },
    stats: Stats = .{},

    pub fn init(hwnd: c.HWND) Error!WindowCapture {
        if (builtin.os.tag != .windows) return Error.Unsupported;
        _ = c.SetProcessDPIAware();
        // S_FALSE и RPC_E_CHANGED_MODE — поток уже в COM: для свободнопоточного
        // пула это не помеха.
        _ = RoInitialize(ro_init_multithreaded);

        var self = WindowCapture{ .hwnd = hwnd };
        const geo = try windowGeometry(hwnd);
        self.crop = clientInFrame(geo.frame, geo.client);
        self.screen_origin = geo.client;
        if (self.crop.isEmpty()) return Error.Failed;

        try self.createDevice();
        errdefer self.releaseDevice();

        const interop = try activationFactory("Windows.Graphics.Capture.GraphicsCaptureItem", &IID_IGraphicsCaptureItemInterop);
        defer releaseObj(interop);
        var item: ?*anyopaque = null;
        if (win32.failed(vt(IGraphicsCaptureItemInteropVtbl, interop).CreateForWindow(interop, hwnd, &IID_IGraphicsCaptureItem, &item)) or item == null)
            return Error.AccessDenied;
        self.item = item.?;
        errdefer releaseObj(self.item);

        var size: SizeInt32 = undefined;
        if (win32.failed(vt(IGraphicsCaptureItemVtbl, self.item).get_Size(self.item, &size))) return Error.Failed;

        // Устройство D3D11 в обёртке WinRT: пул создаёт буферы на нём же,
        // и копия в staging идёт без перехода между адаптерами.
        var dxgi: ?*anyopaque = null;
        if (win32.failed(self.device.lpVtbl.*.QueryInterface.?(@ptrCast(self.device), &c.IID_IDXGIDevice, @ptrCast(&dxgi))) or dxgi == null)
            return Error.NoDevice;
        defer releaseObj(dxgi);
        var rt_device: ?*anyopaque = null;
        if (win32.failed(CreateDirect3D11DeviceFromDXGIDevice(dxgi.?, &rt_device)) or rt_device == null) return Error.NoDevice;
        defer releaseObj(rt_device);

        const statics = try activationFactory("Windows.Graphics.Capture.Direct3D11CaptureFramePool", &IID_IDirect3D11CaptureFramePoolStatics2);
        defer releaseObj(statics);
        var pool: ?*anyopaque = null;
        if (win32.failed(vt(IFramePoolStatics2Vtbl, statics).CreateFreeThreaded(statics, rt_device.?, pixel_format_bgra8, pool_buffers, size, &pool)) or pool == null)
            return Error.Failed;
        self.pool = pool.?;
        errdefer closeAndRelease(self.pool);

        var session: ?*anyopaque = null;
        if (win32.failed(vt(IFramePoolVtbl, self.pool).CreateCaptureSession(self.pool, self.item, &session)) or session == null)
            return Error.Failed;
        self.session = session.?;
        errdefer closeAndRelease(self.session);

        // Курсор рисуем сами (слой событий, подсветка), жёлтую рамку не просим.
        // Обоих свойств нет на старых сборках Windows — нет, и не надо.
        if (query(self.session, &IID_IGraphicsCaptureSession2)) |s2| {
            _ = vt(ISession2Vtbl, s2).put_IsCursorCaptureEnabled(s2, 0);
            releaseObj(s2);
        }
        if (query(self.session, &IID_IGraphicsCaptureSession3)) |s3| {
            _ = vt(ISession3Vtbl, s3).put_IsBorderRequired(s3, 0);
            releaseObj(s3);
        }
        if (win32.failed(vt(ISessionVtbl, self.session).StartCapture(self.session))) return Error.AccessDenied;
        return self;
    }

    fn createDevice(self: *WindowCapture) Error!void {
        var device: ?*c.ID3D11Device = null;
        var context: ?*c.ID3D11DeviceContext = null;
        var level: c.D3D_FEATURE_LEVEL = 0;
        const hres = c.D3D11CreateDevice(
            null,
            c.D3D_DRIVER_TYPE_HARDWARE,
            null,
            c.D3D11_CREATE_DEVICE_BGRA_SUPPORT,
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

    fn releaseDevice(self: *WindowCapture) void {
        _ = self.context.lpVtbl.*.Release.?(@ptrCast(self.context));
        _ = self.device.lpVtbl.*.Release.?(@ptrCast(self.device));
    }

    pub fn deinit(self: *WindowCapture) void {
        self.release();
        if (self.staging) |t| _ = t.lpVtbl.*.Release.?(@ptrCast(t));
        self.staging = null;
        closeAndRelease(self.session);
        closeAndRelease(self.pool);
        releaseObj(self.item);
        self.releaseDevice();
    }

    /// Размер кадра — клиентская область; начало — где она на экране
    /// (по нему дорисовывается курсор и пишется слой событий).
    pub fn frameSize(self: WindowCapture) Rect {
        return .{
            .x = self.screen_origin.x,
            .y = self.screen_origin.y,
            .width = self.crop.width,
            .height = self.crop.height,
        };
    }

    pub fn release(self: *WindowCapture) void {
        if (self.mapped) {
            if (self.staging) |t| self.context.lpVtbl.*.Unmap.?(self.context, @ptrCast(t), 0);
            self.mapped = false;
        }
    }

    fn ensureStaging(self: *WindowCapture) Error!void {
        if (self.staging != null) return;
        var desc = std.mem.zeroes(c.D3D11_TEXTURE2D_DESC);
        desc.Width = self.crop.width;
        desc.Height = self.crop.height;
        desc.MipLevels = 1;
        desc.ArraySize = 1;
        desc.Format = c.DXGI_FORMAT_B8G8R8A8_UNORM;
        desc.SampleDesc.Count = 1;
        desc.Usage = c.D3D11_USAGE_STAGING;
        desc.CPUAccessFlags = c.D3D11_CPU_ACCESS_READ;
        var tex: ?*c.ID3D11Texture2D = null;
        if (win32.failed(self.device.lpVtbl.*.CreateTexture2D.?(self.device, &desc, null, &tex))) return Error.OutOfMemory;
        self.staging = tex.?;
    }

    /// Следующий кадр или `null`, если за `timeout_ms` окно не перерисовалось.
    pub fn next(self: *WindowCapture, timeout_ms: u32) Error!?Frame {
        if (builtin.os.tag != .windows) return Error.Unsupported;
        self.release();
        const deadline = win32.nowNs() + @as(u64, timeout_ms) * std.time.ns_per_ms;
        var frame: ?*anyopaque = null;
        while (true) {
            if (win32.failed(vt(IFramePoolVtbl, self.pool).TryGetNextFrame(self.pool, &frame))) return Error.Lost;
            if (frame != null) break;
            // Окно закрыли — кадров больше не будет, ждать нечего.
            if (c.IsWindow(self.hwnd) == 0) return Error.Lost;
            if (win32.nowNs() >= deadline) {
                self.stats.idle += 1;
                return null;
            }
            c.Sleep(poll_ms);
        }
        defer closeAndRelease(frame.?);

        // Кадр пула бывает меньше заказанного (окно ужали) — копируем то,
        // что есть; остальное остаётся от прошлого кадра.
        var content: SizeInt32 = .{ .width = 0, .height = 0 };
        _ = vt(IFrameVtbl, frame.?).get_ContentSize(frame.?, &content);

        var surface: ?*anyopaque = null;
        if (win32.failed(vt(IFrameVtbl, frame.?).get_Surface(frame.?, &surface)) or surface == null) return Error.Failed;
        defer releaseObj(surface);
        const access = query(surface.?, &IID_IDirect3DDxgiInterfaceAccess) orelse return Error.Failed;
        defer releaseObj(access);
        var tex_raw: ?*anyopaque = null;
        if (win32.failed(vt(IDxgiAccessVtbl, access).GetInterface(access, &c.IID_ID3D11Texture2D, &tex_raw)) or tex_raw == null)
            return Error.Failed;
        const tex: *c.ID3D11Texture2D = @ptrCast(@alignCast(tex_raw.?));
        defer _ = tex.lpVtbl.*.Release.?(@ptrCast(tex));

        try self.ensureStaging();
        const box = copyBox(self.crop, content);
        if (box.right > box.left and box.bottom > box.top) {
            self.context.lpVtbl.*.CopySubresourceRegion.?(self.context, @ptrCast(self.staging.?), 0, 0, 0, 0, @ptrCast(tex), 0, &box);
        }

        var mapped: c.D3D11_MAPPED_SUBRESOURCE = undefined;
        if (win32.failed(self.context.lpVtbl.*.Map.?(self.context, @ptrCast(self.staging.?), 0, c.D3D11_MAP_READ, 0, &mapped)))
            return Error.Failed;
        self.mapped = true;
        const stride: u32 = mapped.RowPitch;
        const ptr: [*]const u8 = @ptrCast(mapped.pData.?);
        self.stats.frames += 1;
        return Frame{
            .pixels = ptr[0 .. @as(usize, stride) * self.crop.height],
            .width = self.crop.width,
            .height = self.crop.height,
            .stride = stride,
            .timestamp_ns = win32.nowNs(),
            .accumulated = 1,
        };
    }
};

/// Что копировать из кадра пула: клиентскую область, но не дальше того, что
/// в кадре действительно нарисовано (`ContentSize`).
fn copyBox(crop: Rect, content: SizeInt32) c.D3D11_BOX {
    const left: u32 = @intCast(@max(crop.x, 0));
    const top: u32 = @intCast(@max(crop.y, 0));
    const want_right: i64 = @as(i64, crop.x) + crop.width;
    const want_bottom: i64 = @as(i64, crop.y) + crop.height;
    const right: u32 = @intCast(@max(@min(want_right, content.width), 0));
    const bottom: u32 = @intCast(@max(@min(want_bottom, content.height), 0));
    return .{ .left = left, .top = top, .front = 0, .right = right, .bottom = bottom, .back = 1 };
}

// ---------------------------------------------------------------- тесты

test "клиентская область: сдвиг от рамки, заголовок отрезан" {
    // Окно Aurora со стенда: 1566x1182 в (3851,0), клиентская часть 1542x1123 с (3863,47).
    const r = clientInFrame(
        .{ .x = 3851, .y = 0, .width = 1566, .height = 1182 },
        .{ .x = 3863, .y = 47, .width = 1542, .height = 1123 },
    );
    try std.testing.expectEqual(@as(i32, 12), r.x);
    try std.testing.expectEqual(@as(i32, 47), r.y);
    try std.testing.expectEqual(@as(u32, 1542), r.width);
    try std.testing.expectEqual(@as(u32, 1122), r.height);
}

test "клиентская область не вылезает за кадр окна" {
    const r = clientInFrame(
        .{ .x = 0, .y = 0, .width = 100, .height = 100 },
        .{ .x = 10, .y = 30, .width = 100, .height = 100 },
    );
    try std.testing.expectEqual(@as(u32, 90), r.width);
    try std.testing.expectEqual(@as(u32, 70), r.height);
}

test "копия не берёт больше, чем нарисовано в кадре" {
    const full = copyBox(.{ .x = 12, .y = 47, .width = 1542, .height = 1122 }, .{ .width = 1566, .height = 1182 });
    try std.testing.expectEqual(@as(u32, 12), full.left);
    try std.testing.expectEqual(@as(u32, 1554), full.right);
    try std.testing.expectEqual(@as(u32, 1169), full.bottom);
    // Окно ужали: кадр пула 800x600 — копируется только то, что в нём есть.
    const small = copyBox(.{ .x = 12, .y = 47, .width = 1542, .height = 1122 }, .{ .width = 800, .height = 600 });
    try std.testing.expectEqual(@as(u32, 800), small.right);
    try std.testing.expectEqual(@as(u32, 600), small.bottom);
    // Пустой кадр — пустая копия, а не выход за границы.
    const none = copyBox(.{ .x = 12, .y = 47, .width = 100, .height = 100 }, .{ .width = 0, .height = 0 });
    try std.testing.expect(none.right <= none.left);
}

test "таблицы методов: порядок по IDL" {
    // Смещение метода — номер слота в таблице. Ошибка здесь — вызов чужого
    // метода без всякой диагностики, поэтому номера проверяются явно:
    // IUnknown занимает 3 слота, IInspectable — 6.
    const slot = @sizeOf(usize);
    try std.testing.expectEqual(@as(usize, 3 * slot), @offsetOf(IGraphicsCaptureItemInteropVtbl, "CreateForWindow"));
    try std.testing.expectEqual(@as(usize, 7 * slot), @offsetOf(IGraphicsCaptureItemVtbl, "get_Size"));
    try std.testing.expectEqual(@as(usize, 6 * slot), @offsetOf(IFramePoolStatics2Vtbl, "CreateFreeThreaded"));
    try std.testing.expectEqual(@as(usize, 7 * slot), @offsetOf(IFramePoolVtbl, "TryGetNextFrame"));
    try std.testing.expectEqual(@as(usize, 10 * slot), @offsetOf(IFramePoolVtbl, "CreateCaptureSession"));
    try std.testing.expectEqual(@as(usize, 6 * slot), @offsetOf(ISessionVtbl, "StartCapture"));
    try std.testing.expectEqual(@as(usize, 7 * slot), @offsetOf(ISession2Vtbl, "put_IsCursorCaptureEnabled"));
    try std.testing.expectEqual(@as(usize, 7 * slot), @offsetOf(ISession3Vtbl, "put_IsBorderRequired"));
    try std.testing.expectEqual(@as(usize, 6 * slot), @offsetOf(IFrameVtbl, "get_Surface"));
    try std.testing.expectEqual(@as(usize, 8 * slot), @offsetOf(IFrameVtbl, "get_ContentSize"));
    try std.testing.expectEqual(@as(usize, 3 * slot), @offsetOf(IDxgiAccessVtbl, "GetInterface"));
    try std.testing.expectEqual(@as(usize, 6 * slot), @offsetOf(IClosableVtbl, "Close"));
}
