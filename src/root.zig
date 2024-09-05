const std = @import("std");
const protocol = @import("protocol.zig");
const util = @import("util.zig");

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
        const sock_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse return error.RuntimeDirNotSet;
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

test "functionality" {
    const sock = try connectToSocket();
    defer sock.close();
    var global = util.WaylandState.init(sock);
    const display = global.create_display();
    const reg = try display.getRegistry();
    _ = reg;
    const sync = try display.sync();
    _ = sync;
}
