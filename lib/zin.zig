const std = @import("std");
const http = std.http;
const net = std.net;
const logger = @import("logger.zig");
var log = logger.Logger.init(.{});
var debugLog = logger.Logger.init(.{
    .date = false,
    .time = false,
    .debug = true,
});

pub const Context = struct {
    req: *http.Server.Request,
    allocator: std.mem.Allocator,
    status_header: http.Status = .ok,
    body: []const u8 = "",
    remote_ip: net.Ip4Address,

    pub fn status(self: *Context, code: http.Status) void {
        self.status_header = code;
    }

    fn write(self: *Context, content: []const u8) void {
        self.body = content;
    }

    pub fn string(self: *Context, code: http.Status, content: []const u8) void {
        self.status(code);
        self.write(content);
    }
};

pub const DebugMode = true;
pub const ReleaseMode = false;
pub const HandlerFunc = *const fn (ctx: *Context) anyerror!void;

pub const Engine = struct {
    routes: std.StringHashMap(HandlerFunc),
    allocator: std.mem.Allocator,
    debug_mode: bool = true,

    pub fn init(allocator: std.mem.Allocator) Engine {
        log.setPrefix("ZIN");
        debugLog.setPrefix("ZIN-debug");
        debugLog.debug = true;
        return .{ .allocator = allocator, .routes = std.StringHashMap(HandlerFunc).init(allocator) };
    }

    pub fn deinit(self: *Engine) void {
        self.routes.deinit();
    }

    pub fn setMode(self: *Engine, debug: bool) void {
        self.debug_mode = debug;
        debugLog.debug = debug;
    }

    pub fn get(self: *Engine, path: []const u8, handler: HandlerFunc) !void {
        const key = try std.fmt.allocPrint(self.allocator, "GET {s}", .{path});
        try self.route(key, handler);
    }

    pub fn post(self: *Engine, path: []const u8, handler: HandlerFunc) !void {
        const key = try std.fmt.allocPrint(self.allocator, "POST {s}", .{path});
        try self.route(key, handler);
    }

    fn route(self: *Engine, path: []const u8, handler: HandlerFunc) !void {
        const path_copy = try self.allocator.dupe(u8, path);
        debugLog.print("{s}", .{path_copy});
        try self.routes.put(path_copy, handler);
    }

    fn handleConnection(self: *Engine, connection: net.Server.Connection) !void {
        defer connection.stream.close();

        var read_buf: [4096]u8 = undefined;
        var write_buf: [4096]u8 = undefined;

        var client_reader_impl = connection.stream.reader(&read_buf);
        var client_writer_impl = connection.stream.writer(&write_buf);

        var http_server = http.Server.init(&client_reader_impl.interface_state, &client_writer_impl.interface);

        var request_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer request_arena.deinit();
        const arena = request_arena.allocator();

        var req = http_server.receiveHead() catch |err| {
            if (err != error.HttpConnectionClosing) {
                std.debug.print("Erro Headers: {}\n", .{err});
            }
            return;
        };

        const method_path = try std.fmt.allocPrint(arena, "{s} {s}", .{ @tagName(req.head.method), req.head.target });
        defer arena.free(method_path);

        const start = std.time.nanoTimestamp();

        const client_addr = connection.address;
        const client_addr_data = client_addr.any.data;
        const client_ip = try std.fmt.allocPrint(arena, "{d}.{d}.{d}.{d}", .{ client_addr_data[2], client_addr_data[3], client_addr_data[4], client_addr_data[5] });

        var ctx = Context{ .req = &req, .allocator = arena, .body = "", .remote_ip = client_addr.in };
        if (self.routes.get(method_path)) |handler| {
            try handler(&ctx);
        } else {
            ctx.string(.not_found, "Not found");
        }

        try req.respond(ctx.body, .{ .status = ctx.status_header });

        const end = std.time.nanoTimestamp();
        const elapsed_ns: i128 = end - start;
        const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;

        const code = @intFromEnum(ctx.status_header);
        var colorCode = logger.LOG_COLOR_GREEN;
        if (code >= 400) {
            colorCode = logger.LOG_COLOR_RED;
        }
        log.print("| {s}{d}{s} |  {d}ms |   {s} |   {s} \"{s}\"", .{ colorCode, code, logger.LOG_COLOR_RESET, elapsed_ms, client_ip, @tagName(req.head.method), req.head.target });
    }

    pub fn run(self: *Engine, port: u16, bind: ?[]const u8) !void {
        const bind_addrs = bind orelse "127.0.0.1";
        const address = try net.Address.parseIp4(bind_addrs, port);
        var server = try address.listen(.{ .reuse_address = true });
        defer server.deinit();

        debugLog.print("Listening and serving HTTP on {s}:{d}", .{ bind_addrs, port });

        while (true) {
            const connection = try server.accept();

            const thread = try std.Thread.spawn(.{}, handleConnection, .{ self, connection });
            thread.detach();
        }
    }
};
