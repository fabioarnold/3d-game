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

pub const String = struct {
    pub const Handle = i32;
    pub const invalid:Handle = -1;

    var string: []u8 = undefined; // ony one for now lol

    pub fn alloc(len: usize) Handle {
        String.string = std.heap.wasm_allocator.alloc(u8, len) catch return String.invalid;
        return 0;
    }

    pub fn dealloc(handle: Handle) void {
        _ = handle;
        std.heap.wasm_allocator.free(string);
    }

    pub fn fromSlice(slice: []u8) Handle {
        string = slice;
        return 0;
    }

    pub fn get(handle: Handle) []u8 {
        _ = handle;
        return string;
    }
};
export fn allocString(len: usize) String.Handle {
    return String.alloc(len);
}
export fn deallocString(handle: String.Handle) void {
    String.dealloc(handle);
}
export fn getStringPtr(handle: String.Handle) [*]u8 {
    return String.get(handle).ptr;
}
export fn getStringLen(handle: String.Handle) usize {
    return String.get(handle).len;
}

pub extern fn isKeyDown(key: u32) bool;

pub extern fn inspectFloat(name_ptr: [*]const u8, name_len: usize, value_ptr: *f32) void;
pub extern fn inspectFloatRange(name_ptr: [*]const u8, name_len: usize, value_ptr: *f32, min: f32, max: f32) void;
pub extern fn inspectVec3(name_ptr: [*]const u8, name_len: usize, value_ptr: *f32) void;
