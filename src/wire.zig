const std = @import("std");
const root = @import("root.zig");

const assertObject = root.assertObject;

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

// TODO make more specific version errors
pub const RequestError = std.posix.SendMsgError || error.VersionError;

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
        i32 => return @enumFromInt(try decodeI32(bytes, start)),
        u32 => return @enumFromInt(try decodeU32(bytes, start)),
        else => @compileError(type_name ++ " tag must be i32 or u32.")
    }
}

/// Gets the length of array `len` rounded up 4 bytes.
pub fn arrayLen(len: u32) u32 {
    return (len + @sizeOf(u32) - 1) & ~(@sizeOf(u32) - 1);
}

/// Gets the number of padding bytes needed for array of `len`.
pub fn arrayPad(len: u32) u32 {
    return (@sizeOf(u32) - (len & @sizeOf(u32) - 1)) & (@sizeOf(u32) - 1);
}

pub fn sendRequestRaw(
    socket: std.posix.socket_t,
    object_id: u32,
    opcode: u16,
    comptime N: comptime_int,
    args: anytype,
    fds: anytype,
) RequestError!void {
    comptime if (N < 1) @compileError("N must be at least 1");
    var iovecs: [N]std.posix.iovec_const = undefined;
    var i: usize = 1;
    const zeros: [4]u8 = .{0} ** 4;

    const info = @typeInfo(@TypeOf(args));
    if (info != .Struct) @compileError("`args` must be struct");
    inline for (info.Struct.fields) |field| {
        const val = @field(args, field.name);
        switch (field.type) {
            i32, u32, Fixed => {
                iovecs[i].base = std.mem.asBytes(&val);
                iovecs[i].len = @sizeOf(i32);
                i += 1;
            },
            []const u8 => {
                if (val.len > 0) {
                    iovecs[i].base = val.ptr;
                    iovecs[i].len = val.len;
                    i += 1;
                }
                const pad = arrayPad(@intCast(val.len));
                if (pad > 0) {
                    iovecs[i].base = &zeros;
                    iovecs[i].len = pad;
                    i += 1;
                }
            },
            [:0]const u8 => {
                const len: u32 = @intCast(val.len + 1);
                iovecs[i].base = val.ptr;
                iovecs[i].len = len;
                i += 1;
                const pad = arrayPad(len);
                if (pad > 0) {
                    iovecs[i].base = &zeros;
                    iovecs[i].len = pad;
                    i += 1;
                }
            },
            ?[:0]const u8 => {
                if (val == null) {
                    continue;
                }
                const len: u32 = @intCast(val.len + 1);
                iovecs[i].base = val.ptr;
                iovecs[i].len = @intCast(len);
                i += 1;
                const pad = arrayPad(len);
                if (pad > 0) {
                    iovecs[i].base = &zeros;
                    iovecs[i].len = pad;
                    i += 1;
                }
            },
            else => {
                @compileError("Invalid arg type: " ++ @typeName(field.type));
            }
        }
    }

    var length: usize = @sizeOf(Header);
    for (1..i) |n| {
        length += iovecs[n].len;
    }
    const header = Header {
        .object_id = object_id,
        .opcode = opcode,
        .length = @intCast(length),
    };
    iovecs[0].base = std.mem.asBytes(&header);
    iovecs[0].len = @sizeOf(Header);

    var msg = std.posix.msghdr_const {
        .name = null,
        .namelen = 0,
        .iov = &iovecs,
        .iovlen = @intCast(i),
        .control = null,
        .controllen = 0,
        .flags = 0,
    };

    const fds_info = @typeInfo(@TypeOf(fds));
    if (fds_info != .Array) @compileError("`fds` must be an array.");
    var cmsg: cmsghdr(@TypeOf(fds)) = undefined;
    if (fds_info.Array.len != 0) {
        cmsg = .{
            .level = std.posix.SOL.SOCKET,
            .type = 0x01, // SCM_RIGHTS
            .data = fds,
        };
        msg.control = &cmsg;
        msg.controllen = @intCast(cmsg.len);
    }

    const sent = try std.posix.sendmsg(socket, &msg, 0);
    if (sent < header.length) {
        return std.posix.SendMsgError.SocketNotConnected;
    }
}

fn cmsghdr(comptime T: type) type {
    // `__CMSG_PADDING` macro from bits/socket.h
    const pad_len = (@sizeOf(usize) - (@sizeOf(T) & @sizeOf(usize) - 1))
                    & (@sizeOf(usize) - 1);

    // `struct cmsghdr` translation from bit/socket.h
    return extern struct {
        len: usize = @sizeOf(@This()) - pad_len,
        level: c_int,
        type: c_int,
        data: T,
        _pad: [pad_len]u8 align(1) = .{0} ** pad_len,
    };
}
