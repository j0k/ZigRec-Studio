//! Собрать всё, что нужно для экспорта и сведения, по одному пути (#110).
//!
//! Экспорту нужен не только проект: ключевые кадры каждого исходника (чтобы
//! решить, можно ли обойтись без перекодирования), их звук (чтобы свести
//! дорожки) и слои событий (чтобы впечатать курсор). В редакторе всё это
//! уже лежит на местах, а просьбе извне достаётся один путь — к проекту
//! `.zrs` или прямо к записи.
//!
//! Здесь это собирается в одном месте, чтобы окно не собирало то же самое
//! во второй раз и по-своему: разойдясь, два сборщика дали бы разный
//! экспорт на один и тот же файл.
const std = @import("std");
const timeline = @import("timeline.zig");
const project_file = @import("../file/project_file.zig");
const media = @import("../file/media.zig");
const keyframes = @import("../file/keyframes.zig");
const audio_read = @import("../file/audio_read.zig");
const mixdown = @import("mixdown.zig");
const events = @import("../file/events.zig");

pub const Error = error{
    /// Ни проект, ни медиафайл не читаются.
    NotReadable,
    /// В проекте нет ни одного куска.
    Empty,
    OutOfMemory,
};

/// Проект «под ключ» вместе со всем, что нужно экспорту.
///
/// Владеет всем, что собрал: проект живёт в куче (на стеке он не помещается),
/// списки и звук освобождаются в `deinit`.
pub const Ready = struct {
    allocator: std.mem.Allocator,
    project: *timeline.Project,
    keys: [][]const u64,
    audio: []mixdown.SourceAudio,
    layers: []?events.Events,
    /// Память под звук: `audio` показывает внутрь этих кусков.
    audio_store: []audio_read.Audio,

    pub fn deinit(self: *Ready) void {
        const a = self.allocator;
        for (self.keys) |list| a.free(list);
        a.free(self.keys);
        for (self.audio_store) |*sound| sound.deinit(a);
        a.free(self.audio_store);
        a.free(self.audio);
        for (self.layers) |*maybe| if (maybe.*) |*layer| layer.deinit(a);
        a.free(self.layers);
        a.destroy(self.project);
        self.* = undefined;
    }
};

/// Проект из файла проекта или из одной записи.
///
/// `.zrs` читается как проект; всё остальное считается записью, и тогда
/// проект собирается из неё: видеодорожка и звуковая, один кусок от `from_ns`
/// до `to_ns`. Ноль в `to_ns` означает «до конца».
pub fn fromPath(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    from_ns: u64,
    to_ns: u64,
) !Ready {
    const project = try allocator.create(timeline.Project);
    errdefer allocator.destroy(project);
    project.* = .{};

    if (std.mem.endsWith(u8, path, ".zrs")) {
        const data = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(8 << 20));
        defer allocator.free(data);
        const base = std.fs.path.dirname(path) orelse ".";
        try project_file.read(project, data, base);
    } else {
        const info = try media.read(io, allocator, path);
        const src = try project.addSource(path, info.duration_ns);
        const start = @min(from_ns, info.duration_ns);
        const stop = if (to_ns == 0 or to_ns > info.duration_ns) info.duration_ns else to_ns;
        if (stop <= start) return Error.Empty;
        const len_ns = stop - start;
        const vt = try project.addTrack(.video, "видео");
        try project.place(vt, src, 0, len_ns);
        project.tracks[vt].clips[0].in_ns = start;
        var has_audio = false;
        for (info.list()) |t| {
            if (t.kind == .audio) has_audio = true;
        }
        if (has_audio) {
            const at = try project.addTrack(.audio, "звук");
            try project.place(at, src, 0, len_ns);
            project.tracks[at].clips[0].in_ns = start;
        }
    }

    const count = project.sourceList().len;
    if (count == 0) return Error.Empty;

    var keys = try allocator.alloc([]const u64, count);
    errdefer allocator.free(keys);
    var audio_store = try allocator.alloc(audio_read.Audio, count);
    errdefer allocator.free(audio_store);
    var sources = try allocator.alloc(mixdown.SourceAudio, count);
    errdefer allocator.free(sources);
    var layers = try allocator.alloc(?events.Events, count);
    errdefer allocator.free(layers);

    for (project.sourceList(), 0..) |src, i| {
        const full = src.fullPath();
        // Ключевые кадры: не прочитались — считаем, что их нет, и экспорт
        // пойдёт с перекодированием. Это медленнее, но честнее, чем резать
        // не по ключу и отдать файл, который начинается с мусора.
        keys[i] = keyframes.read(io, allocator, full) catch try allocator.alloc(u64, 0);
        audio_store[i] = audio_read.read(allocator, full) catch audio_read.Audio{};
        sources[i] = .{ .rate = audio_store[i].rate, .samples = audio_store[i].samples };
        layers[i] = readLayer(allocator, io, full);
    }

    return .{
        .allocator = allocator,
        .project = project,
        .keys = keys,
        .audio = sources,
        .layers = layers,
        .audio_store = audio_store,
    };
}

/// Слой событий рядом с записью; нет — значит нет.
fn readLayer(allocator: std.mem.Allocator, io: std.Io, media_path: []const u8) ?events.Events {
    var buf: [1024]u8 = undefined;
    const side = events.sidecarPath(&buf, media_path);
    const data = std.Io.Dir.cwd().readFileAlloc(io, side, allocator, .limited(64 << 20)) catch return null;
    defer allocator.free(data);
    return events.read(allocator, data) catch null;
}

// ---------------------------------------------------------------- тесты

const testing = std.testing;

test "проект из записи: один кусок от и до" {
    // Без файлов тут не обойтись, поэтому проверяем то, что можно проверить
    // без Windows: границы куска считаются правильно.
    const duration: u64 = 10 * std.time.ns_per_s;
    const cases = [_]struct { from: u64, to: u64, want: u64 }{
        .{ .from = 0, .to = 0, .want = duration },
        .{ .from = 0, .to = 4 * std.time.ns_per_s, .want = 4 * std.time.ns_per_s },
        .{ .from = 2 * std.time.ns_per_s, .to = 0, .want = 8 * std.time.ns_per_s },
        .{ .from = 2 * std.time.ns_per_s, .to = 99 * std.time.ns_per_s, .want = 8 * std.time.ns_per_s },
    };
    for (cases) |c| {
        const start = @min(c.from, duration);
        const stop = if (c.to == 0 or c.to > duration) duration else c.to;
        try testing.expectEqual(c.want, stop - start);
    }
}

test "пустой отрезок — не экспорт" {
    const duration: u64 = 10 * std.time.ns_per_s;
    const from: u64 = 5 * std.time.ns_per_s;
    const to: u64 = 5 * std.time.ns_per_s;
    const stop = if (to == 0 or to > duration) duration else to;
    try testing.expect(stop <= from);
}
