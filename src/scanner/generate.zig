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
        try writeParsedText(copyright, "// ", writer);
        try writer.print("\n", .{});
    }

    try writer.print("const util = @import(\"util.zig\");\n", .{});
    try writer.print("const ints = struct {{\n", .{});
    try writer.print("    usingnamespace @import(\"protocol.zig\");\n", .{});
    for (dependencies) |dep| {
        try writer.print("    usingnamespace @import(\"{s}\");\n", .{dep});
    }
    try writer.print("}};\n\n", .{});

    try writer.print("const Object = util.Object;\n", .{});
    try writer.print("const Fixed = util.Fixed;\n", .{});
    try writer.print("const FD = util.FD;\n", .{});
    try writer.print("const WaylandState = util.WaylandState;\n\n\n", .{});

    for (protocol.interfaces) |*interface| {
        try generateInterface(interface, writer);
    }
}

fn generateInterface(interface: *const Interface, writer: anytype) !void {
    if (interface.description) |desc| {
        if (desc.body) |body| {
            try writeParsedText(body, "/// ", writer);
        }
    }
    try writer.print("pub const ", .{});
    try writeName(interface.name, writer);
    try writer.print(" = struct {{\n", .{});
    try writer.print("    id: u32,\n", .{});
    try writer.print("    global: *WaylandState,\n\n", .{});
    try writer.print("    const Self = @This();\n\n", .{});
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
    try writer.print("}};\n\n", .{});
}

fn generateOpcodes(interface: *const Interface, writer: anytype) !void {
    try writer.print("    pub const opcode = struct {{\n", .{});
    if (interface.requests.len > 0) {
        try writer.print("        pub const request = struct {{\n", .{});
    }
    for (interface.requests, 0..) |*request, i| {
        try writer.print("            pub const ", .{});
        try writeName(request.name, writer);
        try writer.print(": u16 = {d};\n", .{i});
    }
    if (interface.requests.len > 0) {
        try writer.print("        }};\n", .{});
    }
    if (interface.events.len > 0) {
        try writer.print("        pub const event = struct {{\n", .{});
    }
    for (interface.events, 0..) |*event, i| {
        try writer.print("            pub const ", .{});
        try writeName(event.name, writer);
        try writer.print(": u16 = {d};\n", .{i});
    }
    if (interface.events.len > 0) {
        try writer.print("        }};\n", .{});
    }
    try writer.print("    }};\n\n", .{});
}

fn generateRequest(request: *const Method, writer: anytype) !void {
    if (request.description) |desc| {
        if (desc.body) |body| {
            try writeParsedText(body, "    /// ", writer);
        }
    }
    try writer.print("    pub fn ", .{});
    try writeMethodName(request.name, writer);
    try writer.print("(self: Self", .{});

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
            try writer.print(") !ints.", .{});
            try writeName(name, writer);
            try writer.print(" {{\n", .{});

            try writer.print(
                \\        const new_id = self.global.nextObjectId();
                \\
                , .{});
            try writer.print("        const new_obj = ints.", .{});
            try writeName(name, writer);
            try writer.print(
                \\ {{
                \\            .id = new_id,
                \\            .global = self.global,
                \\        }};
                \\
                \\
                , .{});
        } else {
            try writer.print(") !Object {{\n", .{});

            try writer.print(
                \\        const new_id = self.global.nextObjectId();
                \\
                , .{});
            try writer.print(
                \\        const new_obj = Object {{
                \\            .id = new_id,
                \\            .global = self.global,
                \\        }};
                \\
                \\
                , .{});
        }
    } else {
        try writer.print(") !void {{\n", .{}); // TODO return specific error
    }

    try writer.print("        const op = Self.opcode.request.", .{});
    try writeName(request.name, writer);
    try writer.print(";\n", .{});

    try writer.print("        try self.global.sendRequest(self.id, op, .{{ ", .{});
    for (request.args) |arg| {
        if ((arg.type == .new_id) and return_obj) {
            try writer.print("new_id, ", .{});
            continue;
        }
        try writeName(arg.name, writer);
        try writer.print(", ", .{});
    }
    try writer.print("}});\n", .{});

    if (return_obj) {
        try writer.print("        return new_obj;\n", .{});
    }

    try writer.print("    }}\n\n", .{});
}

