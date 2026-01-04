const std = @import("std");

const ArenaAllocator = std.heap.ArenaAllocator;

pub const Link = struct {
    source: []const u8,
    destination: []const u8,
    force: bool = false,
};

pub const Config = struct {
    links: []const Link,
};

pub const ConfigError = error{
    FileNotFound,
    ParseError,
    HomeNotSet,
};

/// Expand ~ to home directory in a path
pub fn expandPath(arena: *ArenaAllocator, path: []const u8) ![]const u8 {
    const allocator = arena.allocator();
    if (path.len == 0) return path;

    if (path[0] == '~') {
        const home = std.posix.getenv("HOME") orelse return ConfigError.HomeNotSet;
        if (path.len == 1) {
            return try allocator.dupe(u8, home);
        }
        if (path[1] == '/') {
            return try std.fmt.allocPrint(allocator, "{s}{s}", .{ home, path[1..] });
        }
    }

    return try allocator.dupe(u8, path);
}

/// Load and parse config from JSON file
pub fn loadConfig(arena: *ArenaAllocator, path: []const u8) !std.json.Parsed(Config) {
    const allocator = arena.allocator();
    const expanded_path = try expandPath(arena, path);

    const file = std.fs.cwd().openFile(expanded_path, .{}) catch |err| {
        if (err == error.FileNotFound) return ConfigError.FileNotFound;
        return err;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max

    return std.json.parseFromSlice(Config, allocator, content, .{
        .allocate = .alloc_always,
    }) catch ConfigError.ParseError;
}

test "expandPath with tilde" {
    var arena = ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const plain = try expandPath(&arena, "/absolute/path");
    try std.testing.expectEqualStrings("/absolute/path", plain);
}

test "expandPath home" {
    var arena = ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    if (std.posix.getenv("HOME")) |home| {
        const expanded = try expandPath(&arena, "~/test");
        const expected = try std.fmt.allocPrint(allocator, "{s}/test", .{home});
        try std.testing.expectEqualStrings(expected, expanded);
    }
}
