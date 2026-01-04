const std = @import("std");

const ArenaAllocator = std.heap.ArenaAllocator;

pub const AliasError = error{
    ParseError,
    UnknownVariable,
    MaxDepthExceeded,
    InvalidSyntax,
    OutOfMemory,
};

const max_resolution_depth = 32;
const max_file_size = 1024 * 1024;

/// Built-in variable names
pub const builtins = struct {
    pub const home = "_home";
    pub const hostname = "_hostname";
    pub const user = "_user";
};

pub const Alias = []const u8;

pub const Aliases = struct {
    map: std.StringHashMap(Alias),

    pub fn init(arena: *ArenaAllocator) !Aliases {
        const allocator = arena.allocator();
        var map = std.StringHashMap(Alias).init(allocator);

        // Built-in variables
        if (std.posix.getenv("HOME")) |home| {
            try map.put(builtins.home, try allocator.dupe(u8, home));
        }

        if (std.posix.getenv("USER")) |user| {
            try map.put(builtins.user, try allocator.dupe(u8, user));
        }

        var hostname_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
        const hostname = std.posix.gethostname(&hostname_buf) catch null;
        if (hostname) |h| {
            try map.put(builtins.hostname, try allocator.dupe(u8, h));
        }

        return .{ .map = map };
    }

    /// Load aliases from JSON file, returns empty aliases if file not found
    pub fn load(arena: *ArenaAllocator, path: []const u8) !Aliases {
        const allocator = arena.allocator();
        var self = try init(arena);

        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            if (err == error.FileNotFound) return self;
            return err;
        };
        defer file.close();

        const content = try file.readToEndAlloc(allocator, max_file_size);

        const parsed = std.json.parseFromSlice(
            std.json.Value,
            allocator,
            content,
            .{},
        ) catch return AliasError.ParseError;

        if (parsed.value != .object) return AliasError.ParseError;

        // First pass: add all raw values
        var it = parsed.value.object.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* != .string) return AliasError.ParseError;
            try self.map.put(entry.key_ptr.*, entry.value_ptr.string);
        }

        // Second pass: resolve nested references
        try self.resolveAll(arena);

        return self;
    }

    /// Resolve all nested references in aliases
    fn resolveAll(self: *Aliases, arena: *ArenaAllocator) !void {
        const allocator = arena.allocator();
        var keys = std.ArrayListUnmanaged([]const u8){};
        var it = self.map.iterator();
        while (it.next()) |entry| {
            try keys.append(allocator, entry.key_ptr.*);
        }

        for (keys.items) |key| {
            const value = self.map.get(key).?;
            const resolved = try self.resolveValue(arena, value, 0);
            try self.map.put(key, resolved);
        }
    }

    /// Resolve ${var} references in a value
    fn resolveValue(self: *Aliases, arena: *ArenaAllocator, value: Alias, depth: usize) AliasError!Alias {
        if (depth >= max_resolution_depth) return AliasError.MaxDepthExceeded;

        const allocator = arena.allocator();
        var result = std.ArrayListUnmanaged(u8){};
        var i: usize = 0;

        while (i < value.len) {
            if (i + 1 < value.len and value[i] == '$' and value[i + 1] == '{') {
                // Find closing brace
                const start = i + 2;
                var end = start;
                while (end < value.len and value[end] != '}') : (end += 1) {}

                if (end >= value.len) return AliasError.InvalidSyntax;

                const var_name = value[start..end];
                const var_value = try self.lookupVariable(arena, var_name, depth + 1);
                try result.appendSlice(allocator, var_value);

                i = end + 1;
            } else {
                try result.append(allocator, value[i]);
                i += 1;
            }
        }

        return try allocator.dupe(u8, result.items);
    }

    /// Look up a variable: aliases -> env vars -> error
    fn lookupVariable(self: *Aliases, arena: *ArenaAllocator, name: []const u8, depth: usize) AliasError!Alias {
        const allocator = arena.allocator();

        // Check aliases first
        if (self.map.get(name)) |value| {
            // Recursively resolve if it contains references
            return try self.resolveValue(arena, value, depth);
        }

        // Check environment variables
        // Need null-terminated string for getenv
        const name_z = try allocator.dupeZ(u8, name);
        if (std.posix.getenv(name_z)) |env_value| {
            return try allocator.dupe(u8, env_value);
        }

        return AliasError.UnknownVariable;
    }

    /// Interpolate ${var} references in a string
    pub fn interpolate(self: *Aliases, arena: *ArenaAllocator, value: Alias) !Alias {
        return self.resolveValue(arena, value, 0);
    }
};

// Tests
const testing = std.testing;

test "built-in variables" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const aliases = try Aliases.init(&arena);

    // _home should be set if HOME is set
    if (std.posix.getenv("HOME")) |home| {
        const value = aliases.map.get(builtins.home);
        try testing.expect(value != null);
        try testing.expectEqualStrings(home, value.?);
    }
}

test "interpolate simple variable" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var aliases = try Aliases.init(&arena);
    try aliases.map.put("foo", "bar");

    const result = try aliases.interpolate(&arena, "prefix/${foo}/suffix");
    try testing.expectEqualStrings("prefix/bar/suffix", result);
}

test "interpolate nested variables" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var aliases = try Aliases.init(&arena);
    try aliases.map.put("base", "/home/user");
    try aliases.map.put("dotfiles", "${base}/.dotfiles");

    // Resolve nested references
    try aliases.resolveAll(&arena);

    const result = try aliases.interpolate(&arena, "${dotfiles}/nvim");
    try testing.expectEqualStrings("/home/user/.dotfiles/nvim", result);
}

test "interpolate env var fallback" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var aliases = try Aliases.init(&arena);

    // HOME should be available as env var
    if (std.posix.getenv("HOME")) |home| {
        const result = try aliases.interpolate(&arena, "${HOME}/test");
        const expected = try std.fmt.allocPrint(arena.allocator(), "{s}/test", .{home});
        try testing.expectEqualStrings(expected, result);
    }
}

test "unknown variable error" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var aliases = try Aliases.init(&arena);

    const result = aliases.interpolate(&arena, "${nonexistent_var_xyz}");
    try testing.expectError(AliasError.UnknownVariable, result);
}

test "invalid syntax error" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var aliases = try Aliases.init(&arena);

    const result = aliases.interpolate(&arena, "${unclosed");
    try testing.expectError(AliasError.InvalidSyntax, result);
}

test "no interpolation needed" {
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var aliases = try Aliases.init(&arena);

    const result = try aliases.interpolate(&arena, "/plain/path/no/vars");
    try testing.expectEqualStrings("/plain/path/no/vars", result);
}
