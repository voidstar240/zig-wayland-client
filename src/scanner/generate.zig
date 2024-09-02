const std = @import("std");
const types = @import("types.zig");

const Version = types.Version;
const Protocol = types.Protocol;
const Interface = types.Interface;
const Method = types.Method;
const Arg = types.Arg;
const Enum = types.Enum;
const Entry = types.Entry;

pub fn generateProtocol(protocol: *const Protocol, writer: anytype) !void {
    try writer.print("const util = @import(\"util.zig\");\n", .{});
    try writer.print("const ints = struct {{\n", .{});
    try writer.print("    usingnamespace @import(\"protocol.zig\");\n", .{});
    // TODO allow build script dependency imports
    try writer.print("}};\n\n", .{});

    try writer.print("const Object = util.Object;\n", .{});
    try writer.print("const Fixed = util.Fixed;\n", .{});
    try writer.print("const FD = util.FD;\n\n", .{});
    for (protocol.interfaces) |*interface| {
        try generateInterface(interface, writer);
    }
}

fn generateInterface(interface: *const Interface, writer: anytype) !void {
    try writer.print("pub const ", .{});
    try writeName(interface.name, writer);
    try writer.print(" = struct {{\n", .{});
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
        try writer.print("            pub const ", .{});
        try writeName(request.name, writer);
        try writer.print(": u16 = {d};\n", .{i});
    }
    try writer.print(
        \\        }};
        \\        pub const event = struct {{
        \\
        , .{});
    for (interface.events, 0..) |*event, i| {
        try writer.print("            pub const ", .{});
        try writeName(event.name, writer);
        try writer.print(": u16 = {d};\n", .{i});
    }
    try writer.print("        }};\n    }};\n\n", .{});
}

fn generateRequest(request: *const Method, writer: anytype) !void {
    try writer.print("    pub fn ", .{});
    try writeMethodName(request.name, writer);
    try writer.print("(self: @This()", .{});

    const return_obj = newIdArgCount(request) == 1;
    var return_interface: ?[]const u8 = null;
    for (request.args) |arg| {
        if (arg.type == .new_id) {
            if (return_obj) {
                return_interface = arg.type.new_id.interface;
                continue;
            }
        }
        try writer.print(", ", .{});
        try writeName(arg.name, writer);
        try writer.print(": ", .{});
        switch (arg.type) {
            .int => try writer.print("i32", .{}),
            .uint => try writer.print("u32", .{}),
            .fixed => try writer.print("Fixed", .{}),
            .array => try writer.print("[]const u8", .{}),
            .fd => try writer.print("FD", .{}),
            .string => |meta| {
                if (meta.allow_null) try writer.print("?", .{});
                try writer.print("[:0]const u8", .{});
            },
            .object => |meta| {
                if (meta.allow_null) try writer.print("?", .{});
                if (meta.interface) |name| {
                    try writer.print("ints.", .{});
                    try writeName(name, writer);
                } else {
                    try writer.print("Object", .{});
                }
            },
            .new_id => |meta| {
                if (meta.interface) |name| {
                    try writer.print("ints.", .{});
                    try writeName(name, writer);
                } else {
                    try writer.print("Object", .{});
                }
            },
            .enum_ => |meta| {
                if (std.mem.indexOfScalar(u8, meta.enum_name, '.')) |i| {
                    try writer.print("ints.", .{});
                    try writeName(meta.enum_name[0..i], writer);
                    try writer.print(".", .{});
                    try writeEnumName(meta.enum_name[(i + 1)..], writer);
                } else {
                    try writeEnumName(meta.enum_name, writer);
                }
            },
        }
    }

    if (return_obj) {
        if (return_interface) |name| {
            try writer.print(") ints.", .{});
            try writeName(name, writer);
            try writer.print(" {{\n", .{});
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
    try writer.print("    pub const ", .{});
    try writeEnumName(enum_.name, writer);
    try writer.print(" = enum(u32) {{\n", .{});
    for (enum_.entries) |*entry| {
        try writer.print("        ", .{});
        try writeName(entry.name, writer);
        try writer.print(" = {d},", .{entry.value});
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

// Prints `name` to `writer` potentially escaping both parts of name if needed.
fn writeCompoundName(name: []const u8, writer: anytype) !void {
    if (std.mem.indexOfScalar(u8, name, '.')) |i| {
        try writer.print("ints.", .{});
        try writeName(name[0..i], writer);
        try writer.print(".", .{});
        try writeEnumName(name[(i + 1)..], writer);
    } else {
        try writeName(name, writer);
    }
}

/// Prints `name` to `writer` escaping `name` if needed.
fn writeName(name: []const u8, writer: anytype) !void {
    if (isBadName(name)) {
        try writer.print("@\"{s}\"", .{name});
    } else {
        try writer.print("{s}", .{name});
    }
}

/// If `name` is an invalid identifier returns true.
fn isBadName(name: []const u8) bool {
    if (name.len == 0) return true;

    const keywords = [_][]const u8 {
        "addrspace", "align", "allowzero", "and", "anyframe", "anytype", "asm",
        "async", "await", "break", "callconv", "catch", "comptime", "const",
        "continue", "defer", "else", "enum", "errdefer", "error", "export",
        "extern", "fn", "for", "if", "inline", "noalias", "nosuspend",
        "noinline", "opaque", "or", "orelse", "packed", "pub", "resume",
        "return", "linksection", "struct", "suspend", "switch", "test",
        "threadlocal", "try", "union", "unreachable", "usingnamespace", "var",
        "volatile", "while"
    };

    inline for (keywords) |keyword| {
        if (std.mem.eql(u8, name, keyword)) {
            return true;
        }
    }

    if (std.ascii.isDigit(name[0])) {
        return true;
    }
    
    return false;
}

/// Prints `name` in Pascal case.
fn writeEnumName(name: []const u8, writer: anytype) !void {
    var word_start = true;
    for (name) |c| {
        if (c == '_') {
            word_start = true;
            continue;
        }
        if (word_start) {
            try writer.print("{c}", .{std.ascii.toUpper(c)});
        } else {
            try writer.print("{c}", .{c});
        }
        word_start = false;
    }
}

/// Prints `name` in camel case.
fn writeMethodName(name: []const u8, writer: anytype) !void {
    const bad = isBadName(name);
    if (bad) try writer.print("@\"", .{});

    var word_start = false;
    for (name) |c| {
        if (c == '_') {
            word_start = true;
            continue;
        }
        if (word_start) {
            try writer.print("{c}", .{std.ascii.toUpper(c)});
        } else {
            try writer.print("{c}", .{c});
        }
        word_start = false;
    }

    if (bad) try writer.print("\"", .{});
}
