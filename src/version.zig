//! Р вЂўР Т‘Р С‘Р Р…РЎРѓРЎвЂљР Р†Р ВµР Р…Р Р…РЎвЂ№Р в„– Р С‘РЎРѓРЎвЂљР С•РЎвЂЎР Р…Р С‘Р С” Р Р†Р ВµРЎР‚РЎРѓР С‘Р С‘ Р С—РЎР‚Р С•Р ВµР С”РЎвЂљР В°.
//!
//! Р В§Р ВµРЎвЂљРЎвЂ№РЎР‚Р Вµ РЎРѓР ВµР С–Р СР ВµР Р…РЎвЂљР В° `A.B.C.D`, Р С—РЎР‚Р С‘Р Р†РЎРЏР В·Р В°Р Р…Р Р…РЎвЂ№Р Вµ Р С” РЎС“РЎР‚Р С•Р Р†Р Р…РЎРЏР С Р С”Р В°Р Р…Р В±Р В°Р Р…Р В°:
//!
//!     L0 (Р СР С‘РЎРѓРЎРѓР С‘РЎРЏ)    -> A   РЎР‚Р ВµР В»Р С‘Р В·Р Р…Р В°РЎРЏ Р Р†Р ВµРЎвЂ¦Р В°: A+1, Р С•РЎРѓРЎвЂљР В°Р В»РЎРЉР Р…Р С•Р Вµ Р Р† Р Р…Р С•Р В»РЎРЉ
//!     L1 (РЎРЊР С—Р С‘Р С”)      -> B   +0.1.0.0
//!     L2 (Р В·Р В°Р Т‘Р В°РЎвЂЎР В°)    -> C   +0.0.1.0
//!     L3 (Р С—Р С•Р Т‘Р В·Р В°Р Т‘Р В°РЎвЂЎР В°) -> D   +0.0.0.1
//!
//! Р С’Р Т‘Р Т‘Р С‘РЎвЂљР С‘Р Р†Р Р…Р С•: Р В·Р В°Р С”РЎР‚РЎвЂ№РЎвЂљР С‘Р Вµ РЎвЂљР С‘Р С”Р ВµРЎвЂљР В° Р С—Р С•Р Т‘Р Р…Р С‘Р СР В°Р ВµРЎвЂљ РЎвЂљР С•Р В»РЎРЉР С”Р С• РЎРѓР ВµР С–Р СР ВµР Р…РЎвЂљ РЎРѓР Р†Р С•Р ВµР С–Р С• РЎС“РЎР‚Р С•Р Р†Р Р…РЎРЏ, Р СР В»Р В°Р Т‘РЎв‚¬Р С‘Р Вµ
//! РЎРѓР ВµР С–Р СР ВµР Р…РЎвЂљРЎвЂ№ Р СњР вЂў РЎРѓР В±РЎР‚Р В°РЎРѓРЎвЂ№Р Р†Р В°РЎР‹РЎвЂљРЎРѓРЎРЏ (`0.1.3.0` --L1--> `0.2.3.0`).
//!
//! Р ВРЎРѓР С”Р В»РЎР‹РЎвЂЎР ВµР Р…Р С‘Р Вµ РІР‚вЂќ L0. Р вЂ”Р В°Р С”РЎР‚РЎвЂ№РЎвЂљР С‘Р Вµ Р СР С‘РЎРѓРЎРѓР С‘Р С‘ РЎРЊРЎвЂљР С• РЎР‚Р ВµР В»Р С‘Р В·, Р С‘ Р Р†Р ВµРЎР‚РЎРѓР С‘РЎРЏ РЎРѓРЎвЂљР В°Р Р…Р С•Р Р†Р С‘РЎвЂљРЎРѓРЎРЏ РЎвЂЎР С‘РЎРѓРЎвЂљРЎвЂ№Р С
//! РЎР‚Р ВµР В»Р С‘Р В·Р Р…РЎвЂ№Р С Р Р…Р С•Р СР ВµРЎР‚Р С•Р С: Р С—РЎС“РЎвЂљРЎРЉ `0.7.21.0` --L0--> `1.0.0.0`.
//!
//! Р вЂР В°Р СР С—Р В°Р ВµРЎвЂљРЎРѓРЎРЏ Р Р† РЎвЂљР С•Р С Р В¶Р Вµ Р С”Р С•Р СР СР С‘РЎвЂљР Вµ, РЎвЂЎРЎвЂљР С• Р С‘ РЎРѓР В°Р С Р С”Р С•Р Т‘. `VERSION_DATE` Р Т‘Р Р†Р С‘Р С–Р В°Р ВµРЎвЂљРЎРѓРЎРЏ Р Р†Р СР ВµРЎРѓРЎвЂљР Вµ
//! РЎРѓ `VERSION`. Р СџР С•Р Т‘РЎР‚Р С•Р В±Р Р…Р С•РЎРѓРЎвЂљР С‘: Р Р†Р С‘Р С”Р С‘ Versioning.
const std = @import("std");

