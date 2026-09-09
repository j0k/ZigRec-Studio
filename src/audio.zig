//! Звук: микрофон и системный звук через WASAPI.
//!
//! Эпик #6, в текущую цель не входит. Слой объявлен, чтобы таймлайн знал
//! про дорожки с самого начала и их не пришлось вшивать задним числом.
const std = @import("std");

pub const Source = enum { microphone, system_loopback };

pub const Format = struct {
    sample_rate: u32 = 48_000,
    channels: u8 = 2,
};

test "умолчание звука: 48 кГц стерео" {
    const f = Format{};
    try std.testing.expectEqual(@as(u32, 48_000), f.sample_rate);
    try std.testing.expectEqual(@as(u8, 2), f.channels);
}
