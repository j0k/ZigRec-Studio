//! Захват экрана через DXGI Desktop Duplication.
//!
//! Задача #13. Пока заглушка: слой объявлен, чтобы верхние модули писались
//! против интерфейса, а не против будущих COM-вызовов.
const std = @import("std");

/// Прямоугольник в пикселях экрана. Ширина и высота приводятся к чётным:
/// yuv420p не умеет нечётные размеры, а обрезать лучше здесь, чем в кодировщике.
pub const Rect = struct {
    x: i32 = 0,
    y: i32 = 0,
    width: u32,
    height: u32,

    pub fn evenSized(self: Rect) Rect {
        return .{
            .x = self.x,
            .y = self.y,
            .width = self.width & ~@as(u32, 1),
            .height = self.height & ~@as(u32, 1),
        };
    }
};

/// Кадр как он приходит от DXGI: BGRA8, строка выровнена по `stride`.
pub const Frame = struct {
    pixels: []const u8,
    width: u32,
    height: u32,
    stride: u32,
    /// Метка времени от QPC в наносекундах: общий счёт для видео и звука.
    timestamp_ns: u64,
};

test "нечётные размеры срезаются до чётных" {
    const r = (Rect{ .width = 1749, .height = 1009 }).evenSized();
    try std.testing.expectEqual(@as(u32, 1748), r.width);
    try std.testing.expectEqual(@as(u32, 1008), r.height);
}

test "чётные размеры не трогаются" {
    const r = (Rect{ .x = 10, .y = 20, .width = 1920, .height = 1080 }).evenSized();
    try std.testing.expectEqual(@as(u32, 1920), r.width);
    try std.testing.expectEqual(@as(u32, 1080), r.height);
    try std.testing.expectEqual(@as(i32, 10), r.x);
}