pub const VERSION = "0.1.12.0";
/// Р вЂќР В°РЎвЂљР В° Р Р†РЎвЂ№Р С—РЎС“РЎРѓР С”Р В° VERSION (ISO). Р вЂќР Р†Р С‘Р С–Р В°РЎвЂљРЎРЉ Р Р†Р СР ВµРЎРѓРЎвЂљР Вµ РЎРѓ VERSION.
pub const VERSION_DATE = "2026-09-10";

pub const Level = enum {
    l0,
    l1,
    l2,
    l3,

    pub fn parse(s: []const u8) ?Level {
        inline for (@typeInfo(Level).@"enum".fields) |f| {
            if (std.ascii.eqlIgnoreCase(s, f.name)) return @field(Level, f.name);
        }
        return null;
    }
};

pub const ParseError = error{
    /// Р РЋР ВµР С–Р СР ВµР Р…РЎвЂљР С•Р Р† Р Р…Р Вµ РЎвЂЎР ВµРЎвЂљРЎвЂ№РЎР‚Р Вµ.
    WrongSegmentCount,
    /// Р РЋР ВµР С–Р СР ВµР Р…РЎвЂљ Р С—РЎС“РЎРѓРЎвЂљ Р С‘Р В»Р С‘ РЎРѓР С•Р Т‘Р ВµРЎР‚Р В¶Р С‘РЎвЂљ Р Р…Р Вµ РЎвЂљР С•Р В»РЎРЉР С”Р С• РЎвЂ Р С‘РЎвЂћРЎР‚РЎвЂ№.
    BadSegment,
    /// Р РЋР ВµР С–Р СР ВµР Р…РЎвЂљ Р Р…Р Вµ Р Р†Р В»Р ВµР В·Р В°Р ВµРЎвЂљ Р Р† u16.
    SegmentTooBig,
};

