const std = @import("std");
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

        try respond_request(conn);
        conn.stream.close();
        std.debug.print("Connection close\n", .{});
    }
}

pub fn respond_request(conn: net.StreamServer.Connection) !void {
    const allocator = std.heap.page_allocator;
    const mimes = .{ .{ "html", "text/html" }, .{ "css", "text/css" }, .{ "map", "application/json" }, .{ "svg", "image/svg+xml" }, .{ "jpg", "image/jpg" }, .{ "png", "image/png" } };
    const resquest = try handle_request(conn, allocator);
    const file_path = resquest.path;
    var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    std.debug.print("\n{s}\n", .{file_path[1..]});

    const path = std.fs.realpath(file_path[1..file_path.len], &path_buffer) catch {
        return notfound(conn);
    };
    std.debug.print("\n{s}\n", .{path});
    const file = std.fs.openFileAbsolute(path, .{ .mode = .read_only }) catch {
        return notfound(conn);
    };
    defer file.close();

    var token_filepath = std.mem.tokenize(u8, path[0..], ".");

    _ = token_filepath.next();
    const extension = token_filepath.next();
    std.debug.print("\nextencao {s}\n", .{extension orelse "nao"});
    var content_type: []const u8 = "text/html";

    inline for (mimes) |kv| {
        if (std.mem.eql(u8, extension orelse " ", kv[0])) {
            content_type = kv[1];
        }
    }
    std.debug.print("\ntipo: {s}\n", .{content_type});
    const writer = conn.stream.writer();
    writer.print("HTTP/1.1 200 OK\r\nContent-Type: {s}\r\n\r\n", .{content_type}) catch |err| {
        std.log.err("Erro de conexão perdida: {any}\n", .{err});
        return err;
    };

    try send_file(writer, file, allocator);
}

fn handle_request(conn: net.StreamServer.Connection, alloc: std.mem.Allocator) !HttpRequest {
    const reader = conn.stream.reader();
    var buffer: [4096]u8 = undefined;
    const read_result = try reader.read(buffer[0..]);

    const http_request = try parse_http_request(buffer[0..read_result], alloc);
    std.debug.print("buffer {s}\n", .{buffer[0..200]});
    std.debug.print("method:{s} \npath:{s} \ndocument:{s} \n", .{ http_request.method, http_request.path, http_request.document });

    return http_request;
}

const HttpRequest = struct {
    method: []const u8,
    path: []const u8,
    document: []const u8,
};

fn notfound(conn: net.StreamServer.Connection) !void {
    try conn.stream.writeAll("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n");
}
fn send_file(writer: net.Stream.Writer, file: std.fs.File, alloc: std.mem.Allocator) !void {
    const buffer_size = 10_000_000;
    const file_buffer = try file.readToEndAlloc(alloc, buffer_size);
    defer alloc.free(file_buffer);

    _ = try writer.write(file_buffer[0..]);
}

fn parse_http_request(buffer: []const u8, alloc: std.mem.Allocator) !HttpRequest {
    var start: usize = 0;
    var index: usize = 0;
    var tokenizeItens = try alloc.alloc([]const u8, 4);
    var document: ?[]const u8 = null;
    var n: usize = 0;
    var lastOne: u8 = ' ';

    for (0..4) |_| {
        while (start < buffer.len) {
            index += 1;

            if (buffer[index] == ' ' or buffer[index] == '?') {
                if (lastOne == '?') {
                    document = buffer[start..index];
                } else tokenizeItens[n] = buffer[start..index];
                n += 1;
                lastOne = buffer[index];

                start = index + 1;
                break;
            }
        }
    }
    return HttpRequest{ .method = tokenizeItens[0], .path = tokenizeItens[1], .document = document orelse "" };
}
