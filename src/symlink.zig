const std = @import("std");
const config = @import("config.zig");

const ArenaAllocator = std.heap.ArenaAllocator;

pub const LinkStatus = enum {
    ok,
    broken, // symlink exists but source is missing
    missing, // destination doesn't exist
    not_a_symlink, // destination exists but is not a symlink
    wrong_target, // symlink points to wrong source
};

pub const CreateResult = enum {
    created,
    skipped, // destination exists and force=false
    failed,
};

/// Check the status of a symlink using fstatat with SYMLINK_NOFOLLOW
pub fn checkLink(arena: *ArenaAllocator, link: config.Link) !LinkStatus {
    const allocator = arena.allocator();
    const source = try config.expandPath(arena, link.source);
    const destination = try config.expandPath(arena, link.destination);
    const dest_z = try allocator.dupeZ(u8, destination);

    // Use fstatat with SYMLINK_NOFOLLOW to detect symlinks
    const stat = std.posix.fstatat(std.posix.AT.FDCWD, dest_z, std.posix.AT.SYMLINK_NOFOLLOW) catch |err| {
        if (err == error.FileNotFound) return .missing;
        return err;
    };

    // Check if it's a symlink
    if (!std.posix.S.ISLNK(stat.mode)) {
        return .not_a_symlink;
    }

    // Read the symlink target
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const target = std.fs.cwd().readLink(destination, &buf) catch {
        return .broken;
    };

    // Check if target matches expected source
    if (!std.mem.eql(u8, target, source)) {
        return .wrong_target;
    }

    // Check if source actually exists
    std.fs.cwd().access(source, .{}) catch {
        return .broken;
    };

    return .ok;
}

/// Create a symlink
pub fn createLink(arena: *ArenaAllocator, link: config.Link) !CreateResult {
    const source = try config.expandPath(arena, link.source);
    const destination = try config.expandPath(arena, link.destination);

    // Check if destination already exists
    const exists = blk: {
        std.fs.cwd().access(destination, .{}) catch break :blk false;
        break :blk true;
    };

    if (exists) {
        if (!link.force) {
            return .skipped;
        }
        // Remove existing file/symlink
        std.fs.cwd().deleteFile(destination) catch |err| {
            // Try removing as directory
            if (err == error.IsDir) {
                std.fs.cwd().deleteDir(destination) catch return .failed;
            } else {
                return .failed;
            }
        };
    }

    // Ensure parent directory exists
    if (std.fs.path.dirname(destination)) |parent| {
        std.fs.cwd().makePath(parent) catch {};
    }

    // Create the symlink
    std.fs.cwd().symLink(source, destination, .{}) catch {
        return .failed;
    };

    return .created;
}

/// Get the current target of a symlink (for reporting)
pub fn readLinkTarget(arena: *ArenaAllocator, path: []const u8) ![]const u8 {
    const allocator = arena.allocator();
    const expanded = try config.expandPath(arena, path);

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const target = std.fs.cwd().readLink(expanded, &buf) catch |err| {
        return err;
    };

    return try allocator.dupe(u8, target);
}

// Integration tests using test-tmp/ directory
const testing = std.testing;

fn setupTestDir(comptime name: []const u8) !std.fs.Dir {
    const path = "test-tmp/" ++ name;
    std.fs.cwd().deleteTree(path) catch {};
    return std.fs.cwd().makeOpenPath(path, .{});
}

fn cleanupTestDir(comptime name: []const u8) void {
    const path = "test-tmp/" ++ name;
    std.fs.cwd().deleteTree(path) catch {};
}

test "createLink creates symlink" {
    const name = "create";
    var dir = try setupTestDir(name);
    defer dir.close();
    defer cleanupTestDir(name);

    // Create source file
    var src = try dir.createFile("source.txt", .{});
    src.close();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const link = config.Link{
        .source = "test-tmp/" ++ name ++ "/source.txt",
        .destination = "test-tmp/" ++ name ++ "/dest.txt",
        .force = false,
    };

    const result = try createLink(&arena, link);
    try testing.expectEqual(.created, result);

    // Verify symlink exists and points to source
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const target = try std.fs.cwd().readLink("test-tmp/" ++ name ++ "/dest.txt", &buf);
    try testing.expectEqualStrings("test-tmp/" ++ name ++ "/source.txt", target);
}

