const types = @import("types.zig");

const Version = types.Version;
const Protocol = types.Protocol;
const Interface = types.Interface;
const Method = types.Method;
const Arg = types.Arg;
const Enum = types.Enum;
const Entry = types.Entry;

pub fn generateProtocol(protocol: *const Protocol, writer: anytype) !void {
    try writer.print(
        \\const std = @import("util.zig");
        \\
        \\
        , .{});
    for (protocol.interfaces) |*interface| {
        try generateInterface(interface, writer);
    }
}

fn generateInterface(interface: *const Interface, writer: anytype) !void {
    try writer.print(
        \\pub const {s} = struct {{
        \\
        , .{interface.name});
    try generateOpcodes(interface, writer);
    for (interface.enums) |*enum_| {
        try generateEnum(enum_, writer);
    }
    for (interface.requests) |*request| {
        try generateRequest(request, writer);
    }
    try writer.print(
        \\}};
        \\
        \\
        , .{});
}

fn generateOpcodes(interface: *const Interface, writer: anytype) !void {
    try writer.print(
        \\    pub const opcode = struct {{
        \\        pub const request = struct {{
        \\
        , .{});
    for (interface.requests, 0..) |*request, i| {
        try writer.print(
            \\            pub const {s}: u16 = {};
            \\
            , .{request.name, i});
    }
    try writer.print(
        \\        }};
        \\        pub const event = struct {{
        \\
        , .{});
    for (interface.events, 0..) |*event, i| {
        try writer.print(
            \\            pub const {s}: u16 = {};
            \\
            , .{event.name, i});
    }
    try writer.print(
        \\        }};
        \\    }};
        \\
        \\
        , .{});
}

fn generateRequest(request: *const Method, writer: anytype) !void {
    try writer.print(
        \\    pub fn {s}() void {{}}
        \\
        \\
        , .{request.name});
}

fn generateEnum(enum_: *const Enum, writer: anytype) !void {
    try writer.print(
        \\    pub const {s} = enum(u32) {{
        \\
        , .{enum_.name});
    for (enum_.entries) |*entry| {
        try writer.print(
            \\        {s} = {d},
            , .{entry.name, entry.value});
        if (entry.summary) |summary| {
            try writer.print(" // {s}", .{summary});
        }
        try writer.print("\n", .{});
    }
    try writer.print(
        \\    }};
        \\
        \\
        , .{});
}
