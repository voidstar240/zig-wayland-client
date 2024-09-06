const std = @import("std");
const protocol = @import("protocol.zig");

const toBytes = std.mem.toBytes;
const Stream = std.net.Stream;
const GenericWriter = std.io.GenericWriter;
const GenericReader = std.io.GenericReader;

const Fixed = enum(i32) {
    _,

    pub fn toDouble(val: Fixed) f64 {
        return @as(f64, @floatFromInt(@intFromEnum(val))) / 256.0;
    } 

    pub fn fromDouble(val: f64) Fixed {
        return @enumFromInt(@as(i32, @intFromFloat(val * 256.0)));
    } 

    pub fn toInt(val: Fixed) i24 {
        return @intFromEnum(val) / 256;
    }

    pub fn fromInt(val: i24) Fixed {
        return @enumFromInt(@as(i32, val) * 256);
    }
};

pub const Object = struct {
    id: u32,
    global: *WaylandState,

    pub fn sendRequest(self: Object, opcode: u16, args: anytype) !void {
        return self.global.sendRequest(self.id, opcode, args);
    }
};

pub const FD = std.posix.fd_t;

pub const WaylandState = struct {
    socket: Stream,
    write_buffer: [4096]u8,
    write_end: usize,
    read_buffer: [4096]u8 align(@alignOf(*anyopaque)),
    auto_flush: bool,
    next_id: u32,

    const Writer = GenericWriter(*WaylandState, Stream.WriteError, write);
    const Reader = GenericReader(Stream, Stream.ReadError, Stream.read);

    /// Creates a new Wayland global object.
    pub fn init(socket: Stream) WaylandState {
        return WaylandState {
            .socket = socket,
            .write_buffer = undefined,
            .write_end = 0,
            .read_buffer = undefined,
            .auto_flush = true,
            .next_id = 1,
        };
    }

    /// Writes the contents of the write_buffer to the socket.
    pub fn flush(self: *WaylandState) !void {
        var index: usize = 0;
        while (index < self.write_end) {
            index += try self.socket.write(
                self.write_buffer[index..self.write_end]
            );
        }
        self.write_end = 0;
    }

    /// Writes bytes to the buffer flushing if needed.
    pub fn write(self: *WaylandState, bytes: []const u8) !usize {
        if (self.write_end + bytes.len > self.write_buffer.len) {
            try self.flush();
            if (bytes.len > self.write_buffer.len)
                return self.socket.write(bytes);
        }

        const new_end = self.write_end + bytes.len;
        @memcpy(self.write_buffer[self.write_end..new_end], bytes);
        self.write_end = new_end;
        return bytes.len;
    }

    /// Gets a writer to the buffered socket stream.
    pub fn writer(self: *WaylandState) Writer {
        return .{ .context = self };
    }

    /// Writes a request to the wayland socket stream.
    pub fn sendRequest(
        self: *WaylandState,
        obj_id: u32,
        opcode: u16,
        args: anytype,
    ) !void {
        try writeRequestRaw(self.writer(), obj_id, opcode, args);
        if (self.auto_flush) {
            try self.flush();
        }
    }

    /// Gets a reader to the socket stream.
    pub fn reader(self: *WaylandState) Reader {
        return self.socket.reader();
    }

    /// Reads one event into the read buffer overwritting what was there
    /// previously. Returns a slice to the read buffer message. This slice is
    /// not owned.
    pub fn readEvent(self: *WaylandState) ![]const u8 {
        const len = try readEventRaw(self.reader(), &self.read_buffer);
        return self.read_buffer[0..len];
    }

    /// Gets an unused ID that can be allocated to a new object.
    pub fn nextObjectId(self: *WaylandState) u32 {
        defer self.next_id += 1;
        return self.next_id;
    }

    /// Creates the global wl_display object.
    pub fn create_display(self: *WaylandState) protocol.wl_display {
        return protocol.wl_display {
            .inner = Object {
                .id = self.nextObjectId(),
                .global = self,
            },
        };
    }
};

/// Gets the length of a request given args.
fn msgLength(args: anytype) u16 {
    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);
    if (args_info != .Struct) {
        @compileError(
            "expected tuple or struct argument, found " ++ @typeName(ArgsType)
        );
    }

    const fields = args_info.Struct.fields;
    if (fields.len > 20) {
        @compileError("20 arguments max are supported for wire format");
    }
    var len: u16 = 8;
    inline for (fields) |field| {
        const val = @field(args, field.name);
        switch (field.type) {
            []const u8 => {
                len += 4;
                len += @intCast(val.len);
                len += @intCast(@subWithOverflow(0, val.len).@"0" % 4);
            },
            [:0]const u8 => {
                len += 4;
                len += @intCast(val.len + 1);
                len += @intCast(@subWithOverflow(0, val.len + 1).@"0" % 4);
            },
            ?[:0]const u8 => {
                len += 4;
                if (val == null) continue;
                len += @intCast(val.len + 1);
                len += @intCast(@subWithOverflow(0, val.len + 1).@"0" % 4);
            },
            else => len += 4,
        }
    }
    return len;
}

