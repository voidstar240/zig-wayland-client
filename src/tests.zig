const std = @import("std");
const zwl = @import("zwayland");

test "SyncRequestResponse" {
    const socket = try zwl.connectToSocket();
    defer socket.close();
    var ctx = zwl.WaylandContext.init(socket);
    const display = ctx.getDisplay();
    const sync = try display.sync(&ctx, 2);

    const anon_event = try ctx.readEvent();
    if (try sync.decodeDoneEvent(anon_event) == null) {
        return error.NotSyncEvent;
    }
}
