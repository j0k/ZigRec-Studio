//! Ядро ZigRecStudio: всё, что не про запуск процесса.
//!
//! Слои снизу вверх: `capture` даёт кадры, `encode` пишет их в mp4,
//! `audio` даёт звук, `timeline` и `edit` режут готовое, `ui` показывает.
//! Модуль импортируется как `@import("zigrec")`.
const std = @import("std");

pub const version = @import("version.zig");
pub const capture = @import("capture.zig");
pub const encode = @import("encode.zig");
pub const audio = @import("audio.zig");
pub const timeline = @import("timeline.zig");
pub const edit = @import("edit.zig");
pub const ui = @import("ui.zig");
pub const testbench = @import("testbench.zig");

test {
    // Тесты всех модулей ядра одним `zig build test`.
    std.testing.refAllDecls(@This());
}
