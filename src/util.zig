const std = @import("std");

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
    id: u32 = 0,
    display: ?*anyopaque = null, // TODO store pointer to global wayland object (wl_display)
};

pub const FD = std.posix.fd_t;

fn msgLength(args: anytype) u16 {
    const args_info = @typeInfo(@TypeOf(args));
    const fields = args_info.Struct.fields;
    var msg_len: u16 = 8;
    inline for (fields) |field| {
        const FieldType = field.type;
        const field_info = @typeInfo(FieldType);
        const field_val = @field(args, field.name);

        // THIS WILL NOT CHECK FOR INVALID TYPES
        // That is writePacket's responsibility
        if (FieldType == ?[:0]const u8) { // string type
            if (field_val) |str| {
                const byte_len: u16 = str.len + 1;
                msg_len += byte_len + @subWithOverflow(0, byte_len).@"0" % 4;
            }
        } else if (field_info == .Pointer) {
            const ptr = field_info.Pointer;
            if (ptr.size != .Slice) {
                continue;
            }
            // array type
            const byte_len: u16 = field_val.len * @sizeOf(ptr.child);
            msg_len += byte_len + @subWithOverflow(0, byte_len).@"0" % 4;
        }
        msg_len += 4;
    }
    return msg_len;
}

pub fn writePacket(writer: anytype, object_id: u32, opcode: u16, args: anytype) !void {
    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);
    if (args_info != .Struct) {
        @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
    }

    const fields = args_info.Struct.fields;
    if (fields.len > 20) {
        @compileError("20 arguments max are supported for wire format");
    }

    try writer.writeAll(&std.mem.toBytes(object_id));
    try writer.writeAll(&std.mem.toBytes(opcode));
    try writer.writeAll(&std.mem.toBytes(msgLength(args)));
    inline for (fields) |field| {
        const FieldType = field.type;
        const field_info = @typeInfo(FieldType);
        const field_val = @field(args, field.name);

        switch (FieldType) {
            u32, i32 => {
                // int, uint, object, new_id and fd type
                try writer.writeAll(&std.mem.toBytes(field_val));
                continue;
            },
            ?[:0]const u8 => {
                // string type
                if (field_val == null) {
                    try writer.writeAll(&std.mem.toBytes(@as(u32, 0)));
                    continue;
                }

                const len = field_val.?.len + 1;
                try writer.writeAll(&std.mem.toBytes(@as(u32, len)));
                try writer.writeAll(field_val.?[0..len]);
                try writer.writeByteNTimes(0, @subWithOverflow(0, len).@"0" % 4);
                continue;
            },
            else => {},
        }

        switch (field_info) {
            .Pointer => |ptr| {
                if (ptr.size != .Slice) {
                    @compileError("Unsupported type " ++ @typeName(FieldType));
                }
                if (@sizeOf(ptr.child) == 0) {
                    @compileError("Cannot seriaize zero sized type " ++ @typeName(FieldType));
                }
                if (ptr.sentinel != null) {
                    @compileError("Cannot serialize slice with sentinel value");
                }

                // array type
                const bytes = std.mem.sliceAsBytes(field_val);
                try writer.writeAll(&std.mem.toBytes(@as(u32, @intCast(bytes.len))));
                try writer.writeAll(bytes);
                try writer.writeByteNTimes(0, @subWithOverflow(0, bytes.len).@"0" % 4);
            },
            .Enum => |enum_info| {
                // enum and Fixed type
                const tag_info = @typeInfo(enum_info.tag_type);
                if (tag_info.Int.bits > 32) {
                    @compileError(@typeName(FieldType) ++ " tag has more than 32 bits");
                }
                if (tag_info.Int.signedness == .unsigned) {
                    try writer.writeAll(&std.mem.toBytes(@as(u32, @intFromEnum(field_val))));
                } else {
                    try writer.writeAll(&std.mem.toBytes(@as(i32, @intFromEnum(field_val))));
                }
            },
            else => @compileError("Unsupported type " ++ @typeName(FieldType)),
        }
    }
}
