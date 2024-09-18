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
    /// previously. Returns an AnonymousEvent. The contained data slice is a
    /// reference to the internal read buffer and not owned.
    pub fn readEvent(self: *WaylandState) !AnonymousEvent {
        const head = try readEventRaw(self.reader(), &self.read_buffer);
        return AnonymousEvent {
            .object_id = head.object_id,
            .opcode = head.opcode,
            .arg_data = self.read_buffer[@sizeOf(Header)..head.length],
        };
    }

    /// Gets an unused ID that can be allocated to a new object.
    pub fn nextObjectId(self: *WaylandState) u32 {
        defer self.next_id += 1;
        return self.next_id;
    }

    /// Gets the global wl_display object.
    pub fn getDisplay(self: *WaylandState) protocol.wl_display {
        return protocol.wl_display {
            .id = self.nextObjectId(),
        };
    }
};

/// Throws a compile error if `ObjType` is not an object/interface.
pub fn assertObject(comptime ObjType: type) void {
    comptime {
        const name = @typeName(ObjType);
        const info = @typeInfo(ObjType);
        if (info != .Struct)
            @compileError(name ++ " is not an object. Not a struct.");

        var has_id = false;
        for (info.Struct.fields) |field| {
            if (std.mem.eql(u8, field.name, "id")) {
                has_id = true;
                if (field.type != u32)
                    @compileError(name ++ " is not an object. `id` not u32.");
            }
        }

        if (has_id == false)
            @compileError(name ++ " is not an object. Has no `id` field.");
    }
}

/// Converts `interface` into an Object.
pub fn objectFromInterface(interface: anytype) Object {
    comptime assertObject(@TypeOf(interface));
    return Object {
        .id = interface.id,
    };
}

/// Converts `object` to an interface with type `InterfaceType`.
pub fn interfaceFromObject(InterfaceType: type, object: Object) InterfaceType {
    comptime assertObject(InterfaceType);
    return InterfaceType {
        .id = object.id,
    };
}

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

const Header = packed struct(u64) {
    object_id: u32,
    opcode: u16,
    length: u16,
};

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
            else => switch (info) {
                .Struct => try wireWriteObject(writer, val),
                .Optional => try wireWriteObject(writer, val),
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
) !Header {
    if (buffer.len < 8) return error.EventTooBig;
    try reader.readNoEof(buffer[0..@sizeOf(Header)]);
    const header = @as(*const Header, @ptrCast(buffer));
    const len = header.length;
    if (buffer.len < len) return error.EventTooBig;
    try reader.readNoEof(buffer[@sizeOf(Header)..len]);
    return header.*;
}

pub const AnonymousEvent = struct {
    object_id: u32,
    opcode: u16,
    arg_data: []const u8,
};

/// Decodes the event into the passed struct Type. Note any slices in the struct
/// are not owned.
pub fn decodeEvent(
    event: AnonymousEvent,
    Type: type
) DecodeError!Type {
    const type_info = @typeInfo(Type);
    if (type_info != .Struct) {
        @compileError("Not tuple or struct, found " ++ @typeName(Type));
    }

    var out: Type = undefined;
    var index: usize = 0;
    const fields = type_info.Struct.fields;
    inline for (fields, 0..) |field, i| {
        const info = @typeInfo(field.type);
        const val_ptr = &@field(out, field.name);
        if (i == 0) {
            if (info != .Struct)
                @compileError("First field must be an object.");
            if (event.object_id == 0) return DecodeError.NullNonNullObject;
            val_ptr.id = event.object_id; 
            continue;
        }
        switch (field.type) {
            i32 => val_ptr.* = try wireDecodeI32(event.arg_data, &index),
            u32 => val_ptr.* = try wireDecodeU32(event.arg_data, &index),
            Fixed => val_ptr.* = try wireDecodeFixed(event.arg_data, &index),
            []const u8 => val_ptr.* = try wireDecodeArray(event.arg_data, &index),
            [:0]const u8 => val_ptr.* =
                (try wireDecodeString(event.arg_data, &index))
                    orelse return DecodeError.NullNonNullString,
            ?[:0]const u8 => val_ptr.* =
                try wireDecodeString(event.arg_data, &index),
            else => switch (info) {
                .Struct => val_ptr.* =
                    (try wireDecodeObject(event.arg_data, &index, field.type))
                        orelse return DecodeError.NullNonNullObject, 
                .Optional => val_ptr.* =
                    try wireDecodeObject(event.arg_data, &index, field.type),
                .Enum => val_ptr.* =
                    try wireDecodeEnum(event.arg_data, &index, field.type),
                else => @compileError("Invalid type, " ++ field.type),
            }
        }
    }
    return out;
}

