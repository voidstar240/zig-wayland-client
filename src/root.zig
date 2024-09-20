const std = @import("std");
const protocol = @import("protocol.zig");
const wire = @import("wire.zig");

const Stream = std.net.Stream;
const GenericWriter = std.io.GenericWriter;
const GenericReader = std.io.GenericReader;

pub const Fixed = wire.Fixed;
pub const FD = wire.FD;
pub const Object = wire.Object;
pub const AnonymousEvent = wire.AnonymousEvent;
pub const DecodeError = wire.DecodeError;

pub const WaylandState = struct {
    socket: Stream,
    write_buffer: [4096]u8,
    write_end: usize,
    read_buffer: [4096]u8 align(@alignOf(*anyopaque)),
    auto_flush: bool,

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
        try wire.writeRequest(self.writer(), obj_id, opcode, args);
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

test "functionality" {
    const sock = try connectToSocket();
    defer sock.close();
    var global = WaylandState.init(sock);
    const display = WaylandState.getDisplay();
    const reg = try display.getRegistry(&global, 2);
    const sync = try display.sync(&global, 3);

    while (true) {
        const anon = try global.readEvent();
        if (try reg.decodeGlobalEvent(anon)) |event| {
            std.debug.print(
                \\{d}: {s} v{d}
                \\
                , .{event.name, event.interface, event.version});
        } else if (try sync.decodeDoneEvent(anon)) |_| {
            std.debug.print("DONE!\n", .{});
            break;
        } else if (try display.decodeErrorEvent(anon)) |event| {
            std.debug.print(
                \\ERROR: {d} on object {d}: {s}
                \\
                , .{event.code, event.object_id.id, event.message});
        } else {
            std.debug.print(
                \\Unkown Event: obj: {d} op: {d}\n
                \\
                , .{anon.self.id, anon.opcode});
        }
    }
}
