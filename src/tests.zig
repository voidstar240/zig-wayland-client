const std = @import("std");
const wl = @import("wayland-client");

test "SyncRequestResponse" {
    const socket = try wl.connectToSocket();
    defer socket.close();
    var ctx = wl.WaylandContext.init(socket);
    const display = ctx.getDisplay();
    const sync = try display.sync(&ctx, 2);

    const anon_event = try ctx.readEvent();
    if (try sync.decodeDoneEvent(anon_event) == null) {
        return error.NotSyncEvent;
    }
}