/// Р В Р В°Р В·Р С•Р В±РЎР‚Р В°Р Р…Р Р…Р В°РЎРЏ Р Р†Р ВµРЎР‚РЎРѓР С‘РЎРЏ. Р СџР ВµРЎвЂЎР В°РЎвЂљР В°Р ВµРЎвЂљРЎРѓРЎРЏ РЎвЂЎР ВµРЎР‚Р ВµР В· `std.fmt` Р С”Р В°Р С” `A.B.C.D`.
pub const Version = struct {
    a: u16 = 0,
    b: u16 = 0,
    c: u16 = 0,
    d: u16 = 0,

    /// Р СљР В°Р С”РЎРѓР С‘Р СР В°Р В»РЎРЉР Р…Р В°РЎРЏ Р Т‘Р В»Р С‘Р Р…Р В° РЎвЂљР ВµР С”РЎРѓРЎвЂљР С•Р Р†Р С•Р С–Р С• Р С—РЎР‚Р ВµР Т‘РЎРѓРЎвЂљР В°Р Р†Р В»Р ВµР Р…Р С‘РЎРЏ: 4 РЎвЂЎР С‘РЎРѓР В»Р В° Р С—Р С• 5 РЎвЂ Р С‘РЎвЂћРЎР‚ Р С‘ 3 РЎвЂљР С•РЎвЂЎР С”Р С‘.
    pub const max_len = 4 * 5 + 3;

    pub fn parse(text: []const u8) ParseError!Version {
        var it = std.mem.splitScalar(u8, text, '.');
        var seg: [4]u16 = .{ 0, 0, 0, 0 };
        var n: usize = 0;
        while (it.next()) |part| {
            if (n == 4) return ParseError.WrongSegmentCount;
            if (part.len == 0) return ParseError.BadSegment;
            for (part) |ch| {
                if (!std.ascii.isDigit(ch)) return ParseError.BadSegment;
            }
            seg[n] = std.fmt.parseInt(u16, part, 10) catch return ParseError.SegmentTooBig;
            n += 1;
        }
        if (n != 4) return ParseError.WrongSegmentCount;
        return .{ .a = seg[0], .b = seg[1], .c = seg[2], .d = seg[3] };
    }

    /// Р вЂ™Р ВµРЎР‚РЎРѓР С‘РЎРЏ Р С—Р С•РЎРѓР В»Р Вµ Р В·Р В°Р С”РЎР‚РЎвЂ№РЎвЂљР С‘РЎРЏ РЎвЂљР С‘Р С”Р ВµРЎвЂљР В° РЎС“РЎР‚Р С•Р Р†Р Р…РЎРЏ `level`.
    ///
    /// L0 Р С•Р В±Р Р…РЎС“Р В»РЎРЏР ВµРЎвЂљ Р СР В»Р В°Р Т‘РЎв‚¬Р С‘Р Вµ РЎРѓР ВµР С–Р СР ВµР Р…РЎвЂљРЎвЂ№, Р С—Р С•РЎвЂљР С•Р СРЎС“ РЎвЂЎРЎвЂљР С• РЎРЊРЎвЂљР С• РЎР‚Р ВµР В»Р С‘Р В·, Р В° Р Р…Р Вµ Р ВµРЎвЂ°РЎвЂ Р С•Р Т‘Р С‘Р Р… РЎв‚¬Р В°Р С–:
    /// Р Р…Р С•Р СР ВµРЎР‚ РЎР‚Р ВµР В»Р С‘Р В·Р В° Р Т‘Р С•Р В»Р В¶Р ВµР Р… РЎвЂЎР С‘РЎвЂљР В°РЎвЂљРЎРЉРЎРѓРЎРЏ Р С”Р В°Р С” Р Р…Р С•Р СР ВµРЎР‚ РЎР‚Р ВµР В»Р С‘Р В·Р В°, Р В° Р Р…Р Вµ РЎвЂљР В°РЎвЂ°Р С‘РЎвЂљРЎРЉ Р В·Р В° РЎРѓР С•Р В±Р С•Р в„–
    /// РЎРѓРЎвЂЎРЎвЂРЎвЂљРЎвЂЎР С‘Р С” Р В·Р В°Р Т‘Р В°РЎвЂЎ Р С—РЎР‚Р ВµР Т‘РЎвЂ№Р Т‘РЎС“РЎвЂ°Р ВµР С–Р С• Р С—РЎС“РЎвЂљР С‘.
    pub fn bump(self: Version, level: Level) Version {
        return switch (level) {
            .l0 => .{ .a = self.a + 1 },
            .l1 => .{ .a = self.a, .b = self.b + 1, .c = self.c, .d = self.d },
            .l2 => .{ .a = self.a, .b = self.b, .c = self.c + 1, .d = self.d },
            .l3 => .{ .a = self.a, .b = self.b, .c = self.c, .d = self.d + 1 },
        };
    }

    /// Р СћР ВµР С”РЎРѓРЎвЂљ Р Р†Р ВµРЎР‚РЎРѓР С‘Р С‘ Р Р† Р С—Р ВµРЎР‚Р ВµР Т‘Р В°Р Р…Р Р…РЎвЂ№Р в„– Р В±РЎС“РЎвЂћР ВµРЎР‚ (Р Р…РЎС“Р В¶Р ВµР Р… Р СР С‘Р Р…Р С‘Р СРЎС“Р С `max_len` Р В±Р В°Р в„–РЎвЂљ).
    pub fn write(self: Version, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "{d}.{d}.{d}.{d}", .{ self.a, self.b, self.c, self.d }) catch unreachable;
    }

    pub fn eql(self: Version, other: Version) bool {
        return self.a == other.a and self.b == other.b and self.c == other.c and self.d == other.d;
    }
};

