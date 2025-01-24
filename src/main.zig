const std = @import("std");

const Command = enum {
    exit,
    unknown,
};

const ParsedInput = struct {
    command: Command,
    arguments: [][]const u8,
};

fn handleCommand(input: ParsedInput) void {
    switch (input.command) {
        .exit => std.process.exit(std.fmt.parseUnsigned(u8, input.arguments[1], 10) catch 1),
        else => std.debug.print("{s}: command not found\n", .{input.arguments[0]}),
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
    const allocator = std.heap.page_allocator;

    while (true) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("$ ", .{});

        const stdin = std.io.getStdIn().reader();
        var buffer: [1024]u8 = undefined;

        const user_input = try stdin.readUntilDelimiter(&buffer, '\n');
        const command = try parseInput(allocator, user_input);

        handleCommand(command);
    }
}