fn generateEvent(event: *const Method, writer: anytype) !void {
    if (event.description) |desc| {
        if (desc.body) |body| {
            try writeParsedText(body, "    /// ", writer);
        }
    }
    try writer.print("    const ", .{});
    try writeEnumName(event.name, writer);
    try writer.print("Callback = ", .{});
    try generateEventCallbackType(event, writer);
    try writer.print(";\n", .{});

    try writer.print("    pub fn set", .{});
    try writeEnumName(event.name, writer);
    try writer.print(
        \\Callback(self: Self, user_data: *anyopaque, callback: 
        , .{});
    try writeEnumName(event.name, writer);
    try writer.print("Callback) void {{\n", .{});
    try writer.print(
        \\        _ = self;
        \\        _ = user_data;
        \\        _ = callback;
        \\
        , .{});
    try writer.print("    }}\n\n", .{});
}

fn generateEventCallbackType(event: *const Method, writer: anytype) !void {
    try writer.print("*const fn (*anyopaque", .{});
    for (event.args) |arg| {
        // TODO abstract this into function
        switch (arg.type) {
            .int => try writer.print(", i32", .{}),
            .uint => try writer.print(", u32", .{}),
            .fixed => try writer.print(", Fixed", .{}),
            .array => try writer.print(", []const u8", .{}),
            .fd => try writer.print(", FD", .{}),
            .string => |meta| {
                try writer.print(", ", .{});
                if (meta.allow_null)
                    try writer.print("?", .{});
                try writer.print("[:0]const u8", .{});
            },
            .object => |meta| {
                try writer.print(", ", .{});
                if (meta.allow_null)
                    try writer.print("?", .{});
                if (meta.interface) |interface| {
                    try writer.print("ints.", .{});
                    try writeName(interface, writer);
                } else {
                    try writer.print("Object", .{});
                }
            },
            .new_id => |meta| {
                if (meta.interface) |interface| {
                    try writer.print(", ints.", .{});
                    try writeName(interface, writer);
                } else {
                    try writer.print(", Object", .{});
                }
            },
            .enum_ => |meta| {
                if (std.mem.indexOfScalar(u8, meta.enum_name, '.')) |i| {
                    try writer.print(", ints.", .{});
                    try writeName(meta.enum_name[0..i], writer);
                    try writer.print(".", .{});
                    try writeEnumName(meta.enum_name[(i + 1)..], writer);
                } else {
                    try writer.print(", ", .{});
                    try writeEnumName(meta.enum_name, writer);
                }
            },
        }
    }
    try writer.print(") void", .{});
}

fn generateEnum(enum_: *const Enum, writer: anytype) !void {
    if (enum_.description) |desc| {
        if (desc.body) |body| {
            try writeParsedText(body, "    /// ", writer);
        }
    }
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

/// Prints `text` with XML escape sequences properly escaped.
fn writeParsedText(
    text: []const u8,
    prefix: []const u8,
    writer: anytype
) !void {
    var rem_text = text;
    var i: usize = 0;
    var new_line = true;
    while (i < rem_text.len) {
        switch (rem_text[i]) {
            ' ', '\t' => if (new_line) {
                rem_text = rem_text[i+1..];
                i = 0;
            } else {
                i += 1;
            },
            '&' => {
                try writer.print("{s}{s}", .{prefix, rem_text[0..i]});
                rem_text = rem_text[i..];
                if (std.mem.eql(u8, rem_text[0..5], "&quot")) {
                    try writer.print("\"", .{});
                    rem_text = rem_text[5..];
                } else if (std.mem.eql(u8, rem_text[0..5], "&apos")) {
                    try writer.print("'", .{});
                    rem_text = rem_text[5..];
                } else if (std.mem.eql(u8, rem_text[0..3], "&lt")) {
                    try writer.print("<", .{});
                    rem_text = rem_text[3..];
                } else if (std.mem.eql(u8, rem_text[0..3], "&gt")) {
                    try writer.print(">", .{});
                    rem_text = rem_text[4..];
                } else if (std.mem.eql(u8, rem_text[0..4], "&amp")) {
                    try writer.print("&", .{});
                    rem_text = rem_text[4..];
                }
                new_line = false;
                i = 0;
            },
            '\n' => {
                try writer.print("{s}{s}", .{prefix, rem_text[0..i+1]});
                rem_text = rem_text[i+1..];
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
