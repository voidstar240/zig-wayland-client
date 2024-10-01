const std = @import("std");
pub const wire = @import("wire.zig");
const protocol = @import("protocol.zig");
pub usingnamespace protocol;

const Stream = std.net.Stream;
const GenericReader = std.io.GenericReader;

pub const Fixed = wire.Fixed;
pub const FD = wire.FD;
pub const Object = wire.Object;
pub const AnonymousEvent = wire.AnonymousEvent;
pub const DecodeError = wire.DecodeError;
pub const RequestError = wire.RequestError;
pub const decodeEvent = wire.decodeEvent;

pub const WaylandContext = struct {
    socket: Stream,
    read_buffer: [4096]u8 align(@alignOf(*anyopaque)),

    const Reader = GenericReader(Stream, Stream.ReadError, Stream.read);

    /// Creates a new Wayland global object.
    pub fn init(socket: Stream) WaylandContext {
        return WaylandContext {
            .socket = socket,
            .read_buffer = undefined,
        };
    }

    /// Gets a reader to the socket stream.
    pub fn reader(self: *WaylandContext) Reader {
        return self.socket.reader();
    }

    /// Reads one event into the read buffer overwritting what was there
    /// previously. Returns an AnonymousEvent. The contained data slice is a
    /// reference to the internal read buffer and not owned.
    pub fn readEvent(self: *WaylandContext) !AnonymousEvent {
        const head = try wire.readEvent(self.reader(), &self.read_buffer);
        return AnonymousEvent {
            .self = Object { .id = head.object_id },
            .opcode = head.opcode,
            .arg_data = self.read_buffer[@sizeOf(wire.Header)..head.length],
        };
    }

    /// Gets the global wl_display object.
    pub fn getDisplay() protocol.wl_display {
        return protocol.wl_display {
            .id = 1,
        };
    }
};

/// Connect to the wayland socket.
pub fn connectToSocket() !std.net.Stream {
    // 108 is the maximum path length in std.posix.sockaddr.un, \0 terminated
    var path: [107]u8 = undefined;
    var len: usize = undefined; 
    const sock_name = std.posix.getenv("WAYLAND_DISPLAY") orelse "wayland-0";
    if (sock_name[0] == '/') {
        // sock_name is the absolute path to the socket
        if (sock_name.len > path.len) return error.SocketPathTooLong;
        @memcpy(path[0..sock_name.len], sock_name);
        len = sock_name.len;
    } else {
        // concat XDG_RUNTIME_DIR and sock_name to get path
        const sock_dir = std.posix.getenv("XDG_RUNTIME_DIR")
            orelse return error.RuntimeDirNotSet;
        len = sock_dir.len + 1 + sock_name.len;
        if (len > path.len) return error.SocketPathTooLong;
        @memcpy(path[0..sock_dir.len], sock_dir);
        path[sock_dir.len] = '/';
        const name_start = sock_dir.len + 1;
        const name_end = name_start + sock_name.len;
        @memcpy(path[name_start..name_end], sock_name);
    }
    return std.net.connectUnixSocket(path[0..len]);
}

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
