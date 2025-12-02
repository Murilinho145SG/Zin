const std = @import("std");
const http = std.http;
const net = std.net;

pub const Context = struct {
    req: *http.Server.Request,
    allocator: std.mem.Allocator,
};

pub const HandlerFunc = *const fn (ctx: *Context) anyerror!void;

pub const Engine = struct {
    routes: std.StringHashMap(HandlerFunc),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Engine {
        return .{ .allocator = allocator, .routes = std.StringHashMap(HandlerFunc).init(allocator) };
    }

    pub fn deinit(self: *Engine) void {
        self.routes.deinit();
    }
    
    pub fn route(self: *Engine, path: []const u8, handler: HandlerFunc) !void {
        const path_copy = try self.allocator.dupe(u8, path);
        try self.routes.put(path_copy, handler);
    }

    pub fn run(self: *Engine, port: u16, bind: ?[]const u8) !void {
        const bind_addrs = bind orelse "127.0.0.1";
        const address = try net.Address.parseIp4(bind_addrs, port);
        var server = try address.listen(.{ .reuse_address = true });
        defer server.deinit();
        
        std.debug.print("Listening on http://{s}:{}\n", .{bind_addrs, port});
        
        while (true) {
            var connection = try server.accept();
            defer connection.stream.close();
            
            var read_buf: [4096]u8 = undefined;
            var write_buf: [4096]u8 = undefined;
            
            var client_reader_impl = connection.stream.reader(&read_buf);
            var client_writer_impl = connection.stream.writer(&write_buf);
            
            var http_server = http.Server.init(&client_reader_impl.interface_state, &client_writer_impl.interface);
            
            var request_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer request_arena.deinit();
            const arena = request_arena.allocator();
            
            var req = try http_server.receiveHead();
            
            if (self.routes.get(req.head.target)) |handler| {
                var ctx = Context{ .req = &req, .allocator = arena };
                try handler(&ctx);
            } else {
                try req.respond("404 Not Found", .{ .status = .not_found });
            }            
        }
    }
};
