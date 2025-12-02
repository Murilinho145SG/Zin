const std = @import("std");
const builtin = @import("builtin");

pub const LOG_COLOR_GREEN = "\x1b[32m";
pub const LOG_COLOR_RED = "\x1b[31m";
pub const LOG_COLOR_CYAN = "\x1b[36m";
pub const LOG_COLOR_RESET = "\x1b[0m";
pub const LOG_BG_MAGENTA = "\x1b[45m";

pub const LogFlags = packed struct {
    date: bool = true,
    time: bool = true,
    file: bool = false,
    line: bool = false,
    prefix: bool = false,
    debug: bool = false,
};

pub const Logger = struct {
    debug: bool,
    prefix: []const u8 = "",
    flags: LogFlags,

    pub fn init(flags: LogFlags) Logger {
        const os_tag = builtin.target.os.tag;

        const is_debug_mode = switch (os_tag) {
            .linux => false,
            .windows, .macos => true,
            else => true,
        };

        return .{ .debug = is_debug_mode, .flags = flags };
    }

    pub fn setPrefix(self: *Logger, prefix: []const u8) void {
        self.prefix = prefix;
        self.flags.prefix = true;
    }

    pub fn log(self: *Logger, comptime format: []const u8, args: anytype, return_addr: usize) void {
        if (self.flags.debug and !self.debug) {
            return;
        }

        const debug = std.debug;
        if (self.flags.prefix) {
            debug.print("[{s}] ", .{self.prefix});
        }
        if (self.flags.date or self.flags.time) {
            const now = std.time.timestamp();
            const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
            const year = epoch.getEpochDay().calculateYearDay().year;
            const day = epoch.getEpochDay().calculateYearDay().calculateMonthDay().day_index + 1;
            const month = epoch.getEpochDay().calculateYearDay().calculateMonthDay().month.numeric();
            const hour = epoch.getDaySeconds().getHoursIntoDay() - 3;
            const min = epoch.getDaySeconds().getMinutesIntoHour();
            const sec = epoch.getDaySeconds().getSecondsIntoMinute();

            if (self.flags.date) {
                debug.print("{}/{}/{} ", .{ year, month, day });
            }
            if (self.flags.time) {
                debug.print("{}:{}:{} ", .{ hour, min, sec });
            }
        }
        if (self.flags.file or self.flags.line) {
            const adjusted_addr = return_addr - 1;

            const debug_info = debug.getSelfDebugInfo() catch {
                debug.print("Error: can't possible loading debug info.\n", .{});
                return;
            };
            defer debug_info.deinit();

            const module = debug_info.getModuleForAddress(adjusted_addr) catch {
                debug.print("Error: Address {x} not founded in module.\n", .{adjusted_addr});
                return;
            };

            const symbol_info = module.getSymbolAtAddress(debug_info.allocator, adjusted_addr) catch {
                debug.print("Erro: can't possible resolve symbol for {x}.\n", .{adjusted_addr});
                return;
            };

            if (symbol_info.source_location) |li| {
                if (self.flags.file and self.flags.line) {
                    const filename = std.fs.path.basename(li.file_name);
                    debug.print("{s}:{d} ", .{ filename, li.line });
                }
                if (self.flags.file and !self.flags.line) {
                    const filename = std.fs.path.basename(li.file_name);
                    debug.print("{s} ", .{filename});
                }
            }
        }

        debug.print(format ++ "\n", args);
    }

    pub fn print(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(fmt, args, @returnAddress());
    }
};
