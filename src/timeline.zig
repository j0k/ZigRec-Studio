//! Модель проекта: дорожки и клипы с точками входа и выхода.
//!
//! Эпик #7, в текущую цель не входит.
const std = @import("std");

pub const TrackKind = enum { video, microphone, system_audio, voice_over };

pub const Clip = struct {
    start_ns: u64,
    end_ns: u64,

    pub fn durationNs(self: Clip) u64 {
        return self.end_ns -| self.start_ns;
    }
};

test "длительность клипа не уходит в минус" {
    try std.testing.expectEqual(@as(u64, 5), (Clip{ .start_ns = 10, .end_ns = 15 }).durationNs());
    try std.testing.expectEqual(@as(u64, 0), (Clip{ .start_ns = 20, .end_ns = 10 }).durationNs());
}
