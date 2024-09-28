const std = @import("std");
const types = @import("types.zig");

const Version = types.Version;
const Protocol = types.Protocol;
const Interface = types.Interface;
const Method = types.Method;
const Arg = types.Arg;
const Enum = types.Enum;
const Entry = types.Entry;

pub fn generateProtocol(
    protocol: *const Protocol,
    writer: anytype,
    dependencies: [][]const u8
) !void {
    if (protocol.copyright) |copyright| {
        try writer.print("{// }\n", .{parsedText(copyright)});
    }

    try writer.writeAll("const deps = struct {\n");
    try writer.writeAll("    usingnamespace @import(\"protocol.zig\");\n");
    for (dependencies) |dep| {
        try writer.print("    usingnamespace @import(\"{s}\");\n", .{dep});
    }
    try writer.writeAll("};\n\n");

    try writer.writeAll(
        \\const Fixed = deps.Fixed;
        \\const FD = deps.FD;
        \\const Object = deps.Object;
        \\const AnonymousEvent = deps.AnonymousEvent;
        \\const DecodeError = deps.DecodeError;
        \\const decodeEvent = deps.decodeEvent;
        \\const WaylandState = deps.WaylandState;
        \\
        \\
        \\
    );

    for (protocol.interfaces) |*interface| {
        try generateInterface(interface, writer);
    }
}

