const std = @import("std");
const config_mod = @import("config.zig");
const symlink = @import("symlink.zig");

const ArenaAllocator = std.heap.ArenaAllocator;
const Writer = std.Io.Writer;
const Config = config_mod.Config;

const Status = enum {
    ok,
    skip,
    fail,
    err,
    broken,
    missing,
    conflict,
    wrong,

    const max_len = blk: {
        var max: usize = 0;
        for (@typeInfo(Status).@"enum".fields) |field| {
            const s: Status = @enumFromInt(field.value);
            const len = s.tag().len;
            if (len > max) max = len;
        }
        break :blk max;
    };

    fn print(self: Status, writer: *Writer, comptime fmt: []const u8, args: anytype) !void {
        try writer.print("{s: <" ++ std.fmt.comptimePrint("{d}", .{max_len}) ++ "} " ++ fmt ++ "\n", .{self.tag()} ++ args);
    }

    fn tag(self: Status) []const u8 {
        return switch (self) {
            .ok => "[OK]",
            .skip => "[SKIP]",
            .fail => "[FAIL]",
            .err => "[ERROR]",
            .broken => "[BROKEN]",
            .missing => "[MISSING]",
            .conflict => "[CONFLICT]",
            .wrong => "[WRONG]",
        };
    }
};

pub const CommandError = error{
    LinksFailed,
    LinksUnhealthy,
};

/// Run the link command - create all symlinks from config
pub fn runLink(writer: *Writer, config: Config) !void {
    var created_count: u32 = 0;
    var skipped_count: u32 = 0;
    var failed_count: u32 = 0;

    for (config.links) |link| {
        const result = symlink.createLink(link) catch {
            try Status.fail.print(writer, "{s} -> {s} (error)", .{ link.source, link.destination });
            failed_count += 1;
            continue;
        };

        switch (result) {
            .created => {
                try Status.ok.print(writer, "{s} -> {s}", .{ link.source, link.destination });
                created_count += 1;
            },
            .created_broken => {
                try Status.broken.print(writer, "{s} -> {s} (source does not exist)", .{ link.source, link.destination });
                created_count += 1;
            },
            .skipped => {
                try Status.skip.print(writer, "{s} -> {s} (destination exists, use force: true)", .{ link.source, link.destination });
                skipped_count += 1;
            },
            .failed => {
                try Status.fail.print(writer, "{s} -> {s}", .{ link.source, link.destination });
                failed_count += 1;
            },
        }
    }

    try writer.print("\n{d} created, {d} skipped, {d} failed\n", .{ created_count, skipped_count, failed_count });
    if (failed_count > 0) return CommandError.LinksFailed;
}

/// Run the doctor command - check health of all links
pub fn runDoctor(arena: *ArenaAllocator, writer: *Writer, config: Config) !void {
    var ok_count: u32 = 0;
    var broken_count: u32 = 0;
    var missing_count: u32 = 0;
    var wrong_count: u32 = 0;
    var conflict_count: u32 = 0;

    for (config.links) |link| {
        const status = symlink.checkLink(arena, link) catch {
            try Status.err.print(writer, "{s} -> {s} (could not check)", .{ link.destination, link.source });
            continue;
        };

        switch (status) {
            .ok => {
                try Status.ok.print(writer, "{s} -> {s}", .{ link.destination, link.source });
                ok_count += 1;
            },
            .broken => {
                try Status.broken.print(writer, "{s} -> {s} (source missing)", .{ link.destination, link.source });
                broken_count += 1;
            },
            .missing => {
                try Status.missing.print(writer, "{s} (symlink not created)", .{link.destination});
                missing_count += 1;
            },
            .not_a_symlink => {
                try Status.conflict.print(writer, "{s} (exists but is not a symlink)", .{link.destination});
                conflict_count += 1;
            },
            .wrong_target => {
                const actual = symlink.readLinkTarget(arena, link.destination) catch "<unknown>";
                try Status.wrong.print(writer, "{s} -> {s} (expected {s})", .{ link.destination, actual, link.source });
                wrong_count += 1;
            },
        }
    }

    try writer.print("\n{d} ok, {d} broken, {d} missing, {d} wrong, {d} conflict\n", .{ ok_count, broken_count, missing_count, wrong_count, conflict_count });
    if (ok_count != config.links.len) return CommandError.LinksUnhealthy;
}
