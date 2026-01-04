const std = @import("std");
const build_options = @import("build_options");
const config_mod = @import("config.zig");
const commands = @import("commands.zig");

const Config = config_mod.Config;

const ArenaAllocator = std.heap.ArenaAllocator;

const version = build_options.version;

const Command = enum {
    link,
    doctor,
    help,
    version,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = ArenaAllocator.init(gpa.allocator());
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
    var links_path: ?[]const u8 = null;
    var aliases_path: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            command = .help;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            command = .version;
        } else if (std.mem.eql(u8, arg, "--links") or std.mem.eql(u8, arg, "-l")) {
            links_path = args.next() orelse {
                try stderr.print("error: --links requires a path argument\n", .{});
                stderr.flush() catch {};
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "--aliases") or std.mem.eql(u8, arg, "-a")) {
            aliases_path = args.next() orelse {
                try stderr.print("error: --aliases requires a path argument\n", .{});
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

    // Load config
    const config = Config.init(&arena, links_path, aliases_path) catch |err| {
        switch (err) {
            error.FileNotFound => try stderr.print("error: links file not found\n", .{}),
            error.ParseError => try stderr.print("error: failed to parse config file\n", .{}),
            error.HomeNotSet => try stderr.print("error: HOME environment variable not set\n", .{}),
            else => try stderr.print("error: could not load config: {any}\n", .{err}),
        }
        stderr.flush() catch {};
        std.process.exit(1);
    };

    // Execute command
    const result = switch (command.?) {
        .link => commands.runLink(stdout, config),
        .doctor => commands.runDoctor(&arena, stdout, config),
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
        \\    -l, --links <path>      Links file path (default: ~/.config/autosymlink/links.json)
        \\    -a, --aliases <path>    Aliases file path (default: ~/.config/autosymlink/aliases.json)
        \\    -h, --help              Show this help
        \\    -v, --version           Show version
        \\
        \\LINKS FORMAT (links.json):
        \\    {{
        \\      "links": [
        \\        {{"source": "${{dotfiles}}/bashrc", "destination": "~/.bashrc"}},
        \\        {{"source": "${{dotfiles}}/vimrc", "destination": "~/.vimrc", "force": true}}
        \\      ]
        \\    }}
        \\
        \\ALIASES FORMAT (aliases.json):
        \\    {{
        \\      "dotfiles": "${{_home}}/.dotfiles",
        \\      "nvim": "${{dotfiles}}/nvim"
        \\    }}
        \\
        \\BUILT-IN VARIABLES:
        \\    ${{_home}}       Home directory
        \\    ${{_user}}       Current user
        \\    ${{_hostname}}   Machine hostname
        \\
    , .{});
}

test {
    _ = config_mod;
    _ = commands;
    _ = @import("symlink.zig");
    _ = @import("aliases.zig");
    _ = @import("links.zig");
}
