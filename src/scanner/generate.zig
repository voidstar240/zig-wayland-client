const types = @import("types.zig");

const Version = types.Version;
const Protocol = types.Protocol;
const Interface = types.Interface;
const Method = types.Method;
const Arg = types.Arg;
const Enum = types.Enum;
const Entry = types.Entry;

pub fn generateProtocol(protocol: *const Protocol, writer: anytype) !void {
    try writer.print("const util = @import(\"util.zig\");\n\n", .{});
    // TODO allow users to import dependency protocols here. Ex. wayland is a
    // dep. or xdg_shell so print ...
    // const wl = @import("zwayland");
    // The dependency will have to get passed in the build script in build.zig.
    try writer.print("const Object = util.Object;\n", .{});
    try writer.print("const Fixed = util.Fixed;\n", .{});
    try writer.print("const FD = util.FD;\n\n", .{});
    for (protocol.interfaces) |*interface| {
        try generateInterface(interface, writer);
    }
}

fn generateInterface(interface: *const Interface, writer: anytype) !void {
    try writer.print("pub const {s} = struct {{\n", .{interface.name});
    try writer.print("    inner: Object,\n\n", .{});
    try generateOpcodes(interface, writer);
    for (interface.enums) |*enum_| {
        try generateEnum(enum_, writer);
    }
    for (interface.requests) |*request| {
        try generateRequest(request, writer);
    }
    try writer.print("}};\n\n", .{});
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
    try writer.print("    pub fn {s}(self: @This()", .{request.name});

    const return_obj = newIdArgCount(request) == 1;
    var return_interface: ?[]const u8 = null;
    for (request.args) |arg| {
        var pre: []const u8 = "";
        var type_name: []const u8 = undefined;
        switch (arg.type) {
            .int => type_name = "i32",
            .uint => type_name = "u32",
            .fixed => type_name = "Fixed",
            .array => type_name = "[]const u8",
            .fd => type_name = "FD",
            .string => |meta| {
                if (meta.allow_null) pre = "?";
                type_name = "[:0]const u8";
            },
            .object => |meta| {
                if (meta.allow_null) pre = "?";
                if (meta.interface) |name| {
                    type_name = name;
                } else {
                    type_name = "Object";
                }
            },
            .new_id => |meta| {
                if (return_obj) {
                    return_interface = meta.interface;
                    continue;
                }
                if (meta.interface) |name| {
                    type_name = name;
                } else {
                    type_name = "Object";
                }
            },
            .enum_ => |meta| {
                type_name = meta.enum_name;
            },
        }
        try writer.print(", {s}: {s}{s}", .{arg.name, pre, type_name});
    }

    if (return_obj) {
        if (return_interface) |name| {
            try writer.print(") {s} {{\n", .{name});
        } else {
            try writer.print(") Object {{\n", .{});
        }
    } else {
        try writer.print(") void {{\n", .{}); // TODO return error??
    }

    try writer.print("        _ = self;\n", .{});
    for (request.args) |arg| {
        if ((arg.type == .new_id) and return_obj) continue;
        try writer.print("        _ = {s};\n", .{arg.name});
    }

    if (return_obj) {
        try writer.print("        return undefined;\n", .{});
    }

    try writer.print("    }}\n\n", .{});
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

fn newIdArgCount(request: *const Method) usize {
    var count: usize = 0;
    for (request.args) |arg| {
        switch (arg.type) {
            .new_id => count += 1,
            else => {},
        }
    }
    return count;
}
