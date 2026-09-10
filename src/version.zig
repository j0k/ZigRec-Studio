//! Р•РґРёРЅСЃС‚РІРµРЅРЅС‹Р№ РёСЃС‚РѕС‡РЅРёРє РІРµСЂСЃРёРё РїСЂРѕРµРєС‚Р°.
//!
//! Р§РµС‚С‹СЂРµ СЃРµРіРјРµРЅС‚Р° `A.B.C.D`, РїСЂРёРІСЏР·Р°РЅРЅС‹Рµ Рє СѓСЂРѕРІРЅСЏРј РєР°РЅР±Р°РЅР°:
//!
//!     L0 (РјРёСЃСЃРёСЏ)    -> A   СЂРµР»РёР·РЅР°СЏ РІРµС…Р°: A+1, РѕСЃС‚Р°Р»СЊРЅРѕРµ РІ РЅРѕР»СЊ
//!     L1 (СЌРїРёРє)      -> B   +0.1.0.0
//!     L2 (Р·Р°РґР°С‡Р°)    -> C   +0.0.1.0
//!     L3 (РїРѕРґР·Р°РґР°С‡Р°) -> D   +0.0.0.1
//!
//! РђРґРґРёС‚РёРІРЅРѕ: Р·Р°РєСЂС‹С‚РёРµ С‚РёРєРµС‚Р° РїРѕРґРЅРёРјР°РµС‚ С‚РѕР»СЊРєРѕ СЃРµРіРјРµРЅС‚ СЃРІРѕРµРіРѕ СѓСЂРѕРІРЅСЏ, РјР»Р°РґС€РёРµ
//! СЃРµРіРјРµРЅС‚С‹ РќР• СЃР±СЂР°СЃС‹РІР°СЋС‚СЃСЏ (`0.1.3.0` --L1--> `0.2.3.0`).
//!
//! РСЃРєР»СЋС‡РµРЅРёРµ вЂ” L0. Р—Р°РєСЂС‹С‚РёРµ РјРёСЃСЃРёРё СЌС‚Рѕ СЂРµР»РёР·, Рё РІРµСЂСЃРёСЏ СЃС‚Р°РЅРѕРІРёС‚СЃСЏ С‡РёСЃС‚С‹Рј
//! СЂРµР»РёР·РЅС‹Рј РЅРѕРјРµСЂРѕРј: РїСѓС‚СЊ `0.7.21.0` --L0--> `1.0.0.0`.
//!
//! Р‘Р°РјРїР°РµС‚СЃСЏ РІ С‚РѕРј Р¶Рµ РєРѕРјРјРёС‚Рµ, С‡С‚Рѕ Рё СЃР°Рј РєРѕРґ. `VERSION_DATE` РґРІРёРіР°РµС‚СЃСЏ РІРјРµСЃС‚Рµ
//! СЃ `VERSION`. РџРѕРґСЂРѕР±РЅРѕСЃС‚Рё: РІРёРєРё Versioning.
const std = @import("std");

pub const VERSION = "0.1.11.4";
/// Р”Р°С‚Р° РІС‹РїСѓСЃРєР° VERSION (ISO). Р”РІРёРіР°С‚СЊ РІРјРµСЃС‚Рµ СЃ VERSION.
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
    /// РЎРµРіРјРµРЅС‚РѕРІ РЅРµ С‡РµС‚С‹СЂРµ.
    WrongSegmentCount,
    /// РЎРµРіРјРµРЅС‚ РїСѓСЃС‚ РёР»Рё СЃРѕРґРµСЂР¶РёС‚ РЅРµ С‚РѕР»СЊРєРѕ С†РёС„СЂС‹.
    BadSegment,
    /// РЎРµРіРјРµРЅС‚ РЅРµ РІР»РµР·Р°РµС‚ РІ u16.
    SegmentTooBig,
};

