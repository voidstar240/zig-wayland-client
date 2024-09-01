const std = @import("std");
const types = @import("types.zig");

const Allocator = std.mem.Allocator;

const Protocol = types.Protocol;
const Interface = types.Interface;
const Method = types.Method;
const Arg = types.Arg;
const Enum = types.Enum;
const Entry = types.Entry;

const eql = std.mem.eql;

// TODO use a prefix array or something to allow for multiple prefixes.
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
    interface.name = try cleanInterfaceName(interface.name, prefix, alloc);
    for (interface.requests) |*request| {
        try cleanMethod(request, prefix, alloc);
    }
    for (interface.events) |*event| {
        try cleanMethod(event, prefix, alloc);
    }
    for (interface.enums) |*enum_| {
        try cleanEnum(enum_, alloc);
    }
}

fn cleanInterfaceName(name: []const u8, prefix: ?[]const u8, alloc: Allocator) ![]const u8 {
    const no_pre = if (prefix) |pre|
        // Turns out prefixes are actually really important in wayland protocol,
        // so we can't just erase them.
        // TODO create InterfaceType type which contains prefix and name
        // return that instead of removing prefix completely. This will allow
        // fancy importing with usingnamespace resulting in syntax like
        // wl.Display or xdg.Positioner.
        removePrefix(name, pre)
    else
        name;
    return toCamelOrPascalCase(no_pre, true, alloc);
}

pub fn cleanMethod(method: *Method, prefix: ?[]const u8, alloc: Allocator) !void {
    const tmp = try toCamelOrPascalCase(method.name, false, alloc);
    method.name = try escapeKeyword(tmp, alloc);
    for (method.args) |*arg| {
        try cleanArg(arg, prefix, alloc);
    }
}

pub fn cleanArg(arg: *Arg, prefix: ?[]const u8, alloc: Allocator) !void {
    switch (arg.type) {
        .new_id => |*meta| {
            if (meta.interface == null) return;
            const tmp = if (prefix) |pre|
                removePrefix(meta.interface.?, pre)
            else
                meta.interface.?;
            meta.interface = try toCamelOrPascalCase(tmp, true, alloc);
        },
        .object => |*meta| {
            if (meta.interface == null) return;
            const tmp = if (prefix) |pre|
                removePrefix(meta.interface.?, pre)
            else
                meta.interface.?;
            meta.interface = try toCamelOrPascalCase(tmp, true, alloc);
        },
        .enum_ => |*meta| {
            // TODO this should be its own function
            if (std.mem.indexOfScalar(u8, meta.enum_name, '.')) |i| {
                const interface = try cleanInterfaceName(meta.enum_name[0..i], prefix, alloc);
                const enum_name = try toCamelOrPascalCase(meta.enum_name[(i+1)..], true, alloc);
                // also this triple allocs. 2 above 1 here. refactor needed
                var new_name = try alloc.alloc(u8, interface.len + 1 + enum_name.len);
                @memcpy(new_name[0..interface.len], interface);
                new_name[interface.len] = '.';
                @memcpy(new_name[interface.len + 1..], enum_name);
                meta.enum_name = new_name;
            } else {
                meta.enum_name = try toCamelOrPascalCase(meta.enum_name, true, alloc);
            }
        },
        else => {},
    }
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
