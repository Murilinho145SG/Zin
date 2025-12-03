# Zin

A simple and lightweight HTTP server library written in Zig.

> **Note**: This project is in an early stage and will soon support new features. The project is fully based on Golang HTTP routers.

## Features

- Easy to use routing (GET, POST)
- Context-based request handling
- Built-in logging
- Debug mode

## Installation

To use **Zin** in your project, you can add it as a module in your `build.zig`.

Assuming you have the library in a `lib/zin` directory or similar:

```zig
// build.zig

pub fn build(b: *std.Build) void {
    // ...

    const zin_mod = b.addModule("zin", .{
        .root_source_file = b.path("path/to/zin/lib/zin.zig"),
    });

    const exe = b.addExecutable(.{
        // ...
    });

    exe.root_module.addImport("zin", zin_mod);

    // ...
}
```

## Usage

Here is a simple example of how to create a server with **Zin**:

```zig
const std = @import("std");
const zin = @import("zin");

// Handler function
fn hello(ctx: *zin.Context) !void {
    ctx.string(.ok, "Hello from Zin!");
}

fn createUser(ctx: *zin.Context) !void {
    // You can access the request body via ctx.req
    ctx.string(.created, "User created");
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Initialize the engine
    var engine = zin.Engine.init(allocator);
    defer engine.deinit();

    // Define routes
    try engine.get("/hello", hello);
    try engine.post("/user", createUser);

    // Start the server
    // Port: 8080
    // Bind Address: null (defaults to 127.0.0.1)
    try engine.run(8080, null);
}
```

## API Reference

### Engine

- `init(allocator: std.mem.Allocator) Engine`: Initializes a new server engine.
- `deinit()`: Frees resources.
- `setMode(debug: bool)`: Enables or disables debug logging.
- `get(path: []const u8, handler: HandlerFunc)`: Registers a GET route.
- `post(path: []const u8, handler: HandlerFunc)`: Registers a POST route.
- `run(port: u16, bind: ?[]const u8)`: Starts the server.

### Context

- `status(code: http.Status)`: Sets the HTTP status code.
- `string(code: http.Status, content: []const u8)`: Sends a string response with a status code.
