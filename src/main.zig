const std = @import("std");

fn handleCommand(input: []const u8) void {
    std.debug.print("{s}: command not found\n", .{input});
}

pub fn main() !void {
    while (true) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("$ ", .{});

        const stdin = std.io.getStdIn().reader();
        var buffer: [1024]u8 = undefined;

        const user_input = try stdin.readUntilDelimiter(&buffer, '\n');

        handleCommand(user_input);
    }
}
