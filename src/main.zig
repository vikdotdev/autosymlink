const std = @import("std");
const build_options = @import("build_options");
const config = @import("config.zig");
const commands = @import("commands.zig");

const ArenaAllocator = std.heap.ArenaAllocator;

const version = build_options.version;

fn getDefaultConfigPath(arena: *ArenaAllocator) ![]const u8 {
    const allocator = arena.allocator();
    const xdg_config_home = std.posix.getenv("XDG_CONFIG_HOME");
    if (xdg_config_home) |base| {
        return std.fmt.allocPrint(allocator, "{s}/autosymlink/config.json", .{base});
    }
    const home = std.posix.getenv("HOME") orelse return error.HomeNotSet;
    return std.fmt.allocPrint(allocator, "{s}/.config/autosymlink/config.json", .{home});
}

const Command = enum {
    link,
    doctor,
    help,
    version,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    // Parse arguments
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // skip program name

    var command: ?Command = null;
    var config_path: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            command = .help;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            command = .version;
        } else if (std.mem.eql(u8, arg, "--config") or std.mem.eql(u8, arg, "-c")) {
            config_path = args.next() orelse {
                try stderr.print("error: --config requires a path argument\n", .{});
                stderr.flush() catch {};
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "link")) {
            command = .link;
        } else if (std.mem.eql(u8, arg, "doctor")) {
            command = .doctor;
        } else {
            try stderr.print("error: unknown command or option '{s}'\n", .{arg});
            try printUsage(stderr);
            stderr.flush() catch {};
            std.process.exit(1);
        }
    }

    // Handle commands that don't need config
    if (command) |cmd| {
        switch (cmd) {
            .help => {
                try printUsage(stdout);
                return;
            },
            .version => {
                try stdout.print("autosymlink {s}\n", .{version});
                return;
            },
            else => {},
        }
    }

    // Default to help if no command given
    if (command == null) {
        try printUsage(stdout);
        return;
    }

    // Resolve config path
    const resolved_config_path = config_path orelse getDefaultConfigPath(&arena) catch |err| {
        if (err == error.HomeNotSet) {
            try stderr.print("error: HOME environment variable not set\n", .{});
        } else {
            try stderr.print("error: could not determine config path: {any}\n", .{err});
        }
        stderr.flush() catch {};
        std.process.exit(1);
    };

    // Load config
    const cfg = config.loadConfig(&arena, resolved_config_path) catch |err| {
        switch (err) {
            error.FileNotFound => try stderr.print("error: config file not found: {s}\n", .{resolved_config_path}),
            error.ParseError => try stderr.print("error: failed to parse config file: {s}\n", .{resolved_config_path}),
            error.HomeNotSet => try stderr.print("error: HOME environment variable not set\n", .{}),
            else => try stderr.print("error: could not load config: {any}\n", .{err}),
        }
        stderr.flush() catch {};
        std.process.exit(1);
    };
    defer cfg.deinit();

    // Execute command
    const result = switch (command.?) {
        .link => commands.runLink(&arena, cfg.value, stdout),
        .doctor => commands.runDoctor(&arena, cfg.value, stdout),
        .help, .version => unreachable,
    };

    result catch |err| switch (err) {
        error.LinksFailed, error.LinksUnhealthy => {
            stdout.flush() catch {};
            std.process.exit(1);
        },
        else => return err,
    };
}

fn printUsage(writer: anytype) !void {
    try writer.print(
        \\autosymlink - Symlink manager based on config file
        \\
        \\USAGE:
        \\    autosymlink <command> [options]
        \\
        \\COMMANDS:
        \\    link        Create symlinks defined in config
        \\    doctor      Check health of all symlinks
        \\
        \\OPTIONS:
        \\    -c, --config <path>    Config file path (default: ~/.config/autosymlink/config.json)
        \\    -h, --help             Show this help
        \\    -v, --version          Show version
        \\
        \\CONFIG FORMAT:
        \\    {{
        \\      "links": [
        \\        {{"source": "~/.dotfiles/bashrc", "destination": "~/.bashrc"}},
        \\        {{"source": "~/.dotfiles/vimrc", "destination": "~/.vimrc", "force": true}}
        \\      ]
        \\    }}
        \\
    , .{});
}

test {
    _ = config;
    _ = commands;
    _ = @import("symlink.zig");
}