const Header = packed struct(u64) {
    object_id: u32,
    opcode: u16,
    length: u16,
};

pub fn writeRequestRaw(
    writer: anytype,
    obj_id: u32,
    opcode: u16,
    args: anytype
) !void {
    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);
    if (args_info != .Struct) {
        @compileError("Not tuple or struct, found " ++ @typeName(ArgsType));
    }

    const fields = args_info.Struct.fields;
    if (fields.len > 20) {
        @compileError("20 arguments max are supported for wire format");
    }

    try writer.writeAll(&toBytes(obj_id));
    try writer.writeAll(&toBytes(opcode));
    try writer.writeAll(&toBytes(msgLength(args)));
    inline for (fields) |field| {
        const info = @typeInfo(field.type);
        const val = @field(args, field.name);
        switch (field.type) {
            i32, u32 => try writer.writeAll(&toBytes(val)),
            Fixed => try writer.writeAll(&toBytes(@as(i32, @intFromEnum(val)))),
            []const u8 => {
                try writer.writeAll(&toBytes(@as(u32, val.len)));
                try writer.writeAll(val);
                const pad = @subWithOverflow(0, val.len).@"0" % 4;
                for (0..pad) |_| {
                    try writer.writeAll(&[_]u8{0});
                }
            },
            [:0]const u8 => {
                try writer.writeAll(&toBytes(@as(u32, val.len + 1)));
                try writer.writeAll(val);
                try writer.writeAll(&[_]u8{0});
                const pad = @subWithOverflow(0, val.len + 1).@"0" % 4;
                for (0..pad) |_| {
                    try writer.writeAll(&[_]u8{0});
                }
            },
            ?[:0]const u8 => {
                if (val == null) {
                    try writer.writeAll(&toBytes(@as(u32, 0)));
                    continue;
                }
                try writer.writeAll(&toBytes(@as(u32, val.len + 1)));
                try writer.writeAll(val);
                try writer.writeAll(&[_]u8{0});
                const pad = @subWithOverflow(0, val.len + 1).@"0" % 4;
                for (0..pad) |_| {
                    try writer.writeAll(&[_]u8{0});
                }
            },
            *const Object, Object => {
                try writer.writeAll(&toBytes(val.id));
            },
            ?*const Object, ?Object => {
                try writer.writeAll(&toBytes(if (val) |o| o.id else 0));
            },
            else => switch (info) {
                .Pointer, .Struct => {
                    if (@hasField(field.type, "inner")) {
                        @compileError("No inner field on struct.");
                    }
                    const obj = val.inner;
                    if (@TypeOf(obj) != Object) {
                        @compileError("inner is not an Object.");
                    }
                    try writer.writeAll(&toBytes(obj.id));
                },
                .Optional => {
                    if (val) |interface| {
                        if (@hasField(@TypeOf(interface), "inner")) {
                            @compileError("No inner field on struct");
                        }
                        const obj = val.inner;
                        if (@TypeOf(obj) != Object) {
                            @compileError("inner is not an Object.");
                        }
                        try writer.writeAll(&toBytes(obj.id));
                    } else {
                        try writer.writeAll(&toBytes(@as(u32, 0)));
                    }
                },
                .Enum => |meta| {
                    if (meta.tag_type != i32 or meta.tag_type != u32) {
                        @compileError("Enum tag isn't u32/i32.");
                    }
                    try writer.writeAll(&toBytes(@intFromEnum(val)));
                },
                else => @compileError(
                    "Unrecognized type, " ++ @typeName(field.type)
                ),
            },
        }
    }
}

/// Reads one event into the provided buffer returning the length of the
/// message. If the buffer is too small to fit the event error.EventTooBig
/// is returned.
pub fn readEventRaw(
    reader: anytype,
    buffer: []align(@alignOf(*anyopaque)) u8
) !usize {
    if (buffer.len < 8) return error.EventTooBig;
    try reader.readNoEof(buffer[0..@sizeOf(Header)]);
    const header = @as(*const Header, @ptrCast(buffer));
    const len = header.length;
    if (buffer.len < len) return error.EventTooBig;
    try reader.readNoEof(buffer[@sizeOf(Header)..len]);
    return len;
}