/// Р Р°Р·РѕР±СЂР°РЅРЅР°СЏ РІРµСЂСЃРёСЏ. РџРµС‡Р°С‚Р°РµС‚СЃСЏ С‡РµСЂРµР· `std.fmt` РєР°Рє `A.B.C.D`.
pub const Version = struct {
    a: u16 = 0,
    b: u16 = 0,
    c: u16 = 0,
    d: u16 = 0,

    /// РњР°РєСЃРёРјР°Р»СЊРЅР°СЏ РґР»РёРЅР° С‚РµРєСЃС‚РѕРІРѕРіРѕ РїСЂРµРґСЃС‚Р°РІР»РµРЅРёСЏ: 4 С‡РёСЃР»Р° РїРѕ 5 С†РёС„СЂ Рё 3 С‚РѕС‡РєРё.
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

    /// Р’РµСЂСЃРёСЏ РїРѕСЃР»Рµ Р·Р°РєСЂС‹С‚РёСЏ С‚РёРєРµС‚Р° СѓСЂРѕРІРЅСЏ `level`.
    ///
    /// L0 РѕР±РЅСѓР»СЏРµС‚ РјР»Р°РґС€РёРµ СЃРµРіРјРµРЅС‚С‹, РїРѕС‚РѕРјСѓ С‡С‚Рѕ СЌС‚Рѕ СЂРµР»РёР·, Р° РЅРµ РµС‰С‘ РѕРґРёРЅ С€Р°Рі:
    /// РЅРѕРјРµСЂ СЂРµР»РёР·Р° РґРѕР»Р¶РµРЅ С‡РёС‚Р°С‚СЊСЃСЏ РєР°Рє РЅРѕРјРµСЂ СЂРµР»РёР·Р°, Р° РЅРµ С‚Р°С‰РёС‚СЊ Р·Р° СЃРѕР±РѕР№
    /// СЃС‡С‘С‚С‡РёРє Р·Р°РґР°С‡ РїСЂРµРґС‹РґСѓС‰РµРіРѕ РїСѓС‚Рё.
    pub fn bump(self: Version, level: Level) Version {
        return switch (level) {
            .l0 => .{ .a = self.a + 1 },
            .l1 => .{ .a = self.a, .b = self.b + 1, .c = self.c, .d = self.d },
            .l2 => .{ .a = self.a, .b = self.b, .c = self.c + 1, .d = self.d },
            .l3 => .{ .a = self.a, .b = self.b, .c = self.c, .d = self.d + 1 },
        };
    }

    /// РўРµРєСЃС‚ РІРµСЂСЃРёРё РІ РїРµСЂРµРґР°РЅРЅС‹Р№ Р±СѓС„РµСЂ (РЅСѓР¶РµРЅ РјРёРЅРёРјСѓРј `max_len` Р±Р°Р№С‚).
    pub fn write(self: Version, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "{d}.{d}.{d}.{d}", .{ self.a, self.b, self.c, self.d }) catch unreachable;
    }

    pub fn eql(self: Version, other: Version) bool {
        return self.a == other.a and self.b == other.b and self.c == other.c and self.d == other.d;
    }
};

/// Р Р°Р·РѕР±СЂР°РЅРЅР°СЏ РІРµСЂСЃРёСЏ РїСЂРѕРµРєС‚Р°. РћС€РёР±РёС‚СЊСЃСЏ РЅРµР»СЊР·СЏ: СЃС‚СЂРѕРєР° РїСЂРѕРІРµСЂСЏРµС‚СЃСЏ С‚РµСЃС‚РѕРј.
pub fn current() Version {
    return Version.parse(VERSION) catch unreachable;
}

// ---------------------------------------------------------------- С‚РµСЃС‚С‹

test "РІРµСЂСЃРёСЏ РїСЂРѕРµРєС‚Р° СЂР°Р·Р±РёСЂР°РµС‚СЃСЏ Рё РїРµС‡Р°С‚Р°РµС‚СЃСЏ РѕР±СЂР°С‚РЅРѕ С‚РµРј Р¶Рµ С‚РµРєСЃС‚РѕРј" {
    const v = try Version.parse(VERSION);
    var buf: [Version.max_len]u8 = undefined;
    try std.testing.expectEqualStrings(VERSION, v.write(&buf));
}

