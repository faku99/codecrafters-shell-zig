const std = @import("std");

const ALLOCATOR = std.heap.page_allocator;

const CommandError = error{
    NotFound,
};

const Builtin = enum {
    echo,
    exit,
    type,
};

const CommandType = enum {
    builtin,
    executable,
};

const CommandExe = union {
    builtin: Builtin,
    path: []const u8,
};

const Command = struct {
    type: CommandType,
    arguments: [][]const u8,
    exe: CommandExe,
};

fn echoCmd(input: Command) void {
    for (1..input.arguments.len) |i| {
        if (i > 1) std.debug.print(" ", .{});
        std.debug.print("{s}", .{input.arguments[i]});
    }
    std.debug.print("\n", .{});
}

fn findInPath(allocator: std.mem.Allocator, file: []const u8) !?[]const u8 {
    const path = try std.process.getEnvVarOwned(allocator, "PATH");
    var iter = std.mem.tokenizeAny(u8, path, ":");

    while (iter.next()) |directory| {
        var dir = std.fs.openDirAbsolute(directory, .{}) catch continue;
        defer dir.close();

        var exists = true;
        dir.access(file, .{}) catch |e| switch (e) {
            error.FileNotFound => exists = false,
            else => return e,
        };

        if (exists) {
            return try allocator.dupe(u8, directory);
        }
    }

    return null;
}

fn typeCmd(command: Command) void {
    const target = parseInput(ALLOCATOR, command.arguments[1]) catch {
        std.debug.print("{s}: not found\n", .{command.arguments[1]});
        return;
    };

    switch (target.type) {
        .builtin => std.debug.print("{s} is a shell builtin\n", .{target.arguments[0]}),
        .executable => std.debug.print("{s} is {s}\n", .{ target.arguments[0], target.exe.path }),
    }
}

fn parseInput(allocator: std.mem.Allocator, input: []const u8) !Command {
    var tokens = std.ArrayList([]const u8).init(allocator);
    defer tokens.deinit();

    var it = std.mem.tokenizeAny(u8, input, " ");
    while (it.next()) |token| {
        try tokens.append(token);
    }

    // Check if builtin
    if (std.meta.stringToEnum(Builtin, tokens.items[0])) |builtin| {
        return Command{
            .type = .builtin,
            .arguments = try tokens.toOwnedSlice(),
            .exe = CommandExe{ .builtin = builtin },
        };
    }

    // Check if executable
    if (try findInPath(allocator, tokens.items[0])) |directory| {
        var path = std.ArrayList(u8).init(allocator);
        defer path.deinit();

        try path.appendSlice(directory);
        try path.appendSlice("/");
        try path.appendSlice(tokens.items[0]);

        return Command{
            .type = .executable,
            .arguments = try tokens.toOwnedSlice(),
            .exe = CommandExe{
                .path = try path.toOwnedSlice(),
            },
        };
    }

    return CommandError.NotFound;
}

fn handleExecutable(command: Command) void {
    var child = std.process.Child.init(command.arguments, ALLOCATOR);
    child.stdout_behavior = .Pipe;

    child.spawn() catch {
        std.log.err("Error executing '{s}'\n", .{command.arguments[0]});
        return;
    };

    if (child.stdout) |stdout| {
        std.io.getStdOut().writeFileAll(stdout, .{}) catch |e| {
            std.log.err("Error: {s}\n", .{@typeName(@TypeOf(e))});
        };
    }

    _ = child.wait() catch |e| {
        std.log.err("Error: {s}\n", .{@typeName(@TypeOf(e))});
    };
}

fn handleBuiltin(command: Command) void {
    switch (command.exe.builtin) {
        .echo => echoCmd(command),
        .exit => std.process.exit(std.fmt.parseUnsigned(u8, command.arguments[1], 10) catch 1),
        .type => typeCmd(command),
    }
}

fn handleCommand(command: Command) void {
    switch (command.type) {
        .builtin => handleBuiltin(command),
        .executable => handleExecutable(command),
    }
}

pub fn main() !void {
    while (true) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("$ ", .{});

        const stdin = std.io.getStdIn().reader();
        var buffer: [1024]u8 = undefined;

        const user_input = try stdin.readUntilDelimiter(&buffer, '\n');

        const input = parseInput(ALLOCATOR, user_input) catch |e| switch (e) {
            CommandError.NotFound => {
                std.debug.print("{s}: not found\n", .{user_input});
                continue;
            },
            else => {
                std.log.err("error: {}\n", .{e});
                std.process.exit(1);
            },
        };

        handleCommand(input);
    }
}
