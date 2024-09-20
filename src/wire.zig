const std = @import("std");
const root = @import("root.zig");

const assertObject = root.assertObject;
const toBytes = std.mem.toBytes;

pub const Fixed = enum(i32) {
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

pub const FD = std.posix.fd_t;

pub const Object = struct {
    id: u32,
};

pub const AnonymousEvent = struct {
    self: Object,
    opcode: u16,
    arg_data: []const u8,
};

pub const DecodeError = error {
    UnexpectedEnd,
    NullNonNullString,
    NullNonNullObject,
};

pub const Header = packed struct(u64) {
    object_id: u32,
    opcode: u16,
    length: u16,
};

/// Writes a request to `writer` from `object_id` with `opcode` and `args`.
/// Length is calculated from `args`.
pub fn writeRequest(
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
    try writeHeader(writer, header);
    const fields = args_info.Struct.fields;
    inline for (fields) |field| {
        const info = @typeInfo(field.type);
        const val = @field(args, field.name);
        const field_type_name = @typeName(field.type);
        switch (field.type) {
            i32 => try writeI32(writer, val),
            u32 => try writeU32(writer, val),
            Fixed => try writeFixed(writer, val),
            []const u8 => try writeArray(writer, val),
            [:0]const u8 => try writeString(writer, val),
            ?[:0]const u8 => try writeString(writer, val),
            else => switch (info) {
                .Struct => try writeObject(writer, val),
                .Optional => try writeObject(writer, val),
                .Enum => try writeEnum(writer, val),
                else => @compileError("Invalid type, " ++ field_type_name),
            },
        }
    }
}

/// Reads one event into the provided buffer returning the length of the
/// message. If the buffer is too small to fit the event error.EventTooBig
/// is returned.
pub fn readEvent(
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
            if (event.self.id == 0) return DecodeError.NullNonNullObject;
            val_ptr.id = event.self.id; 
            continue;
        }
        switch (field.type) {
            i32 => val_ptr.* = try decodeI32(event.arg_data, &index),
            u32 => val_ptr.* = try decodeU32(event.arg_data, &index),
            Fixed => val_ptr.* = try decodeFixed(event.arg_data, &index),
            []const u8 => val_ptr.* = try decodeArray(event.arg_data, &index),
            [:0]const u8 => val_ptr.* =
                (try decodeString(event.arg_data, &index))
                    orelse return DecodeError.NullNonNullString,
            ?[:0]const u8 => val_ptr.* =
                try decodeString(event.arg_data, &index),
            else => switch (info) {
                .Struct => val_ptr.* =
                    (try decodeObject(event.arg_data, &index, field.type))
                        orelse return DecodeError.NullNonNullObject, 
                .Optional => val_ptr.* =
                    try decodeObject(event.arg_data, &index, field.type),
                .Enum => val_ptr.* =
                    try decodeEnum(event.arg_data, &index, field.type),
                else => @compileError("Invalid type, " ++ field.type),
            }
        }
    }
    return out;
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

fn writeHeader(writer: anytype, header: Header) !void {
    return writer.writeAll(&toBytes(header));
}

fn writeI32(writer: anytype, num: i32) !void {
    return writer.writeAll(&toBytes(num));
}

fn writeU32(writer: anytype, num: u32) !void {
    return writer.writeAll(&toBytes(num));
}

fn writeFixed(writer: anytype, num: Fixed) !void {
    return writeI32(writer, @intFromEnum(num));
}

fn writeFD(writer: anytype, fd: FD) !void {
    // TODO send fd through ancillary data
    return writeI32(writer, fd);
}

fn writeArray(writer: anytype, arr: []const u8) !void {
    try writeU32(writer, @intCast(arr.len));
    try writer.writeAll(arr);
    const pad = @subWithOverflow(0, arr.len).@"0" % 4;
    for (0..pad) |_| {
        try writer.writeAll(&[_]u8{0});
    }
}

fn writeString(writer: anytype, str: ?[:0]const u8) !void {
    if (str == null) {
        return writeU32(writer, 0);
    }
    var arr: []const u8 = @ptrCast(str.?);
    arr.len += 1;
    return writeArray(writer, arr);
}

fn writeObject(writer: anytype, object: anytype) !void {
    const ObjType = @TypeOf(object);
    const type_info = @typeInfo(ObjType);
    if (type_info == .Optional) {
        comptime assertObject(type_info.Optional.child);
        if (object == null)
            return writeU32(writer, 0);
        return writeU32(writer, object.?.id);
    }
    comptime assertObject(ObjType);
    return writeU32(writer, object.id);
}

fn writeEnum(writer: anytype, enum_: anytype) !void {
    const type_name = @typeName(@TypeOf(enum_));
    const type_info = @typeInfo(@TypeOf(enum_));
    if (type_info != .Enum)
        @compileError(type_name ++ " is not an object. Not a struct.");
    
    switch (type_info.Enum.tag_type) {
        i32 => return writeI32(writer, @intFromEnum(enum_)),
        u32 => return writeU32(writer, @intFromEnum(enum_)),
        else => @compileError(type_name ++ " tag must be i32 or u32.")
    }
}

fn decodeI32(bytes: []const u8, start: *usize) DecodeError!i32 {
    if (bytes[(start.*)..].len < @sizeOf(i32)) return DecodeError.UnexpectedEnd;
    defer start.* += @sizeOf(i32);
    return std.mem.bytesToValue(i32, bytes[(start.*)..]);
}

fn decodeU32(bytes: []const u8, start: *usize) DecodeError!u32 {
    if (bytes[(start.*)..].len < @sizeOf(u32)) return DecodeError.UnexpectedEnd;
    defer start.* += @sizeOf(u32);
    return std.mem.bytesToValue(u32, bytes[(start.*)..]);
}

fn decodeFixed(bytes: []const u8, start: *usize) DecodeError!Fixed {
    return @enumFromInt(try decodeI32(bytes, start));
}

fn decodeArray(bytes: []const u8, start: *usize) DecodeError![]const u8 {
    const len = try decodeU32(bytes, start);
    const pad = @subWithOverflow(0, len).@"0" % 4;
    if (bytes[(start.*)..].len < len + pad) return DecodeError.UnexpectedEnd;
    defer start.* += len + pad;
    return bytes[(start.*)..(start.* + len)];
}

fn decodeString(
    bytes: []const u8,
    start: *usize
) DecodeError!?[:0]const u8 {
    const arr = try decodeArray(bytes, start);
    if (arr.len == 0) return null;
    var str: [:0]const u8 = @ptrCast(arr);
    str.len -= 1;
    return str;
}

fn decodeObject(
    bytes: []const u8,
    start: *usize,
    ObjType: type
) DecodeError!?ObjType {
    comptime assertObject(ObjType);
    const id = try decodeU32(bytes, start);
    if (id == 0) return null;
    return ObjType {
        .id = id,
    };
}

fn decodeEnum(
    bytes: []const u8,
    start: *usize,
    EnumType: type
) DecodeError!EnumType {
    const type_name = @typeName(EnumType);
    const type_info = @typeInfo(EnumType);
    if (type_info != .Enum)
        @compileError(type_name ++ " is not an object. Not a struct.");

    switch (type_info.Enum.tag_type) {
        i32 => return @enumFromInt(try writeI32(bytes, start)),
        u32 => return @enumFromInt(try writeU32(bytes, start)),
        else => @compileError(type_name ++ " tag must be i32 or u32.")
    }
}