/// Р В Р В°Р В·Р С•Р В±РЎР‚Р В°Р Р…Р Р…Р В°РЎРЏ Р Р†Р ВµРЎР‚РЎРѓР С‘РЎРЏ Р С—РЎР‚Р С•Р ВµР С”РЎвЂљР В°. Р С›РЎв‚¬Р С‘Р В±Р С‘РЎвЂљРЎРЉРЎРѓРЎРЏ Р Р…Р ВµР В»РЎРЉР В·РЎРЏ: РЎРѓРЎвЂљРЎР‚Р С•Р С”Р В° Р С—РЎР‚Р С•Р Р†Р ВµРЎР‚РЎРЏР ВµРЎвЂљРЎРѓРЎРЏ РЎвЂљР ВµРЎРѓРЎвЂљР С•Р С.
pub fn current() Version {
    return Version.parse(VERSION) catch unreachable;
}

// ---------------------------------------------------------------- РЎвЂљР ВµРЎРѓРЎвЂљРЎвЂ№

test "Р Р†Р ВµРЎР‚РЎРѓР С‘РЎРЏ Р С—РЎР‚Р С•Р ВµР С”РЎвЂљР В° РЎР‚Р В°Р В·Р В±Р С‘РЎР‚Р В°Р ВµРЎвЂљРЎРѓРЎРЏ Р С‘ Р С—Р ВµРЎвЂЎР В°РЎвЂљР В°Р ВµРЎвЂљРЎРѓРЎРЏ Р С•Р В±РЎР‚Р В°РЎвЂљР Р…Р С• РЎвЂљР ВµР С Р В¶Р Вµ РЎвЂљР ВµР С”РЎРѓРЎвЂљР С•Р С" {
    const v = try Version.parse(VERSION);
    var buf: [Version.max_len]u8 = undefined;
    try std.testing.expectEqualStrings(VERSION, v.write(&buf));
}

test "Р Т‘Р В°РЎвЂљР В° Р Р†Р ВµРЎР‚РЎРѓР С‘Р С‘ Р Р†РЎвЂ№Р С–Р В»РЎРЏР Т‘Р С‘РЎвЂљ Р С”Р В°Р С” ISO-Р Т‘Р В°РЎвЂљР В°" {
    try std.testing.expectEqual(@as(usize, 10), VERSION_DATE.len);
    try std.testing.expectEqual(@as(u8, '-'), VERSION_DATE[4]);
    try std.testing.expectEqual(@as(u8, '-'), VERSION_DATE[7]);
    for (VERSION_DATE, 0..) |ch, i| {
        if (i == 4 or i == 7) continue;
        try std.testing.expect(std.ascii.isDigit(ch));
    }
}

