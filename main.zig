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
    const mimes = .{ 
        .{ "html", "text/html" }, 
        .{ "css", "text/css" }, 
        .{ "map", "application/json" }, 
        .{ "svg", "image/svg+xml" }, 
        .{ "jpg", "image/jpg" }, 
        .{ "png", "image/png" } 
        };
    const file_path = try handle_request(conn);
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


    const extension = token_filepath.next();
    std.debug.print("\nextencao {s}\n", .{extension orelse "nao"});
    var content_type: []const u8 = "text/html";
    inline for (mimes) |kv| {
        if (std.mem.eql(u8, extension orelse "" , kv[0])) {
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

fn handle_request(conn: net.StreamServer.Connection) ![]const u8 {
    const reader = conn.stream.reader();
    var buffer: [4096]u8 = undefined;
    const read_result = try reader.read(buffer[0..]);

    const http_request = try parse_http_request(buffer[0..read_result]);

    return http_request.path;
}

const HttpRequest = struct {
    method: []const u8,
    path: []const u8,
    version: []const u8,
};

fn parse_http_request(buffer: []const u8) !HttpRequest {
    var tokenizer = std.mem.tokenize(u8, buffer, " ");
    const method = tokenizer.next() orelse "GET";
    const path = tokenizer.next() orelse "/";
    const version = tokenizer.next() orelse "HTTP/1.1";
    std.debug.print("{s} {s} {s}", .{method, path, version});

    return HttpRequest{ .method = method, .path = path, .version = version };
}
fn notfound(conn: net.StreamServer.Connection) !void {
    try conn.stream.writeAll("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n");
}
fn send_file(writer: net.Stream.Writer, file: std.fs.File, alloc: std.mem.Allocator) !void{
    const buffer_size = 10_000_000;
    const file_buffer = try file.readToEndAlloc(alloc,buffer_size);
    defer alloc.free(file_buffer);
    
    _ = try writer.write(file_buffer[0..]);
    
    
    
}
