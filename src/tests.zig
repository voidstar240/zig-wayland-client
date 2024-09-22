const std = @import("std");
const zwl = @import("zwayland");

test "SyncRequestResponse" {
    const socket = try zwl.connectToSocket();
    defer socket.close();
    var state = zwl.WaylandState.init(socket);
    const display = zwl.WaylandState.getDisplay();
    const sync = try display.sync(&state, 2);

    const anon_event = try state.readEvent();
    if (try sync.decodeDoneEvent(anon_event) == null) {
        return error.NotSyncEvent;
    }
}
