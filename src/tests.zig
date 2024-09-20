const std = @import("std");
const zwl = @import("zwayland");

test "functionality" {
    const sock = try zwl.connectToSocket();
    defer sock.close();
    var global = zwl.WaylandState.init(sock);
    const display = zwl.WaylandState.getDisplay();
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