test "Р В±Р В°Р СР С— Р С—Р С•Р Т‘Р Р…Р С‘Р СР В°Р ВµРЎвЂљ РЎвЂљР С•Р В»РЎРЉР С”Р С• РЎРѓР Р†Р С•Р в„– РЎРѓР ВµР С–Р СР ВµР Р…РЎвЂљ, Р СР В»Р В°Р Т‘РЎв‚¬Р С‘Р Вµ Р Р…Р Вµ РЎРѓР В±РЎР‚Р В°РЎРѓРЎвЂ№Р Р†Р В°РЎР‹РЎвЂљРЎРѓРЎРЏ" {
    const v = try Version.parse("0.1.3.0");
    try std.testing.expect(v.bump(.l1).eql(.{ .a = 0, .b = 2, .c = 3, .d = 0 }));
    try std.testing.expect(v.bump(.l2).eql(.{ .a = 0, .b = 1, .c = 4, .d = 0 }));
    try std.testing.expect(v.bump(.l3).eql(.{ .a = 0, .b = 1, .c = 3, .d = 1 }));
}

test "Р В·Р В°Р С”РЎР‚РЎвЂ№РЎвЂљР С‘Р Вµ Р СР С‘РЎРѓРЎРѓР С‘Р С‘ РЎРЊРЎвЂљР С• РЎР‚Р ВµР В»Р С‘Р В·: Р СР В»Р В°Р Т‘РЎв‚¬Р С‘Р Вµ РЎРѓР ВµР С–Р СР ВµР Р…РЎвЂљРЎвЂ№ Р С•Р В±Р Р…РЎС“Р В»РЎРЏРЎР‹РЎвЂљРЎРѓРЎРЏ" {
    const v = try Version.parse("0.7.21.0");
    try std.testing.expect(v.bump(.l0).eql(.{ .a = 1, .b = 0, .c = 0, .d = 0 }));
}

test "Р В±Р В°Р СР С—РЎвЂ№ Р Р…Р ВµР В·Р В°Р Р†Р С‘РЎРѓР С‘Р СРЎвЂ№ Р С‘ Р Р…Р В°Р С”Р В°Р С—Р В»Р С‘Р Р†Р В°РЎР‹РЎвЂљРЎРѓРЎРЏ" {
    var v = try Version.parse("0.1.0.0");
    v = v.bump(.l2).bump(.l2).bump(.l3).bump(.l1);
    var buf: [Version.max_len]u8 = undefined;
    try std.testing.expectEqualStrings("0.2.2.1", v.write(&buf));
}

test "Р СРЎС“РЎРѓР С•РЎР‚ Р Р…Р Вµ РЎР‚Р В°Р В·Р В±Р С‘РЎР‚Р В°Р ВµРЎвЂљРЎРѓРЎРЏ" {
    try std.testing.expectError(ParseError.WrongSegmentCount, Version.parse("1.2.3"));
    try std.testing.expectError(ParseError.WrongSegmentCount, Version.parse("1.2.3.4.5"));
    try std.testing.expectError(ParseError.BadSegment, Version.parse("1.2..4"));
    try std.testing.expectError(ParseError.BadSegment, Version.parse("1.2.x.4"));
    try std.testing.expectError(ParseError.BadSegment, Version.parse(""));
    try std.testing.expectError(ParseError.SegmentTooBig, Version.parse("1.2.3.99999"));
}

test "РЎС“РЎР‚Р С•Р Р†Р ВµР Р…РЎРЉ РЎР‚Р В°Р В·Р В±Р С‘РЎР‚Р В°Р ВµРЎвЂљРЎРѓРЎРЏ Р С‘Р В· РЎРѓРЎвЂљРЎР‚Р С•Р С”Р С‘ Р Р† Р В»РЎР‹Р В±Р С•Р С РЎР‚Р ВµР С–Р С‘РЎРѓРЎвЂљРЎР‚Р Вµ" {
    try std.testing.expectEqual(Level.l0, Level.parse("l0").?);
    try std.testing.expectEqual(Level.l3, Level.parse("L3").?);
    try std.testing.expect(Level.parse("l4") == null);
    try std.testing.expect(Level.parse("") == null);
}
