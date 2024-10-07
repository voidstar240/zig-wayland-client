const std = @import("std");
const types = @import("types.zig");
const main = @import("main.zig");

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
) !void {
    if (protocol.copyright) |copyright| {
        try writer.print("{// }\n", .{parsedText(copyright)});
    }

    try writer.writeAll("const this_protocol = @This();\n");
    for (main.gen_args.imports) |import| {
        if (import.paths.len > 1) {
            try writer.print("const {s} = struct {{\n", .{import.name});
            for (import.paths) |path| {
                if (std.mem.eql(u8, path, "@This()")) {
                    try writer.writeAll("    usingnamespace this_protocol;\n");
                } else {
                    try writer.print(
                        "    usingnamespace @import(\"{s}\");\n",
                        .{path});
                }
            }
            try writer.writeAll("};\n");
        } else {
            if (std.mem.eql(u8, import.paths[0], "@This()")) {
                try writer.print(
                    "const {s} = this_protocol;\n",
                    .{import.name});
            } else {
                try writer.print(
                    "const {s} = @import(\"{s}\");\n",
                    .{import.name, import.paths[0]});
            }
        }
    }

    const ns = main.gen_args.types_namespace;
    try writer.print(
        \\
        \\const Fixed = {s}.Fixed;
        \\const FD = {s}.FD;
        \\const AnonymousEvent = {s}.AnonymousEvent;
        \\const RequestError = {s}.RequestError;
        \\const DecodeError = {s}.DecodeError;
        \\const decodeEvent = {s}.decodeEvent;
        \\const WaylandContext = {s}.WaylandContext;
        \\const sendRequestRaw = {s}.wire.sendRequestRaw;
        \\
        \\
        \\
        , .{ns, ns, ns, ns, ns, ns, ns, ns});

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
        \\pub const {} = struct {{
        \\    id: u32,
        \\    version: u32 = {d},
        \\
        \\    const Self = @This();
        \\
        \\    pub const interface_str = "{s}";
        \\
        \\    pub const opcode = 
        , .{interfaceDecl(interface.name), interface.version, interface.name});
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
        \\    pub fn {}(self: Self, ctx: *const WaylandContext
        , .{camelCase(request.name)});

    const return_arg: ?Arg = try generateRequestArgs(request.args, writer);
    if (return_arg) |arg| {
        if (arg.type.new_id.interface) |interface| {
            try writer.print(
                \\) RequestError!{} {{
                \\        const new_obj = {} {{
                \\            .id = {}
                \\        }};
                \\
                \\
                , .{interfaceFmt(interface),
                    interfaceFmt(interface),
                    escBadName(arg.name)});
        } else {
            try writer.print(
                \\) RequestError!{s}_type {{
                \\        const new_obj = {s}_type {{
                \\            .id = {},
                \\            .version = {s}_version
                \\        }};
                \\
                \\
                , .{arg.name, arg.name, escBadName(arg.name), arg.name});
        }
    } else {
        try writer.writeAll(") RequestError!void {\n");
    }

    if (request.since) |v| {
        try writer.print(
            "        if (self.version < {d}) return error.VersionError;\n\n"
            , .{v});
    }

    // TODO generate interface type validation for new_id w/o specific interface
    
    try writer.writeAll("        const args = ");
    try generateRawArgs(request.args, writer);
    try writer.writeAll(";\n");

    try writer.writeAll("        const fds = ");
    try generateFDs(request.args, writer);
    try writer.writeAll(";\n");

    try writer.print(
        \\        const socket = ctx.socket.handle;
        \\        const op = Self.opcode.request.{};
        \\        const iov_len = {d};
        \\        try sendRequestRaw(socket, self.id, op, iov_len, args, fds);
        \\
        , .{escBadName(request.name), calcIOVLen(request.args)});

    if (return_arg) |_| {
        try writer.writeAll("        return new_obj;\n");
    }

    try writer.writeAll("    }\n\n");
}

fn generateFDs(args: []Arg, writer: anytype) !void {
    try writer.writeAll("[_]FD{ ");
    for (args) |arg| {
        switch (arg.type) {
            .fd => try writer.print("{}, ", .{escBadName(arg.name)}),
            else => {},
        }
    }
    try writer.writeAll("}");
}

fn generateRawArgs(args: []Arg, writer: anytype) !void {
    try writer.writeAll(".{\n");
    for (args) |arg| {
        switch (arg.type) {
            .int, .uint, .fixed => {
                try writer.print(
                    \\            {},
                    \\
                    , .{escBadName(arg.name)});
            },
            .array => {
                try writer.print(
                    \\            @as(u32, @intCast({}.len)), {},
                    \\
                    , .{escBadName(arg.name), escBadName(arg.name)});
            },
            .string => |meta| if (meta.allow_null) {
                try writer.print(
            \\            @as(u32, @intCast(if ({}) |str| str.len + 1 else 0)),
            \\            {},
            \\
                    , .{escBadName(arg.name), escBadName(arg.name)});
            } else {
                try writer.print(
                    \\            @as(u32, @intCast({}.len + 1)),
                    \\            {},
                    \\
                    , .{escBadName(arg.name), escBadName(arg.name)});
            },
            .object => |meta| {
                if (meta.allow_null) {
                    if (meta.interface != null) {
                        try writer.print(
                            \\            if ({}) |obj| obj.id else 0,
                            \\
                            , .{escBadName(arg.name)});
                    } else {
                        try writer.print(
                            \\            {} orelse 0,
                            \\
                            , .{escBadName(arg.name)});
                    }
                } else {
                    if (meta.interface != null) {
                        try writer.print(
                            \\            {}.id,
                            \\
                            , .{escBadName(arg.name)});
                    } else {
                        try writer.print(
                            \\            {},
                            \\
                            , .{escBadName(arg.name)});
                    }
                }
            },
            .new_id => |meta| {
                if (meta.interface) |_| {
                    try writer.print(
                        \\            {},
                        \\
                        , .{escBadName(arg.name)});
                } else {
                    try writer.print(
            \\            @as(u32, @intCast({s}_type.interface_str.len + 1)),
            \\            @as([:0]const u8, {s}_type.interface_str),
            \\            {s}_version,
            \\            {},
            \\
                    , .{arg.name, arg.name, arg.name, escBadName(arg.name)});
                }
            },
            .enum_ => try writer.print(
                \\            @intFromEnum({}),
                \\
                , .{escBadName(arg.name)}),
            .fd => {},
        }
    }
    try writer.writeAll("        }");
}

/// Returns the max length needed for the IOVec array given args.
fn calcIOVLen(args: []Arg) usize {
    var len: usize = 1;
    for (args) |arg| {
        switch (arg.type) {
            .array => len += 3,
            .string => len += 3,
            .new_id => |meta| {
                if (meta.interface) |_| {
                    len += 1;
                } else {
                    len += 5;
                }
            },
            .fd => {},
            else => len += 1,
        }
    }
    return len;
}

/// Writes args for a request returning a possible return argument.
fn generateRequestArgs(args: []Arg, writer: anytype) !?Arg {
    var new_id_count: usize = 0;
    var return_arg: Arg = undefined;
    for (args) |arg| {
        switch (arg.type) {
            .int => try writeArg(arg.name, "i32", writer),
            .uint => try writeArg(arg.name, "u32", writer),
            .fixed => try writeArg(arg.name, "Fixed", writer),
            .fd => try writeArg(arg.name, "FD", writer),
            .array => try writeArg(arg.name, "[]const u8", writer),
            .string => |meta| if (meta.allow_null) {
                try writeArg(arg.name, "?[:0]const u8", writer);
            } else {
                try writeArg(arg.name, "[:0]const u8", writer);
            },
            .object => |meta| {
                try writer.print(", {}: ", .{escBadName(arg.name)});
                if (meta.allow_null) {
                    try writer.writeByte('?');
                }
                if (meta.interface) |interface| {
                    try writer.print("{}", .{interfaceFmt(interface)});
                } else {
                    try writer.writeAll("u32");
                }
            },
            .new_id => |meta| {
                new_id_count += 1;
                return_arg = arg;
                if (meta.interface) |_| {
                    try writer.print(", {s}: u32", .{arg.name});
                } else {
                    try writer.print(
                        \\, {s}_type: type, {s}_version: u32, {}: u32
                        , .{arg.name, arg.name, escBadName(arg.name)});
                }
            },
            .enum_ => |meta| {
                try writer.print(
                    \\, {}: {}
                , .{escBadName(arg.name), enumType(meta.enum_name)});
            },
        }
    }

    if (new_id_count == 1) return return_arg;
    return null;
}

fn writeArg(name: []const u8, type_name: []const u8, writer: anytype) !void {
    try writer.print(", {}: {s}", .{escBadName(name), type_name});
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
        \\        if (event.self_id != self.id) return null;
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
                try writer.print("{}", .{interfaceFmt(interface)});
            } else {
                try writer.writeAll("u32");
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

fn interfaceFmt(bytes: []const u8) std.fmt.Formatter(interfaceFormatFn) {
    return .{ .data = bytes };
}

fn interfaceDecl(bytes: []const u8) std.fmt.Formatter(interfaceDeclFormatFn) {
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
        try writer.print(
            "{}.{}",
            .{interfaceFmt(interface), titleCase(enum_type)});
    } else {
        try writer.print("{}", .{titleCase(bytes)});
    }
}

fn interfaceFormatFn(
    bytes: []const u8,
    comptime _: []const u8,
    _: std.fmt.FormatOptions,
    writer: anytype
) !void {
    for (main.gen_args.replaces) |replace| {
        if (std.mem.startsWith(u8, bytes, replace.prefix)) {
            try writer.print(
                "{s}.{}"
                , .{replace.name, titleCase(bytes[replace.prefix.len..])});
            return;
        }
    }
    try writer.print("{}", .{titleCase(bytes)});
}

fn interfaceDeclFormatFn(
    bytes: []const u8,
    comptime _: []const u8,
    _: std.fmt.FormatOptions,
    writer: anytype
) !void {
    for (main.gen_args.replaces) |replace| {
        if (std.mem.startsWith(u8, bytes, replace.prefix)) {
            try writer.print("{}", .{titleCase(bytes[replace.prefix.len..])});
            return;
        }
    }
    try writer.print("{}", .{titleCase(bytes)});
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