test "createLink skips existing destination" {
    const name = "skip";
    var dir = try setupTestDir(name);
    defer dir.close();
    defer cleanupTestDir(name);

    // Create source and existing destination
    var src = try dir.createFile("source.txt", .{});
    src.close();
    var dst = try dir.createFile("dest.txt", .{});
    dst.close();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const link = config.Link{
        .source = "test-tmp/" ++ name ++ "/source.txt",
        .destination = "test-tmp/" ++ name ++ "/dest.txt",
        .force = false,
    };

    const result = try createLink(&arena, link);
    try testing.expectEqual(.skipped, result);
}

test "createLink with force overwrites" {
    const name = "force";
    var dir = try setupTestDir(name);
    defer dir.close();
    defer cleanupTestDir(name);

    // Create source and existing destination
    var src = try dir.createFile("source.txt", .{});
    src.close();
    var dst = try dir.createFile("dest.txt", .{});
    dst.close();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const link = config.Link{
        .source = "test-tmp/" ++ name ++ "/source.txt",
        .destination = "test-tmp/" ++ name ++ "/dest.txt",
        .force = true,
    };

    const result = try createLink(&arena, link);
    try testing.expectEqual(.created, result);

    // Verify it's now a symlink using fstatat with SYMLINK_NOFOLLOW
    const stat = try std.posix.fstatat(std.posix.AT.FDCWD, "test-tmp/" ++ name ++ "/dest.txt", std.posix.AT.SYMLINK_NOFOLLOW);
    try testing.expect(std.posix.S.ISLNK(stat.mode));
}

test "checkLink returns ok for valid symlink" {
    const name = "ok";
    var dir = try setupTestDir(name);
    defer dir.close();
    defer cleanupTestDir(name);

    // Create source file
    var src = try dir.createFile("source.txt", .{});
    src.close();

    // Create symlink
    try std.fs.cwd().symLink("test-tmp/" ++ name ++ "/source.txt", "test-tmp/" ++ name ++ "/dest.txt", .{});

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const link = config.Link{
        .source = "test-tmp/" ++ name ++ "/source.txt",
        .destination = "test-tmp/" ++ name ++ "/dest.txt",
    };

    const status = try checkLink(&arena, link);
    try testing.expectEqual(.ok, status);
}

test "checkLink returns missing when no symlink" {
    const name = "missing";
    var dir = try setupTestDir(name);
    defer dir.close();
    defer cleanupTestDir(name);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const link = config.Link{
        .source = "test-tmp/" ++ name ++ "/source.txt",
        .destination = "test-tmp/" ++ name ++ "/nonexistent.txt",
    };

    const status = try checkLink(&arena, link);
    try testing.expectEqual(.missing, status);
}

test "checkLink returns broken when source missing" {
    const name = "broken";
    var dir = try setupTestDir(name);
    defer dir.close();
    defer cleanupTestDir(name);

    // Create symlink to non-existent source
    try std.fs.cwd().symLink("test-tmp/" ++ name ++ "/missing.txt", "test-tmp/" ++ name ++ "/dest.txt", .{});

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const link = config.Link{
        .source = "test-tmp/" ++ name ++ "/missing.txt",
        .destination = "test-tmp/" ++ name ++ "/dest.txt",
    };

    const status = try checkLink(&arena, link);
    try testing.expectEqual(.broken, status);
}

test "checkLink returns not_a_symlink for regular file" {
    const name = "notsym";
    var dir = try setupTestDir(name);
    defer dir.close();
    defer cleanupTestDir(name);

    // Create regular file at destination
    var dst = try dir.createFile("dest.txt", .{});
    dst.close();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const link = config.Link{
        .source = "test-tmp/" ++ name ++ "/source.txt",
        .destination = "test-tmp/" ++ name ++ "/dest.txt",
    };

    const status = try checkLink(&arena, link);
    try testing.expectEqual(.not_a_symlink, status);
}

test "checkLink returns wrong_target for mismatched symlink" {
    const name = "wrong";
    var dir = try setupTestDir(name);
    defer dir.close();
    defer cleanupTestDir(name);

    // Create two source files
    var src1 = try dir.createFile("source1.txt", .{});
    src1.close();
    var src2 = try dir.createFile("source2.txt", .{});
    src2.close();

    // Create symlink pointing to source2
    try std.fs.cwd().symLink("test-tmp/" ++ name ++ "/source2.txt", "test-tmp/" ++ name ++ "/dest.txt", .{});

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const link = config.Link{
        .source = "test-tmp/" ++ name ++ "/source1.txt", // expecting source1
        .destination = "test-tmp/" ++ name ++ "/dest.txt",
    };

    const status = try checkLink(&arena, link);
    try testing.expectEqual(.wrong_target, status);
}
