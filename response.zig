const std = @import("std");
const net = std.net;

pub fn respond_request(conn: net.StreamServer.Connection) !void {
    const allocator = std.heap.page_allocator;
    const request = try handle_request(conn, allocator);
    const s = parse_http_method(request.method) orelse {
        std.debug.print("metodo vazio", .{});
        return;
    };
    std.debug.print("{}\n{s}\n\n{s}\n\n", .{ s, request.path, request.form });
    switch (s) {
        .GET => {
            GET_response(conn, &request, allocator) catch |err| {
                return err;
            };
        },
        else => {
            try ok(conn);
        },
    }
}

pub fn ok(conn: net.StreamServer.Connection) !void {
    const writer = conn.stream.writer();

    _ = try writer.write("HTTP/1.1 204 OK\r\n\r\n");
}

fn notfound(conn: net.StreamServer.Connection) !void {
    try conn.stream.writeAll("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n");
}
fn send_file(writer: net.Stream.Writer, file: std.fs.File, alloc: std.mem.Allocator) !void {
    const buffer_size = 10_000_000;
    const file_buffer = try file.readToEndAlloc(alloc, buffer_size);
    defer alloc.free(file_buffer);

    _ = try writer.write(file_buffer[0..]);
}

const HttpMethod = enum {
    GET,
    POST,
    PUT,
    DELETE,
};

fn parse_http_method(methodS: []const u8) ?HttpMethod {
    var methodU: ?HttpMethod = null;
    const methodMap = .{
        .{ "GET", .GET },
        .{ "POST", .POST },
        .{ "PUT", .PUT },
        .{ "DELETE", .DELETE },
    };
    inline for (methodMap) |method| {
        if (std.mem.eql(u8, method[0], methodS)) {
            methodU = method[1];
        }
    }
    return methodU;
}

fn GET_response(conn: net.StreamServer.Connection, resquest: *const HttpRequest, allocator: std.mem.Allocator) !void {
    const mimes = .{ .{ "html", "text/html" }, .{ "css", "text/css" }, .{ "map", "application/json" }, .{ "svg", "image/svg+xml" }, .{ "jpg", "image/jpg" }, .{ "png", "image/png" } };
    std.debug.print("\n hiiii {s}\n", .{resquest.path});
    const file_path = resquest.path;

    std.debug.print("\n\n`{s}\n\n", .{file_path});
    var token_filepath = std.mem.tokenize(u8, file_path[0..], ".");

    std.debug.print("{s}\n", .{token_filepath.next().?});
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

    const file = get_file(file_path, allocator) catch |err| {
        std.debug.print("\n\nerro {any}\n\n", .{err});
        return notfound(conn);
    };
    defer file.close();

    try send_file(writer, file, allocator);
}

pub fn handle_request(conn: std.net.StreamServer.Connection, alloc: std.mem.Allocator) !HttpRequest {
    const reader = conn.stream.reader();
    var buffer: [4096]u8 = undefined;
    const read_result = try reader.read(buffer[0..]);

    const http_request = try parse_http_request(buffer[0..read_result], alloc);
    //std.debug.print("buffer {s}\n", .{buffer[0..]});
    //std.debug.print("method:{s} \npath:{s} \ndocument:{s} \n", .{ http_request.method, http_request.path, http_request.form });

    return http_request;
}

pub const HttpRequest = struct {
    method: []const u8,
    path: []const u8,
    form: []const u8,
};

fn parse_http_request(buffer: []const u8, alloc: std.mem.Allocator) !HttpRequest {
    var start: usize = 0;
    var index: usize = 0;
    var tokenizeItens = try alloc.alloc([]const u8, 4);

    var form: ?[]const u8 = null;
    var n: usize = 0;
    var lastOne: u8 = ' ';

    for (0..4) |_| {
        while (start < buffer.len) {
            index += 1;

            if (buffer[index] == ' ' or buffer[index] == '?') {
                if (lastOne == '?') {
                    form = buffer[start..index];
                } else tokenizeItens[n] = buffer[start..index];
                n += 1;
                lastOne = buffer[index];

                start = index + 1;
                break;
            }
        }
    }
    return HttpRequest{ .method = tokenizeItens[0], .path = tokenizeItens[1], .form = form orelse "" };
}
fn get_file(path: []const u8, allocator: std.mem.Allocator) !std.fs.File {
    var path_buffer = try allocator.alloc([std.fs.MAX_PATH_BYTES]u8, 1);

    const real_path = std.fs.realpath(path[1..], &path_buffer[0]) catch |err| {
        return err;
    };

    // Open the file
    const file = try std.fs.openFileAbsolute(real_path[0..], .{ .mode = .read_only });
    return file;
}
