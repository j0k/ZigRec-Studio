//! Кодирование H.264 и контейнер mp4 через Media Foundation.
//!
//! Задача #16. Пока заглушка с пресетами: они нужны раньше кодировщика,
//! потому что от них зависит и захват (частота кадров), и приёмка.
const std = @import("std");

/// Пресет качества. По умолчанию `text_ui`: скринкаст это почти статичная
/// картинка с мелким шрифтом, и чёткость букв важнее экономии битрейта.
pub const Preset = enum {
    /// Текст и интерфейс: высокое качество, редкие ключевые кадры.
    text_ui,
    /// Обычное видео: движение, средний битрейт.
    video,
    /// Максимум качества, размер не экономим.
    max,

    pub fn bitrateKbps(self: Preset, width: u32, height: u32, fps: u32) u32 {
        const pixels_per_sec = @as(u64, width) * @as(u64, height) * @as(u64, fps);
        const bits_per_pixel_milli: u64 = switch (self) {
            .text_ui => 60,
            .video => 100,
            .max => 200,
        };
        const kbps = pixels_per_sec * bits_per_pixel_milli / 1000 / 1000;
        return @intCast(@max(kbps, 500));
    }
};

pub const Settings = struct {
    preset: Preset = .text_ui,
    fps: u32 = 30,
    /// Длина группы кадров. Резка в редакторе идёт по ключевым кадрам,
    /// поэтому слишком длинный GOP потом мешает резать без перекодирования.
    gop: u32 = 60,
    /// moov в начало файла: без этого видео не играется в браузере до конца загрузки.
    faststart: bool = true,
};

test "пресеты упорядочены по битрейту" {
    const w: u32 = 1920;
    const h: u32 = 1080;
    const fps: u32 = 60;
    try std.testing.expect(Preset.text_ui.bitrateKbps(w, h, fps) < Preset.video.bitrateKbps(w, h, fps));
    try std.testing.expect(Preset.video.bitrateKbps(w, h, fps) < Preset.max.bitrateKbps(w, h, fps));
}

test "битрейт не опускается ниже разумного минимума" {
    try std.testing.expectEqual(@as(u32, 500), Preset.text_ui.bitrateKbps(320, 240, 5));
}

test "умолчания: пресет под текст, moov в начале" {
    const s = Settings{};
    try std.testing.expectEqual(Preset.text_ui, s.preset);
    try std.testing.expect(s.faststart);
}
