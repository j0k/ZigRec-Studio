//! Единственное место, где проект видит заголовки Windows.
//!
//! Заголовки берутся из mingw-w64, который везёт с собой сам Zig, поэтому
//! таблицы методов COM приходят из настоящего заголовка, а не пересчитываются
//! руками. Считать индексы вручную — верный способ получить падение в чужом
//! методе через полгода, когда никто уже не вспомнит, откуда взялось смещение.
//!
//! Отсюда требование к сборке: ABI `gnu` (см. `build.zig`) и `link_libc`.
const std = @import("std");
const builtin = @import("builtin");

pub const c = if (builtin.os.tag == .windows) @cImport({
    @cDefine("COBJMACROS", "1");
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cDefine("CINTERFACE", "1");
    @cInclude("windows.h");
    @cInclude("d3d11.h");
    @cInclude("dxgi1_2.h");
}) else struct {};

/// HRESULT как беззнаковое: так его печатают в документации и в отладчике.
pub fn hrCode(code: anytype) u32 {
    return @bitCast(@as(i32, @intCast(code)));
}

pub fn failed(code: anytype) bool {
    return @as(i32, @intCast(code)) < 0;
}

/// Коды, ради которых пишется отдельная ветка обработки.
pub const hr = struct {
    pub const ok: u32 = 0x0000_0000;
    /// Новый кадр не появился за таймаут. Не ошибка: на статичном экране это норма.
    pub const wait_timeout: u32 = 0x887A_0027;
    /// Дубликация отвалилась: смена разрешения, UAC-затемнение, смена пользователя,
    /// полноэкранное приложение. Лечится пересозданием дубликации, а не падением.
    pub const access_lost: u32 = 0x887A_0026;
    /// Захват запрещён: защищённый экран блокировки или уже занятый выход.
    pub const access_denied: u32 = 0x887A_002B;
    /// Дубликация этого выхода уже кем-то занята.
    pub const not_currently_available: u32 = 0x887A_0022;
    pub const unsupported: u32 = 0x887A_0004;
    pub const e_access_denied: u32 = 0x8007_0005;
    pub const e_invalidarg: u32 = 0x8007_0057;
};

/// Счётчик производительности в наносекундах: общий отсчёт для видео и звука.
/// Один источник времени на всё, иначе дорожки разъедутся ещё до кодировщика.
pub fn nowNs() u64 {
    if (builtin.os.tag != .windows) return @intCast(std.time.nanoTimestamp());
    var counter: c.LARGE_INTEGER = undefined;
    var freq: c.LARGE_INTEGER = undefined;
    _ = c.QueryPerformanceCounter(&counter);
    _ = c.QueryPerformanceFrequency(&freq);
    const ticks: u128 = @intCast(counter.QuadPart);
    const per_sec: u128 = @intCast(freq.QuadPart);
    return @intCast(ticks * std.time.ns_per_s / per_sec);
}

test "коды ошибок различаются" {
    try std.testing.expect(hr.wait_timeout != hr.access_lost);
    try std.testing.expect(failed(@as(i32, @bitCast(hr.access_lost))));
    try std.testing.expect(!failed(@as(i32, 0)));
}

test "время идёт вперёд" {
    const a = nowNs();
    const b = nowNs();
    try std.testing.expect(b >= a);
}
