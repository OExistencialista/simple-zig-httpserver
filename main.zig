const std = @import("std");
const response = @import("response.zig");
const net = std.net;
pub fn main() !void {
    const address = "127.0.0.1";
    const port = 8080;
    var socket = net.StreamServer.init(.{});
    defer socket.deinit();

    try socket.listen(try net.Address.parseIp(address, port));

    while (true) {
        const conn = try socket.accept();
        std.debug.print("Connection open\n", .{});
        const new_thread = try std.Thread.spawn(.{.allocator = std.heap.page_allocator}, response.respond_request, .{conn});
        new_thread.join();
        std.debug.print("Connection close\n", .{});
        conn.stream.close();
    }
}