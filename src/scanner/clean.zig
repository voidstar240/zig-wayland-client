const std = @import("std");
const types = @import("types.zig");

const Allocator = std.mem.Allocator;

const Protocol = types.Protocol;
const Interface = types.Interface;
const Method = types.Method;
const Enum = types.Enum;

const eql = std.mem.eql;

pub fn cleanProtocol(
    protocol: *Protocol,
    prefix: ?[]const u8,
    alloc: Allocator
) !void {
    for (protocol.interfaces) |*interface| {
        try cleanInterface(interface, prefix, alloc);
    }
}

pub fn cleanInterface(
    interface: *Interface,
    prefix: ?[]const u8,
    alloc: Allocator
) !void {
    const tmp = if (prefix) |pre|
        removePrefix(interface.name, pre)
    else
        interface.name;
    interface.name = try toCamelOrPascalCase(tmp, true, alloc);
    for (interface.requests) |*request| {
        try cleanMethod(request, alloc);
    }
    for (interface.events) |*event| {
        try cleanMethod(event, alloc);
    }
    for (interface.enums) |*enum_| {
        try cleanEnum(enum_, alloc);
    }
}

pub fn cleanMethod(method: *Method, alloc: Allocator) !void {
    const tmp = try toCamelOrPascalCase(method.name, false, alloc);
    method.name = try escapeKeyword(tmp, alloc);
}

pub fn cleanEnum(enum_: *Enum, alloc: Allocator) !void {
    enum_.name = try toCamelOrPascalCase(enum_.name, true, alloc);
    for (enum_.entries) |*entry| {
        entry.name = try escapeInvalidIdentifier(entry.name, alloc);
    }
}

pub fn cleanParsedText(text: []const u8, alloc: Allocator) ![]const u8 {
    // TODO implement parsed text cleaning
    _ = alloc;
    return text;
}

/// Removes `prefix` from `name` if `name` contains `prefix`.
pub fn removePrefix(name: []const u8, prefix: []const u8) []const u8 {
    if (name.len >= prefix.len) {
        if (std.mem.eql(u8, name[0..prefix.len], prefix)) {
            return name[prefix.len..];
        }
    }
    return name;
}

/// Converts `name` to camel or pascal case given `pascal`.
pub fn toCamelOrPascalCase(
    name: []const u8,
    pascal: bool,
    alloc: Allocator
) ![]const u8 {
    var tmp_name = name;
    while (tmp_name.len > 0 and tmp_name[0] == '_') {
        tmp_name = tmp_name[1..];
    }
    while (tmp_name.len > 0 and tmp_name[tmp_name.len - 1] == '_') {
        tmp_name = tmp_name[0..(tmp_name.len - 1)];
    }

    var new_len = tmp_name.len;
    for (tmp_name) |c| {
        if (c == '_') new_len -= 1;
    }
    if (new_len == 0) return "";

    var new_name = try alloc.alloc(u8, new_len);
    var i: usize = 0;
    var next_upper = pascal;
    for (tmp_name) |c| {
        if (c == '_') {
            next_upper = true;
            continue;
        }
        if (next_upper) {
            new_name[i] = std.ascii.toUpper(c);
            next_upper = false;
        } else {
            new_name[i] = c;
        }
        i += 1;
    }
    return new_name;
}

/// If `name` is a zig keyword return `name` wrapped in @"...".
fn escapeKeyword(name: []const u8, alloc: Allocator) ![]const u8 {
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
        if (eql(u8, name, keyword)) {
            return escapeName(name, alloc);
        }
    }
    
    return name;
}

/// If `name` if an invalid identifier return `name` wrapped in @"...".
fn escapeInvalidIdentifier(name: []const u8, alloc: Allocator) ![]const u8 {
    if (name.len == 0) return name;
    if (std.ascii.isDigit(name[0])) {
        return escapeName(name, alloc);
    }
    return name;
}

/// Escapes `name` with @"...".
fn escapeName(name: []const u8, alloc: Allocator) ![]const u8 {
    const new = try alloc.alloc(u8, name.len + 3);
    new[0] = '@';
    new[1] = '"';
    new[new.len - 1] = '"';
    @memcpy(new[2..(new.len - 1)], name);
    return new;
}