fn generateInterface(interface: *const Interface, writer: anytype) !void {
    if (interface.description) |desc| {
        if (desc.body) |body| {
            try writer.print("{/// }", .{parsedText(body)});
        }
    }
    try writer.print(
        \\pub const {s} = struct {{
        \\    id: u32,
        \\
        \\    const Self = @This();
        \\
        \\    pub const interface_str = "{s}";
        \\    pub const version: u32 = {d};
        \\
        \\    pub const opcode = 
        , .{interface.name, interface.name, interface.version});
    try generateOpcodes(interface, writer);
    for (interface.enums) |*enum_| {
        try generateEnum(enum_, writer);
    }
    for (interface.requests) |*request| {
        try generateRequest(request, writer);
    }
    for (interface.events) |*event| {
        try generateEvent(event, writer);
    }
    try writer.writeAll("};\n\n");
}

fn generateOpcodes(interface: *const Interface, writer: anytype) !void {
    try writer.writeAll("struct {\n");
    if (interface.requests.len > 0) {
        try writer.writeAll("        pub const request = struct {\n");
    }
    for (interface.requests, 0..) |*request, i| {
        try writer.print(
            \\            pub const {}: u16 = {d};
            \\
            , .{escBadName(request.name), i});
    }
    if (interface.requests.len > 0) {
        try writer.writeAll("        };\n");
    }
    if (interface.events.len > 0) {
        try writer.writeAll("        pub const event = struct {\n");
    }
    for (interface.events, 0..) |*event, i| {
        try writer.print(
            \\            pub const {}: u16 = {d};
            \\
            , .{escBadName(event.name), i});
    }
    if (interface.events.len > 0) {
        try writer.writeAll("        };\n");
    }
    try writer.writeAll("    };\n\n");
}

fn generateRequest(request: *const Method, writer: anytype) !void {
    if (request.description) |desc| {
        if (desc.body) |body| {
            try writer.print("{    /// }", .{parsedText(body)});
        }
    }

    try writer.print(
        \\    pub fn {}(self: Self, global: *WaylandState
        , .{camelCase(request.name)});

    const return_obj = newIdArgCount(request) == 1;
    var return_arg: Arg = undefined;
    for (request.args) |arg| {
        if (arg.type == .new_id) {
            if (return_obj) {
                return_arg = arg;
            }
        }
        try writer.print(", {}: ", .{escBadName(arg.name)});
        try generateArgType(arg.type, writer);
    }

    if (return_obj) {
        if (return_arg.type.new_id.interface) |interface| {
            try writer.print(
                \\) !deps.{s} {{
                \\        const new_obj = deps.{s} {{
                \\            .id = {}
                \\        }};
                \\
                \\
                , .{interface, interface, escBadName(return_arg.name)});
        } else {
            try writer.print(
                \\) !Object {{
                \\        const new_obj = Object {{
                \\            .id = {}
                \\        }};
                \\
                \\
                , .{escBadName(return_arg.name)});
        }
    } else {
        try writer.writeAll(") !void {\n"); // TODO return specific error
    }

    try writer.print(
        \\        const op = Self.opcode.request.{};
        \\        try global.sendRequest(self.id, op, .{{ 
        , .{escBadName(request.name)});
    for (request.args) |arg| {
        try writer.print("{}, ", .{escBadName(arg.name)});
    }
    try writer.writeAll("});\n");

    if (return_obj) {
        try writer.writeAll("        return new_obj;\n");
    }

    try writer.writeAll("    }\n\n");
}

fn generateEvent(event: *const Method, writer: anytype) !void {
    if (event.description) |desc| {
        if (desc.body) |body| {
            try writer.print("{    /// }", .{parsedText(body)});
        }
    }
    try generateEventStruct(event, writer);
    try writer.print(
        \\    pub fn decode{}Event(self: Self, event: AnonymousEvent) DecodeError!?{}Event {{
        \\        if (event.self.id != self.id) return null;
        \\
        \\        const op = Self.opcode.event.{};
        \\        if (event.opcode != op) return null;
        \\
        \\        return try decodeEvent(event, {}Event);
        \\    }}
        \\
        \\
        , .{
            titleCase(event.name),
            titleCase(event.name),
            escBadName(event.name),
            titleCase(event.name)
        });
}

fn generateEventStruct(event: *const Method, writer: anytype) !void {
    try writer.print(
        \\    pub const {}Event = struct {{
        \\        self: Self,
        \\
        , .{titleCase(event.name)});
    for (event.args) |arg| {
        try writer.print("        {}: ", .{escBadName(arg.name)});
        try generateArgType(arg.type, writer);
        try writer.writeAll(",\n");
    }
    try writer.writeAll("    };\n");
}

fn generateArgType(arg_type: Arg.Type, writer: anytype) !void {
    switch (arg_type) {
        .int => try writer.writeAll("i32"),
        .uint => try writer.writeAll("u32"),
        .fixed => try writer.writeAll("Fixed"),
        .array => try writer.writeAll("[]const u8"),
        .fd => try writer.writeAll("FD"),
        .string => |meta| {
            if (meta.allow_null)
                try writer.writeAll("?");
            try writer.writeAll("[:0]const u8");
        },
        .object => |meta| {
            if (meta.allow_null)
                try writer.writeAll("?");
            if (meta.interface) |interface| {
                try writer.print("deps.{s}", .{interface});
            } else {
                try writer.writeAll("Object");
            }
        },
        .new_id => try writer.writeAll("u32"),
        .enum_ => |meta| {
            try writer.print("{}", .{enumType(meta.enum_name)});
        },
    }
}

fn generateEnum(enum_: *const Enum, writer: anytype) !void {
    if (enum_.description) |desc| {
        if (desc.body) |body| {
            try writer.print("{    /// }", .{parsedText(body)});
        }
    }
    try writer.print(
        \\    pub const {} = enum(u32) {{
        \\
        , .{titleCase(enum_.name)});
    for (enum_.entries) |*entry| {
        try writer.print(
            \\        {} = {d},
            , .{escBadName(entry.name), entry.value});
        if (entry.summary) |summary| {
            try writer.print(" // {}", .{singleLine(summary)});
        }
        try writer.print("\n", .{});
    }
    try writer.writeAll("    };\n\n");
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

fn escBadName(bytes: []const u8) std.fmt.Formatter(escBadNameFormatFn) {
    return .{ .data = bytes };
}

fn camelCase(bytes: []const u8) std.fmt.Formatter(camelCaseFormatFn) {
    return .{ .data = bytes };
}

fn titleCase(bytes: []const u8) std.fmt.Formatter(titleCaseFormatFn) {
    return .{ .data = bytes };
}

fn enumType(bytes: []const u8) std.fmt.Formatter(enumTypeFormatFn) {
    return .{ .data = bytes };
}

fn singleLine(bytes: []const u8) std.fmt.Formatter(singleLineFormatFn) {
    return .{ .data = bytes };
}

fn parsedText(bytes: []const u8) std.fmt.Formatter(parsedTextFormatFn) {
    return .{ .data = bytes };
}

fn escBadNameFormatFn(
    bytes: []const u8,
    comptime _: []const u8,
    _: std.fmt.FormatOptions,
    writer: anytype
) !void {
    if (bytes.len == 0) return;
    if (std.zig.Token.keywords.has(bytes) or std.ascii.isDigit(bytes[0])) {
        try writer.print("@\"{s}\"", .{bytes});
    } else {
        try writer.writeAll(bytes);
    }
}

fn camelCaseFormatFn(
    bytes: []const u8,
    comptime _: []const u8,
    _: std.fmt.FormatOptions,
    writer: anytype
) !void {
    var upper = false;
    for (bytes) |c| {
        if (c == '_') {
            upper = true;
            continue;
        }
        try writer.writeByte(if (upper) std.ascii.toUpper(c) else c);
        upper = false;
    }
}

fn titleCaseFormatFn(
    bytes: []const u8,
    comptime _: []const u8,
    _: std.fmt.FormatOptions,
    writer: anytype
) !void {
    var upper = true;
    for (bytes) |c| {
        if (c == '_') {
            upper = true;
            continue;
        }
        try writer.writeByte(if (upper) std.ascii.toUpper(c) else c);
        upper = false;
    }
}

fn enumTypeFormatFn(
    bytes: []const u8,
    comptime _: []const u8,
    _: std.fmt.FormatOptions,
    writer: anytype
) !void {
    if (std.mem.indexOfScalar(u8, bytes, '.')) |i| {
        const interface = bytes[0..i];
        const enum_type = bytes[(i+1)..];
        try writer.print("deps.{s}.{}", .{interface, titleCase(enum_type)});
    } else {
        try writer.print("{}", .{titleCase(bytes)});
    }
}

fn singleLineFormatFn(
    bytes: []const u8,
    comptime _: []const u8,
    _: std.fmt.FormatOptions,
    writer: anytype
) !void {
    var rem_bytes = bytes;
    var i: usize = 0;
    while (i < rem_bytes.len) {
        switch (rem_bytes[i]) {
            '\r', '\n' => {
                try writer.writeAll(rem_bytes[0..i]);
                rem_bytes = rem_bytes[i+1..];
                i = 0;
            },
            else => {
                i += 1;
            },
        }
    }
    try writer.writeAll(rem_bytes);
}

/// Prints `text` with XML escape sequences properly escaped.
fn parsedTextFormatFn(
    bytes: []const u8,
    comptime prefix: []const u8,
    _: std.fmt.FormatOptions,
    writer: anytype
) !void {
    var rem_bytes = bytes;
    var i: usize = 0;
    var new_line = true;
    while (i < rem_bytes.len) {
        switch (rem_bytes[i]) {
            ' ', '\t' => if (new_line) {
                rem_bytes = rem_bytes[i+1..];
                i = 0;
            } else {
                i += 1;
            },
            '&' => {
                try writer.print("{s}{s}", .{prefix, rem_bytes[0..i]});
                rem_bytes = rem_bytes[i..];
                if (std.mem.eql(u8, rem_bytes[0..5], "&quot")) {
                    try writer.writeByte('"');
                    rem_bytes = rem_bytes[5..];
                } else if (std.mem.eql(u8, rem_bytes[0..5], "&apos")) {
                    try writer.writeByte('\'');
                    rem_bytes = rem_bytes[5..];
                } else if (std.mem.eql(u8, rem_bytes[0..3], "&lt")) {
                    try writer.writeByte('<');
                    rem_bytes = rem_bytes[3..];
                } else if (std.mem.eql(u8, rem_bytes[0..3], "&gt")) {
                    try writer.writeByte('>');
                    rem_bytes = rem_bytes[4..];
                } else if (std.mem.eql(u8, rem_bytes[0..4], "&amp")) {
                    try writer.writeByte('&');
                    rem_bytes = rem_bytes[4..];
                }
                new_line = false;
                i = 0;
            },
            '\n' => {
                try writer.print("{s}{s}", .{prefix, rem_bytes[0..i+1]});
                rem_bytes = rem_bytes[i+1..];
                new_line = true;
                i = 0;
            },
            else => {
                new_line = false;
                i += 1;
            },
        }
    }
}
