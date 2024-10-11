const std = @import("std");
const wl = @import("wayland_core");
const xdg = struct {
    usingnamespace @import("xdg_shell");
    usingnamespace @import("xdg_decor");
};

const print = std.debug.print;

pub fn main() !void {
    const socket = try wl.connectToSocket();
    var ctx = wl.WaylandContext.init(socket);
    const display = ctx.getDisplay();
    const reg = try display.getRegistry(&ctx, 2);
    const sync = try display.sync(&ctx, 3);
    
    var next_id: u32 = 4;
    var comp: ?wl.Compositor = null;
    var shm: ?wl.Shm = null;
    var wm: ?xdg.WmBase = null;
    var decor: ?xdg.DecorationManagerV1 = null;
    // find and bind to the needed global objects
    while (true) {
        const anon_event = try ctx.readEvent();
        if (try reg.decodeGlobalEvent(anon_event)) |event| {
            if (std.mem.eql(u8, wl.Compositor.interface_str, event.interface)) {
                comp = try reg.bind(&ctx, event.name, wl.Compositor, event.version, next_id); 
                next_id += 1;
            } else if (std.mem.eql(u8, wl.Shm.interface_str, event.interface)) {
                shm = try reg.bind(&ctx, event.name, wl.Shm, event.version, next_id);
                next_id += 1;
            } else if (std.mem.eql(u8, xdg.WmBase.interface_str, event.interface)) {
                wm = try reg.bind(&ctx, event.name, xdg.WmBase, event.version, next_id);
                next_id += 1;
            } else if (std.mem.eql(u8, xdg.DecorationManagerV1.interface_str, event.interface)) {
                decor = try reg.bind(&ctx, event.name, xdg.DecorationManagerV1, event.version, next_id);
                next_id += 1;
            }
        } else if (try sync.decodeDoneEvent(anon_event)) |_| {
            break;
        } else if (try display.decodeDeleteIdEvent(anon_event)) |event| {
            print("Delete id {}\n", .{event.id});
        } else if (try display.decodeErrorEvent(anon_event)) |event| {
            print("Error {d} on object {d}, {s}\n", .{event.code, event.object_id, event.message});
            return error.WLError;
        }
    }

    if (comp == null) return error.NoComp;
    if (shm == null) return error.NoShm;
    if (wm == null) return error.NoWm;
    if (decor == null) {
        print("Unable to get DecorationManagerV1. Window will have no decorations.", .{});
    }

    const wl_surf: wl.Surface = try comp.?.createSurface(&ctx, next_id);
    next_id += 1;
    const xdg_surf: xdg.Surface = try wm.?.getXdgSurface(&ctx, next_id, wl_surf);
    next_id += 1;
    const xdg_toplevel: xdg.Toplevel = try xdg_surf.getToplevel(&ctx, next_id);
    next_id += 1;
    if (decor != null) {
        const top_decor = try decor.?.getToplevelDecoration(&ctx, next_id, xdg_toplevel);
        next_id += 1;
        try top_decor.setMode(&ctx, .server_side);
    }
    try xdg_toplevel.setTitle(&ctx, "My Test Window");
    try xdg_toplevel.setMinSize(&ctx, 320, 240);
    try wl_surf.commit(&ctx);

    var width: usize = 640;
    var height: usize = 480;
    var resizing = false;

    var buffer: ?wl.Buffer = null;
    // Poll for window events
    while (true) {
        const anon_event = try ctx.readEvent();
        if (try display.decodeDeleteIdEvent(anon_event)) |event| {
            print("Delete id {}\n", .{event.id});
        } else if (try display.decodeErrorEvent(anon_event)) |event| {
            print("Error {d} on object {d}, {s}\n", .{event.code, event.object_id, event.message});
            return error.WLError;
        } else if (try wm.?.decodePingEvent(anon_event)) |event| {
            try wm.?.pong(&ctx, event.serial);
        } else if (try xdg_surf.decodeConfigureEvent(anon_event)) |event| {
            try xdg_surf.ackConfigure(&ctx, event.serial);
            if (!resizing) {
                print("size: {d}x{d}\n", .{width, height});
                buffer = try draw_frame(&ctx, shm.?, &next_id, width, height);
                try wl_surf.attach(&ctx, buffer, 0, 0);
                try wl_surf.commit(&ctx);
            }
        } else if (try xdg_toplevel.decodeCloseEvent(anon_event)) |_| {
            print("Closing...\n", .{});
            return;
        } else if (try xdg_toplevel.decodeConfigureEvent(anon_event)) |event| {
            if (event.width > 0) {
                width = @intCast(event.width);
            }
            if (event.height > 0) {
                height = @intCast(event.height);
            }
            var states: []const xdg.Toplevel.State = undefined;
            states.ptr = @alignCast(@ptrCast(event.states.ptr));
            states.len = event.states.len / 4;
            resizing = std.mem.indexOfScalar(xdg.Toplevel.State, states, .resizing) != null;
        }

        if (buffer) |buf| {
            if (try buf.decodeReleaseEvent(anon_event)) |_| {
                try buf.destroy(&ctx);
                buffer = null;
            }
        }
    }
}

fn draw_frame(ctx: *const wl.WaylandContext, shm: wl.Shm, id: *u32, w: usize, h: usize) !wl.Buffer {
    const shm_size = w * h * 4;
    // create anonymous file
    const mode = std.posix.O { .ACCMODE = .RDWR, .CREAT = true, .EXCL = true};
    const shm_fd = std.c.shm_open("wl_shm_example_buffer", @bitCast(mode), 600);
    if (shm_fd == -1) {
        return error.BadShmFd;
    }
    if (std.c.shm_unlink("wl_shm_example_buffer") == -1) {
        return error.UnlinkShm;
    }
    try std.posix.ftruncate(shm_fd, shm_size);
    const data = try std.posix.mmap(null, shm_size, std.posix.PROT.READ | std.posix.PROT.WRITE, std.posix.MAP { .TYPE = .SHARED }, shm_fd, 0);

    // create memory pool and buffer
    const pool: wl.ShmPool = try shm.createPool(ctx, id.*, shm_fd, @intCast(shm_size));
    id.* += 1;
    const buffer = try pool.createBuffer(ctx, id.*, 0, @intCast(w), @intCast(h), @intCast(w * 4), wl.Shm.Format.xrgb8888);
    id.* += 1;

    try pool.destroy(ctx);
    std.posix.close(shm_fd);

    // draw checkerboard pattern
    for (0..h) |y| {
        for (0..w) |x| {
            if ((y % 16 < 8) == (x % 16 < 8)) {
                data[y*w*4 + x*4] = 0;
                data[y*w*4 + x*4 + 1] = 0;
                data[y*w*4 + x*4 + 2] = 0;
                data[y*w*4 + x*4 + 3] = 255;
            } else {
                data[y*w*4 + x*4] = 255;
                data[y*w*4 + x*4 + 1] = 255;
                data[y*w*4 + x*4 + 2] = 255;
                data[y*w*4 + x*4 + 3] = 255;
            }
        }
    }

    std.posix.munmap(data);
    return buffer;
}
