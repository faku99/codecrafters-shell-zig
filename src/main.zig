const std = @import("std");

const CommandError = error{
    NotFound,
};

const ExternalCommand = struct {
    program: []const u8,
    args: []const []const u8,
};

const Command = union(enum) {
    exit: ?u8,
    echo: []const u8,
    type: []const u8,
    unknown: []const u8,
    external: ExternalCommand,
    // pwd,
    // cd: ?[]const u8,

    fn parse(input: []const u8, allocator: std.mem.Allocator) !Command {
        var args = std.mem.splitSequence(u8, input, " ");
        const first = args.next() orelse return error.NotFound;

        if (std.mem.eql(u8, first, "exit")) {
            if (args.next()) |exit_code| {
                return Command{ .exit = std.fmt.parseUnsigned(u8, exit_code, 10) catch null };
            } else {
                return Command{ .exit = null };
            }
        } else if (std.mem.eql(u8, first, "echo")) {
            return Command{ .echo = input[5..] };
        } else if (std.mem.eql(u8, first, "type")) {
            return Command{ .type = input[5..] };
            // } else if (std.mem.eql(u8, first, "pwd")) {
            //     return Command.pwd;
            // } else if (std.mem.eql(u8, first, "cd")) {
            //     return Command{ .cd = args.next() };
        } else {
            var args_list = std.ArrayList([]const u8).init(allocator);
            try args_list.append(first);
            while (args.next()) |arg| {
                try args_list.append(arg);
            }
            return Command{ .external = ExternalCommand{ .program = first, .args = try args_list.toOwnedSlice() } };
        }
    }
};

fn isBuiltin(cmd: []const u8) bool {
    const builtins = [_][]const u8{ "exit, echo", "type" };
    for (builtins) |builtin| {
        if (std.mem.eql(u8, cmd, builtin)) return true;
    }
    return false;
}

fn findExecutable(executable: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    const path_var = try std.process.getEnvVarOwned(allocator, "PATH");
    var iter = std.mem.tokenizeAny(u8, path_var, ":");

    while (iter.next()) |directory| {
        const path = try std.fs.path.join(allocator, &[_][]const u8{ directory, executable });
        defer allocator.free(path);

        const file = std.fs.openFileAbsolute(path, .{ .mode = .read_only }) catch {
            continue;
        };
        defer file.close();

        const mode = file.mode() catch {
            continue;
        };

        const is_executable = mode & 0b001 != 0;
        if (!is_executable) {
            continue;
        }

        return try allocator.dupe(u8, path);
    }

    return null;
}

fn handleExternalCommand(command: ExternalCommand, allocator: std.mem.Allocator) !void {
    if (try findExecutable(command.args[0], allocator) != null) {
        var child = std.process.Child.init(command.args, allocator);
        const term = try child.spawnAndWait();

        switch (term) {
            .Exited => |code| {
                if (code != 0) {
                    std.debug.print("Program exited with non-zero status code: {d}\n", .{code});
                }
            },
            else => std.debug.print("Program terminated abnormally\n", .{}),
        }
    } else {
        std.debug.print("{s}: command not found\n", .{command.args[0]});
    }
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // Use GPA to detect memory leaks
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer switch (gpa.deinit()) {
        .leak => @panic("Memory leak"),
        .ok => {},
    };

    while (true) {
        try stdout.print("$ ", .{});

        const stdin = std.io.getStdIn().reader();
        var buffer: [1024]u8 = undefined;
        const user_input = try stdin.readUntilDelimiter(&buffer, '\n');

        if (user_input.len == 0) continue;

        const command = try Command.parse(user_input, allocator);
        switch (command) {
            .exit => |exit_code| {
                std.process.exit(exit_code orelse 0);
            },
            .echo => |text| {
                try stdout.print("{s}\n", .{text});
            },
            .type => |cmd| {
                if (isBuiltin(cmd)) {
                    std.debug.print("{s} is a shell builtin\n", .{cmd});
                } else if (try findExecutable(cmd, allocator)) |path| {
                    std.debug.print("{s} is {s}\n", .{ cmd, path });
                } else {
                    std.debug.print("{s}: not found\n", .{cmd});
                }
            },
            .external => |ext| {
                try handleExternalCommand(ext, allocator);
            },
            else => {},
        }
    }
}
