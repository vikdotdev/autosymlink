const std = @import("std");
const aliases_mod = @import("aliases.zig");
const links_mod = @import("links.zig");

const ArenaAllocator = std.heap.ArenaAllocator;

const max_file_size = 1024 * 1024;
const Aliases = aliases_mod.Aliases;
const Link = links_mod.Link;
const Links = links_mod.Links;

pub const ConfigError = error{
    FileNotFound,
    ParseError,
    HomeNotSet,
};

pub const Config = struct {
    links: []const Link,

    pub fn init(arena: *ArenaAllocator, links_path: ?[]const u8, aliases_path: ?[]const u8) !Config {
        const allocator = arena.allocator();
        const resolved_links = links_path orelse try getDefaultConfigPath(arena, "links.json");
        const resolved_aliases = aliases_path orelse try getDefaultConfigPath(arena, "aliases.json");

        var aliases = try loadAliases(arena, resolved_aliases);
        const links_parsed = try loadLinks(arena, resolved_links);

        // Expand all link paths
        var expanded_links = try allocator.alloc(Link, links_parsed.value.links.len);
        for (links_parsed.value.links, 0..) |link, i| {
            expanded_links[i] = Link{
                .source = try expandPath(arena, link.source, &aliases),
                .destination = try expandPath(arena, link.destination, &aliases),
                .force = link.force,
            };
        }

        return Config{
            .links = expanded_links,
        };
    }
};

fn getDefaultConfigPath(arena: *ArenaAllocator, comptime filename: []const u8) ![]const u8 {
    const allocator = arena.allocator();
    if (std.posix.getenv("XDG_CONFIG_HOME")) |base| {
        return std.fmt.allocPrint(allocator, "{s}/autosymlink/" ++ filename, .{base});
    }
    const home = std.posix.getenv("HOME") orelse return ConfigError.HomeNotSet;
    return std.fmt.allocPrint(allocator, "{s}/.config/autosymlink/" ++ filename, .{home});
}

fn loadAliases(arena: *ArenaAllocator, path: []const u8) !Aliases {
    const expanded = try expandTilde(arena, path);
    return Aliases.load(arena, expanded);
}

/// Load and parse links from JSON file
fn loadLinks(arena: *ArenaAllocator, path: []const u8) !std.json.Parsed(Links) {
    const allocator = arena.allocator();
    const expanded_path = try expandTilde(arena, path);

    const file = std.fs.cwd().openFile(expanded_path, .{}) catch |err| {
        if (err == error.FileNotFound) return ConfigError.FileNotFound;
        return err;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, max_file_size);

    return std.json.parseFromSlice(Links, allocator, content, .{
        .allocate = .alloc_always,
    }) catch ConfigError.ParseError;
}

/// Expand ~ to home directory in a path (no alias interpolation)
fn expandTilde(arena: *ArenaAllocator, path: []const u8) ![]const u8 {
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

/// Expand path: interpolate aliases then expand ~
fn expandPath(arena: *ArenaAllocator, path: []const u8, aliases: *Aliases) ![]const u8 {
    const expanded = try aliases.interpolate(arena, path);
    return expandTilde(arena, expanded);
}

const testing = std.testing;

test "expandTilde with absolute path" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const plain = try expandTilde(&arena, "/absolute/path");
    try std.testing.expectEqualStrings("/absolute/path", plain);
}

test "expandTilde with home" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    if (std.posix.getenv("HOME")) |home| {
        const expanded = try expandTilde(&arena, "~/test");
        const expected = try std.fmt.allocPrint(allocator, "{s}/test", .{home});
        try std.testing.expectEqualStrings(expected, expanded);
    }
}