test "РґР°С‚Р° РІРµСЂСЃРёРё РІС‹РіР»СЏРґРёС‚ РєР°Рє ISO-РґР°С‚Р°" {
    try std.testing.expectEqual(@as(usize, 10), VERSION_DATE.len);
    try std.testing.expectEqual(@as(u8, '-'), VERSION_DATE[4]);
    try std.testing.expectEqual(@as(u8, '-'), VERSION_DATE[7]);
    for (VERSION_DATE, 0..) |ch, i| {
        if (i == 4 or i == 7) continue;
        try std.testing.expect(std.ascii.isDigit(ch));
    }
}

test "Р±Р°РјРї РїРѕРґРЅРёРјР°РµС‚ С‚РѕР»СЊРєРѕ СЃРІРѕР№ СЃРµРіРјРµРЅС‚, РјР»Р°РґС€РёРµ РЅРµ СЃР±СЂР°СЃС‹РІР°СЋС‚СЃСЏ" {
    const v = try Version.parse("0.1.3.0");
    try std.testing.expect(v.bump(.l1).eql(.{ .a = 0, .b = 2, .c = 3, .d = 0 }));
    try std.testing.expect(v.bump(.l2).eql(.{ .a = 0, .b = 1, .c = 4, .d = 0 }));
    try std.testing.expect(v.bump(.l3).eql(.{ .a = 0, .b = 1, .c = 3, .d = 1 }));
}

test "Р·Р°РєСЂС‹С‚РёРµ РјРёСЃСЃРёРё СЌС‚Рѕ СЂРµР»РёР·: РјР»Р°РґС€РёРµ СЃРµРіРјРµРЅС‚С‹ РѕР±РЅСѓР»СЏСЋС‚СЃСЏ" {
    const v = try Version.parse("0.7.21.0");
    try std.testing.expect(v.bump(.l0).eql(.{ .a = 1, .b = 0, .c = 0, .d = 0 }));
}

test "Р±Р°РјРїС‹ РЅРµР·Р°РІРёСЃРёРјС‹ Рё РЅР°РєР°РїР»РёРІР°СЋС‚СЃСЏ" {
    var v = try Version.parse("0.1.0.0");
    v = v.bump(.l2).bump(.l2).bump(.l3).bump(.l1);
    var buf: [Version.max_len]u8 = undefined;
    try std.testing.expectEqualStrings("0.2.2.1", v.write(&buf));
}

test "РјСѓСЃРѕСЂ РЅРµ СЂР°Р·Р±РёСЂР°РµС‚СЃСЏ" {
    try std.testing.expectError(ParseError.WrongSegmentCount, Version.parse("1.2.3"));
    try std.testing.expectError(ParseError.WrongSegmentCount, Version.parse("1.2.3.4.5"));
    try std.testing.expectError(ParseError.BadSegment, Version.parse("1.2..4"));
    try std.testing.expectError(ParseError.BadSegment, Version.parse("1.2.x.4"));
    try std.testing.expectError(ParseError.BadSegment, Version.parse(""));
    try std.testing.expectError(ParseError.SegmentTooBig, Version.parse("1.2.3.99999"));
}

test "СѓСЂРѕРІРµРЅСЊ СЂР°Р·Р±РёСЂР°РµС‚СЃСЏ РёР· СЃС‚СЂРѕРєРё РІ Р»СЋР±РѕРј СЂРµРіРёСЃС‚СЂРµ" {
    try std.testing.expectEqual(Level.l0, Level.parse("l0").?);
    try std.testing.expectEqual(Level.l3, Level.parse("L3").?);
    try std.testing.expect(Level.parse("l4") == null);
    try std.testing.expect(Level.parse("") == null);
}
