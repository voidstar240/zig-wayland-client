const std = @import("std");
const root = @import("root.zig");

const assertInterface = root.assertInterface;

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

pub const AnonymousEvent = struct {
    self_id: u32,
    opcode: u16,
    fds_len: u8,
    fds: [4]FD,
    arg_data: []const u8,
};

// TODO make more specific version errors
pub const RequestError = std.posix.SendMsgError || error { VersionError, };

pub const DecodeError = error {
    UnexpectedEnd,
    NullNonNullString,
    NullNonNullObject,
    ExpectedFD,
};

pub const Header = packed struct(u64) {
    object_id: u32,
    opcode: u16,
    length: u16,
};

pub const EventField = struct {
    name: []const u8,
    field_type: Type,
    
    pub const Type = enum {
        int,
        uint,
        fixed,
        array,
        fd,
        string,
        string_opt,
        object,
        object_opt,
        enum_,
    };
};

/// Decodes the event into the passed struct Type. Note any slices in the struct
/// are not owned.
pub fn decodeEvent(
    event: AnonymousEvent,
    Type: type,
    comptime fields: []const EventField,
) DecodeError!Type {
    const type_info = @typeInfo(Type);
    if (type_info != .Struct) {
        @compileError("Not tuple or struct, found " ++ @typeName(Type));
    }

    var out: Type = undefined;

    if (event.self_id == 0) return DecodeError.NullNonNullObject;
    assertInterface(@TypeOf(out.self));
    out.self = .{ .id = event.self_id, };

    const data = event.arg_data;
    var i: usize = 0;
    var fd_n: usize = 0;
    inline for (fields) |field| {
        const ptr = &@field(out, field.name);
        switch (field.field_type) {
            .int => ptr.* = try decodeI32(data, &i),
            .uint => ptr.* = try decodeU32(data, &i),
            .fixed => ptr.* = try decodeFixed(data, &i),
            .array => ptr.* = try decodeArray(data, &i),
            .fd => {
                if (fd_n >= event.fds_len) return DecodeError.ExpectedFD;
                ptr.* = event.fds[fd_n];
                fd_n += 1;
            },
            .string => ptr.* = try decodeString(data, &i) orelse
                return DecodeError.NullNonNullString,
            .string_opt => ptr.* = try decodeString(data, &i),
            .object => ptr.* = try decodeInterface(data, &i, @TypeOf(ptr.*))
                orelse return DecodeError.NullNonNullObject,
            .object_opt => ptr.* = try decodeInterface(
                data,
                &i,
                @typeInfo(@TypeOf(ptr.*)).Optional.child
            ),
            .enum_ => ptr.* = try decodeEnum(data, &i, @TypeOf(ptr.*)),
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

fn decodeInterface(
    bytes: []const u8,
    start: *usize,
    InterfaceType: type
) DecodeError!?InterfaceType {
    comptime assertInterface(InterfaceType);
    const id = try decodeU32(bytes, start);
    if (id == 0) return null;
    return InterfaceType {
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
) RequestError!void { // TODO Refactor this
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

/// Returns the number of bytes read into buffer. `fd_n` will contian the number
/// of FDs read.
pub fn readEvent(
    socket: std.posix.socket_t,
    buffer: []u8,
    fd_buf: []FD,
    fd_n: *usize,
) !Header {
    fd_n.* = 0;
    var header_buf: []u8 = buffer[0..@sizeOf(Header)];
    var read_n: usize = 0;
    while (read_n < header_buf.len) {
        read_n += try readPartial(socket, header_buf[read_n..], fd_buf, fd_n);
    }
    const header = std.mem.bytesToValue(Header, header_buf);
    var data_buffer = buffer[0..header.length];
    while (read_n < header.length) {
        read_n += try readPartial(socket, data_buffer[read_n..], fd_buf, fd_n);
    }
    return header;
}

fn readPartial(
    socket: std.posix.socket_t,
    buffer: []u8,
    fd_buf: []FD,
    fd_offset: *usize
) !usize {
    var iov: std.posix.iovec = .{
        .base = buffer.ptr,
        .len = buffer.len,
    };
    var cmsg = cmsghdr([4]FD) {
        .level = 0,
        .type = 0,
        .data = .{0}**4,
    };
    var msg: std.posix.msghdr = .{
        .name = null,
        .namelen = 0,
        .iov = @ptrCast(&iov),
        .iovlen = 1,
        .control = &cmsg,
        .controllen = @intCast(cmsg.len),
        .flags = 0,
    };

    const n: usize = try recvmsg(socket, &msg, 0);

    //                              SCM_RIGHTS  vvv
    if ((msg.controllen > 16) and (cmsg.type == 0x01)) {
        const fds: usize = (msg.controllen - 16) / @sizeOf(FD);
        if (fds + fd_offset.* > fd_buf.len) return error.FDBufOverflow;
        @memcpy(fd_buf[fd_offset.*..fd_offset.* + fds], cmsg.data[0..fds]);
        fd_offset.* += fds;
    }
    return n;
}

// Wrapper for linux.recvmsg with error handling
pub fn recvmsg(
    fd: i32,
    msg: *std.posix.msghdr,
    flags: u32
) !usize {
    while (true) {
        const rc = std.os.linux.recvmsg(fd, msg, flags);
        switch (std.posix.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .BADF => unreachable, // always a race condition
            .FAULT => unreachable,
            .INVAL => unreachable,
            .NOTCONN => return error.SocketNotConnected,
            .NOTSOCK => unreachable,
            .INTR => continue,
            .AGAIN => return error.WouldBlock,
            .NOMEM => return error.SystemResources,
            .CONNREFUSED => return error.ConnectionRefused,
            .CONNRESET => return error.ConnectionResetByPeer,
            .TIMEDOUT => return error.ConnectionTimedOut,
            else => |err| return std.posix.unexpectedErrno(err),
        }
    }
}
