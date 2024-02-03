const std = @import("std");

extern fn wasm_log_write(ptr: [*]const u8, len: usize) void;

extern fn wasm_log_flush() void;

const WriteError = error{};
const LogWriter = std.io.Writer(void, WriteError, writeLog);

fn writeLog(_: void, msg: []const u8) WriteError!usize {
    wasm_log_write(msg.ptr, msg.len);
    return msg.len;
}

/// Overwrite default log handler
pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = switch (message_level) {
        .err => "error",
        .warn => "warning",
        .info => "info",
        .debug => "debug",
    };
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";

    (LogWriter{ .context = {} }).print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;

    wasm_log_flush();
}

pub extern fn isKeyDown(key: u32) bool;

pub extern fn inspectFloat(name_ptr: [*]const u8, name_len: usize, value_ptr: *f32) void;
pub extern fn inspectFloatRange(name_ptr: [*]const u8, name_len: usize, value_ptr: *f32, min: f32, max: f32) void;
pub extern fn inspectVec3(name_ptr: [*]const u8, name_len: usize, value_ptr: *f32) void;
