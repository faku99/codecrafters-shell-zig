const std = @import("std");

const ALLOCATOR = std.heap.page_allocator;

const Command = enum {
    echo,
    exit,
    type,
    unknown,
};

const ParsedInput = struct {
    command: Command,
    arguments: [][]const u8,
};

fn echoCmd(input: ParsedInput) void {
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

fn typeCmd(allocator: std.mem.Allocator, input: ParsedInput) !void {
    if (std.meta.stringToEnum(Command, input.arguments[1]) != null) {
        std.debug.print("{s} is a shell builtin\n", .{input.arguments[1]});
        return;
    }

    if (try findInPath(allocator, input.arguments[1])) |path| {
        std.debug.print("{s} is {s}/{s}\n", .{ input.arguments[1], path, input.arguments[1] });
    } else {
        std.debug.print("{s}: not found\n", .{input.arguments[1]});
    }
}

fn parseInput(allocator: std.mem.Allocator, input: []const u8) !ParsedInput {
    var tokens = std.ArrayList([]const u8).init(allocator);
    defer tokens.deinit();

    var it = std.mem.tokenizeAny(u8, input, " ");
    while (it.next()) |token| {
        try tokens.append(token);
    }

    const parsed_input = ParsedInput{
        .command = std.meta.stringToEnum(Command, tokens.items[0]) orelse .unknown,
        .arguments = try tokens.toOwnedSlice(),
    };

    return parsed_input;
}

pub fn main() !void {
    while (true) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("$ ", .{});

        const stdin = std.io.getStdIn().reader();
        var buffer: [1024]u8 = undefined;

        const user_input = try stdin.readUntilDelimiter(&buffer, '\n');
        const input = try parseInput(ALLOCATOR, user_input);

        switch (input.command) {
            .echo => echoCmd(input),
            .exit => std.process.exit(std.fmt.parseUnsigned(u8, input.arguments[1], 10) catch 1),
            .type => try typeCmd(ALLOCATOR, input),
            .unknown => std.debug.print("{s}: command not found\n", .{input.arguments[0]}),
        }
    }
}