pub const DecodeError = error {
    UnexpectedEnd,
    NullNonNullString,
    NullNonNullObject,
};

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
    var arr: []const u8 = @ptrCast(str.?);
    arr.len += 1;
    return wireWriteArray(writer, arr);
}

fn wireWriteObject(writer: anytype, object: anytype) !void {
    const ObjType = @TypeOf(object);
    const type_info = @typeInfo(ObjType);
    if (type_info == .Optional) {
        comptime assertObject(type_info.Optional.child);
        if (object == null)
            return wireWriteU32(writer, 0);
        return wireWriteU32(writer, object.?.id);
    }
    comptime assertObject(ObjType);
    return wireWriteU32(writer, object.id);
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

fn wireDecodeI32(bytes: []const u8, start: *usize) DecodeError!i32 {
    if (bytes[(start.*)..].len < @sizeOf(i32)) return DecodeError.UnexpectedEnd;
    defer start.* += @sizeOf(i32);
    return std.mem.bytesToValue(i32, bytes[(start.*)..]);
}

fn wireDecodeU32(bytes: []const u8, start: *usize) DecodeError!u32 {
    if (bytes[(start.*)..].len < @sizeOf(u32)) return DecodeError.UnexpectedEnd;
    defer start.* += @sizeOf(u32);
    return std.mem.bytesToValue(u32, bytes[(start.*)..]);
}

fn wireDecodeFixed(bytes: []const u8, start: *usize) DecodeError!Fixed {
    return @enumFromInt(try wireDecodeI32(bytes, start));
}

fn wireDecodeArray(bytes: []const u8, start: *usize) DecodeError![]const u8 {
    const len = try wireDecodeU32(bytes, start);
    const pad = @subWithOverflow(0, len).@"0" % 4;
    if (bytes[(start.*)..].len < len + pad) return DecodeError.UnexpectedEnd;
    defer start.* += len + pad;
    return bytes[(start.*)..(start.* + len)];
}

fn wireDecodeString(
    bytes: []const u8,
    start: *usize
) DecodeError!?[:0]const u8 {
    const arr = try wireDecodeArray(bytes, start);
    if (arr.len == 0) return null;
    var str: [:0]const u8 = @ptrCast(arr);
    str.len -= 1;
    return str;
}

fn wireDecodeObject(
    bytes: []const u8,
    start: *usize,
    ObjType: type
) DecodeError!?ObjType {
    comptime assertObject(ObjType);
    const id = try wireDecodeU32(bytes, start);
    if (id == 0) return null;
    return ObjType {
        .id = id,
    };
}

fn wireDecodeEnum(
    bytes: []const u8,
    start: *usize,
    EnumType: type
) DecodeError!EnumType {
    const type_name = @typeName(EnumType);
    const type_info = @typeInfo(EnumType);
    if (type_info != .Enum)
        @compileError(type_name ++ " is not an object. Not a struct.");

    switch (type_info.Enum.tag_type) {
        i32 => return @enumFromInt(try wireWriteI32(bytes, start)),
        u32 => return @enumFromInt(try wireWriteU32(bytes, start)),
        else => @compileError(type_name ++ " tag must be i32 or u32.")
    }
}
