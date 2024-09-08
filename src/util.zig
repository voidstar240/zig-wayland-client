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

const Header = packed struct(u64) {
    object_id: u32,
    opcode: u16,
    length: u16,
};

/// Gets the length of a request given args.
fn calcRequestLength(args: anytype) u16 {
    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);

    var len: u16 = 8;
    const fields = args_info.Struct.fields;
    inline for (fields) |field| {
        const val = @field(args, field.name);
        switch (field.type) {
            []const u8 => {
                len += @intCast(val.len);
                len += @intCast(@subWithOverflow(0, val.len).@"0" % 4);
            },
            [:0]const u8 => {
                len += @intCast(val.len + 1);
                len += @intCast(@subWithOverflow(0, val.len + 1).@"0" % 4);
            },
            ?[:0]const u8 => {
                if (val == null) continue;
                len += @intCast(val.len + 1);
                len += @intCast(@subWithOverflow(0, val.len + 1).@"0" % 4);
            },
            else => {},
        }
        len += 4;
    }
    return len;
}

/// Writes a request to `writer` from `object_id` with `opcode` and `args`.
/// Length is calculated from `args`.
pub fn writeRequestRaw(
    writer: anytype,
    object_id: u32,
    opcode: u16,
    args: anytype
) !void {
    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);
    if (args_info != .Struct)
        @compileError("Not tuple or struct, found " ++ @typeName(ArgsType));

    const header = Header {
        .object_id = object_id,
        .opcode = opcode,
        .length = calcRequestLength(args),
    };
    try wireWriteHeader(writer, header);
    const fields = args_info.Struct.fields;
    inline for (fields) |field| {
        const info = @typeInfo(field.type);
        const val = @field(args, field.name);
        const field_type_name = @typeName(field.type);
        switch (field.type) {
            i32 => try wireWriteI32(writer, val),
            u32 => try wireWriteU32(writer, val),
            Fixed => try wireWriteFixed(writer, val),
            []const u8 => try wireWriteArray(writer, val),
            [:0]const u8 => try wireWriteString(writer, val),
            ?[:0]const u8 => try wireWriteString(writer, val),
            Object => try wireWriteObject(writer, val),
            ?Object => try wireWriteObjectOptional(writer, val),
            else => switch (info) {
                .Struct => {
                    if (!@hasField(field.type, "inner")) {
                        @compileError("No inner field on struct.");
                    }
                    const obj = val.inner;
                    if (@TypeOf(obj) != Object) {
                        @compileError("inner is not an Object.");
                    }
                    try wireWriteObject(writer, obj);
                },
                .Optional => {
                    if (val) |interface| {
                        if (!@hasField(@TypeOf(interface), "inner")) {
                            @compileError("No inner field on struct.");
                        }
                        const obj = interface.inner;
                        if (@TypeOf(obj) != Object) {
                            @compileError("inner is not an Object.");
                        }
                        try wireWriteObject(writer, obj);
                    } else {
                        try wireWriteU32(writer, 0);
                    }
                },
                .Enum => try wireWriteEnum(writer, val),
                else => @compileError("Invalid type, " ++ field_type_name),
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

/// Decodes the event into the passed struct Type. Note any slices in the struct
/// are not owned.
pub fn decodeEvent(event: []const u8, Type: type) !Type {
    const type_info = @typeInfo(Type);
    if (type_info != .Struct) {
        @compileError("Not tuple or struct, found " ++ @typeName(Type));
    }

    var out: Type = undefined;

    var index: usize = 0;
    const fields = type_info.Struct.fields;
    inline for (fields) |field| {
        switch (field.type) {
            i32, u32, u16, Fixed => {
                const end = index + @sizeOf(field.type);
                if (end > event.len) return error.UnexpectedMessageEnd;
                const val = std.mem.bytesToValue(field.type, event[index..end]);
                index = end;
                @field(out, field.name) = val;
            },
            []const u8 => {
                var end = index + @sizeOf(u32);
                if (end > event.len) return error.UnexpectedMessageEnd;
                const len = std.mem.bytesToValue(u32, event[index..end]);
                index = end;
                end = index + @as(usize, @intCast(len));
                @field(out, field.name) = event[index..end];
                index = end;
                const pad = @subWithOverflow(0, index).@"0" % 4;
                index += pad;
            },
            [:0]const u8 => {
                var end = index + @sizeOf(u32);
                if (end > event.len) return error.UnexpectedMessageEnd;
                const len = std.mem.bytesToValue(u32, event[index..end]);
                index = end;
                if (len == 0) return error.UnexpectedNullString;
                end = index + @as(usize, @intCast(len));
                @field(out, field.name) = @ptrCast(event[index..(end - 1)]);
                index = end;
                const pad = @subWithOverflow(0, index).@"0" % 4;
                index += pad;
            },
            ?[:0]const u8 => {
                var end = index + @sizeOf(u32);
                if (end > event.len) return error.UnexpectedMessageEnd;
                const len = std.mem.bytesToValue(u32, event[index..end]);
                index = end;
                if (len == 0) {
                    @field(out, field.name) = null;
                    continue;
                }
                end = index + @as(usize, @intCast(len));
                @field(out, field.name) = @ptrCast(event[index..(end - 1)]);
                index = end;
                const pad = @subWithOverflow(0, index).@"0" % 4;
                index += pad;
            },
            else => @compileError("Invalid type, " ++ field.type),
        }
    }

    return out;
}

fn wireWriteHeader(writer: anytype, header: Header) !void {
    return writer.writeAll(&toBytes(header));
}

fn wireWriteI32(writer: anytype, num: i32) !void {
    return writer.writeAll(&toBytes(num));
}

fn wireWriteU32(writer: anytype, num: u32) !void {
    return writer.writeAll(&toBytes(num));
}

fn wireWriteFixed(writer: anytype, num: Fixed) !void {
    return wireWriteI32(writer, @intFromEnum(num));
}

fn wireWriteFD(writer: anytype, fd: FD) !void {
    // TODO send fd through ancillary data
    return wireWriteI32(writer, fd);
}

fn wireWriteArray(writer: anytype, arr: []const u8) !void {
    try wireWriteU32(writer, @intCast(arr.len));
    try writer.writeAll(arr);
    const pad = @subWithOverflow(0, arr.len).@"0" % 4;
    for (0..pad) |_| {
        try writer.writeAll(&[_]u8{0});
    }
}

fn wireWriteString(writer: anytype, str: ?[:0]const u8) !void {
    if (str == null) {
        return wireWriteU32(writer, 0);
    }
    const len = str.?.len + 1;
    try wireWriteU32(writer, @intCast(len));
    try writer.writeAll(str.?[0..len]);
    const pad = @subWithOverflow(0, len).@"0" % 4;
    for (0..pad) |_| {
        try writer.writeAll(&[_]u8{0});
    }
}

fn wireWriteObject(writer: anytype, object: anytype) !void {
    const type_name = @typeName(@TypeOf(object));
    const type_info = @typeInfo(@TypeOf(object));
    if (type_info != .Struct)
        @compileError(type_name ++ " is not an object. Not a struct.");
    if (!@hasField(object, "id"))
        @compileError(type_name ++ " is not an object. Has no `id` field.");
    if (@TypeOf(object.id) != u32)
        @compileError(type_name ++ " is not an object. `id` not u32.");

    return wireWriteU32(writer, object.id);
}

fn wireWriteObjectOptional(writer: anytype, object: anytype) !void {
    if (object == null)
        return wireWriteU32(writer, 0);
    return wireWriteObject(writer, object.?);
}

fn wireWriteEnum(writer: anytype, enum_: anytype) !void {
    const type_name = @typeName(@TypeOf(enum_));
    const type_info = @typeInfo(@TypeOf(enum_));
    if (type_info != .Enum)
        @compileError(type_name ++ " is not an object. Not a struct.");
    
    switch (type_info.Enum.tag_type) {
        i32 => return wireWriteI32(writer, @intFromEnum(enum_)),
        u32 => return wireWriteU32(writer, @intFromEnum(enum_)),
        else => @compileError(type_name ++ " tag must be i32 or u32.")
    }
}
