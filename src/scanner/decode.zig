const std = @import("std");
const xml = @import("scanner.zig");
const types = @import("types.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const Scanner = xml.Scanner;
const Token = xml.Token;

const Version = types.Version;
const Protocol = types.Protocol;
const Interface = types.Interface;
const Method = types.Method;
const Arg = types.Arg;
const Enum = types.Enum;
const Entry = types.Entry;

const eql = std.mem.eql;

pub fn decodeProtocol(scanner: *Scanner, alloc: Allocator) !Protocol {
    var protocol = Protocol {
        .name = undefined,
        .copyright = null,
        .description = null,
        .interfaces = undefined,
    };

    var token = try scanner.next();
    if (!token.expectStartTagName("protocol")) return error.NoStartTag;
    token = try scanner.next();

    protocol.name = token.expectAttributeName("name") orelse
        return error.NoName;
    token = try scanner.next();

    protocol.copyright = decodeCopyright(scanner, &token) catch |err| 
        switch (err) {
            error.NoStartTag => null,
            else => return err,
        };

    protocol.description = decodeDescription(scanner, &token) catch |err| 
        switch (err) {
            error.NoStartTag => null,
            else => return err,
        };

    var interfaces = ArrayList(Interface).init(alloc);
    errdefer interfaces.deinit();
    while (token.expectStartTagName("interface")) {
        const interface = try decodeInterface(scanner, &token, alloc);
        interfaces.append(interface) catch return error.AppendError;
    }
    if (interfaces.items.len == 0) return error.NoInterfaces;
    protocol.interfaces = interfaces.toOwnedSlice() catch
        return error.ToSliceError;

    if (!token.expectEndTagName("protocol"))
        return error.NoEndTag;
    token = try scanner.next();

    return protocol;
}

pub fn decodeCopyright(scanner: *Scanner, token: *Token) ![]const u8 {
    if (!token.expectStartTagName("copyright"))
        return error.NoStartTag;
    token.* = try scanner.next();
    
    const copyright = token.expectText() orelse
        return error.NoText;
    token.* = try scanner.next();

    if (!token.expectEndTagName("copyright"))
        return error.NoEndTag;
    token.* = try scanner.next();

    return copyright;
}

// TODO make description struct that contains body and summary
pub fn decodeDescription(scanner: *Scanner, token: *Token) ![]const u8 {
    var empty_tag = false;
    if (!token.expectStartTagName("description")) {
        if (!token.expectEmptyTagName("description"))
            return error.NoStartTag;
        empty_tag = true;
    }
    token.* = try scanner.next();

    const summary = token.expectAttributeName("summary") orelse
        return error.NoSummary;
    _ = summary;
    token.* = try scanner.next();

    if (empty_tag) return "No Text";

    const description = token.expectText() orelse
        return error.NoText;
    token.* = try scanner.next();

    if (!token.expectEndTagName("description"))
        return error.NoEndTag;
    token.* = try scanner.next();

    return description;
}

pub fn decodeInterface(
    scanner: *Scanner,
    token: *Token,
    alloc: Allocator
) !Interface {
    var interface = Interface {
        .name = undefined,
        .version = undefined,
        .description = null,
        .requests = undefined,
        .events = undefined,
        .enums = undefined,
    };

    if (!token.expectStartTagName("interface"))
        return error.NoStartTag;
    token.* = try scanner.next();

    var got_name = false;
    var got_version = false;
    while (token.expectAttribute()) |attr| : (token.* = try scanner.next()) {
        if (eql(u8, attr.name, "name")) {
            if (got_name) return error.TooManyNames;
            got_name = true;
            interface.name = attr.value;
        } else if (eql(u8, attr.name, "version")) {
            if (got_version) return error.TooManyVersions;
            got_version = true;
            interface.version = std.fmt.parseInt(u8, attr.value, 0) catch |err|
                switch (err) {
                    error.Overflow => return error.VersionOverflow,
                    error.InvalidCharacter => return error.InvalidVersion,
                };
        } else return error.InvalidAttribute;
    }

    if (!got_name) return error.NoName;
    if (!got_version) return error.NoVersion;

    interface.description = decodeDescription(scanner, token) catch |err| 
        switch (err) {
            error.NoStartTag => null,
            else => return err,
        };

    var requests = ArrayList(Method).init(alloc);
    errdefer requests.deinit();
    var events = ArrayList(Method).init(alloc);
    errdefer events.deinit();
    var enums = ArrayList(Enum).init(alloc);
    errdefer enums.deinit();
    while (!token.expectEndTagName("interface")) {
        if (token.expectStartTagName("request")) {
            const request = try decodeMethod(scanner, token, alloc);
            requests.append(request) catch return error.AppendError;
        } else if (token.expectStartTagName("event")) {
            const event = try decodeMethod(scanner, token, alloc);
            events.append(event) catch return error.AppendError;
        } else if (token.expectStartTagName("enum")) {
            const enum_ = try decodeEnum(scanner, token, alloc);
            enums.append(enum_) catch return error.AppendError;
        } else return error.NoEndTag;
    }
    token.* = try scanner.next();

    if (requests.items.len + events.items.len + enums.items.len == 0) {
        return error.NoMembers;
    }

    interface.requests = requests.toOwnedSlice() catch
        return error.ToSliceError;
    interface.events = events.toOwnedSlice() catch
        return error.ToSliceError;
    interface.enums = enums.toOwnedSlice() catch
        return error.ToSliceError;

    return interface;
}

pub fn decodeMethod(
    scanner: *Scanner,
    token: *Token,
    alloc: Allocator
) !Method {
    var method = Method {
        .name = undefined,
        .is_destructor = false,
        .since = null,
        .dep_since = null,
        .description = null,
        .args = undefined,
    };

    var is_request = true;
    var empty_tag = false;
    if (token.expectStartTag()) |name| {
        if (eql(u8, name, "event")) {
            is_request = false;
        } else if (!eql(u8, name, "request")) {
            return error.NoStartTag;
        }
    } else if (token.expectEmptyTag()) |name| {
        empty_tag = true;
        if (eql(u8, name, "event")) {
            is_request = false;
        } else if (!eql(u8, name, "request")) {
            return error.NoStartTag;
        }
    } else return error.NoStartTag;
    token.* = try scanner.next();

    var got_name = false;
    while (token.expectAttribute()) |attr| : (token.* = try scanner.next()) {
        if (eql(u8, attr.name, "name")) {
            if (got_name) return error.TooManyNames;
            got_name = true;
            method.name = attr.value;
        } else if (eql(u8, attr.name, "type")) {
            if (method.is_destructor) return error.TooManyTypes;
            if (eql(u8, attr.value, "destructor")) {
                method.is_destructor = true;
            } else return error.UnrecognizedType;
        } else if (eql(u8, attr.name, "since")) {
            if (method.since != null) return error.TooManySinces;
            method.since = std.fmt.parseInt(u8, attr.value, 0) catch |err|
                switch (err) {
                    error.Overflow => return error.SinceOverflow,
                    error.InvalidCharacter => return error.InvalidSince,
                };
        } else if (eql(u8, attr.name, "deprecated-since")) {
            if (method.dep_since != null) return error.TooManyDeprecatedSinces;
            method.since = std.fmt.parseInt(u8, attr.value, 0) catch |err|
                switch (err) {
                    error.Overflow => return error.DeprecatedSinceOverflow,
                    error.InvalidCharacter => {
                        return error.InvalidDeprecatedSince;
                    },
                };
        } else return error.InvalidAttribute;
    }
    if (!got_name) return error.NoName;

    if (empty_tag) return method;

    method.description = decodeDescription(scanner, token) catch |err| 
        switch (err) {
            error.NoStartTag => null,
            else => return err,
        };

    var args = ArrayList(Arg).init(alloc);
    errdefer args.deinit();
    while (token.expectStartTagName("arg") or token.expectEmptyTagName("arg")) {
        const arg = try decodeArg(scanner, token);
        args.append(arg) catch return error.AppendError;
    }
    method.args = args.toOwnedSlice() catch return error.ToSliceError;

    if (is_request) {
        if (!token.expectEndTagName("request")) return error.NoEndTag;
    } else {
        if (!token.expectEndTagName("event")) return error.NoEndTag;
    }
    token.* = try scanner.next();

    return method;
}

pub fn decodeArg(scanner: *Scanner, token: *Token) !Arg {
    var arg = Arg {
        .name = undefined,
        .type = undefined,
        .summary = null,
        .description = null,
    };

    var empty_tag = false;
    if (!token.expectStartTagName("arg")) {
        if (!token.expectEmptyTagName("arg"))
            return error.NoStartTag;
        empty_tag = true;
    } 
    token.* = try scanner.next();

    var build = struct {
        name: bool = false,
        type: bool = false,
        interface: ?[]const u8 = null,
        allow_null: ?bool = null,
        enum_: ?[]const u8 = null,
    }{};

    while (token.expectAttribute()) |attr| : (token.* = try scanner.next()) {
        if (eql(u8, attr.name, "name")) {
            if (build.name) return error.TooManyNames;
            build.name = true;
            arg.name = attr.value;
        } else if (eql(u8, attr.name, "type")) {
            if (build.type) return error.TooManyTypes;
            build.type = true;
            arg.type = parseArgType(attr.value) orelse
                return error.InvalidType;
        } else if (eql(u8, attr.name, "summary")) {
            if (arg.summary != null) return error.TooManySummaries;
            arg.summary = attr.value;
        } else if (eql(u8, attr.name, "interface")) {
            if (build.interface != null) return error.TooManyInterfaces;
            build.interface = attr.value;
        } else if (eql(u8, attr.name, "allow-null")) {
            if (build.allow_null != null) return error.TooManyAllowNulls;
            build.allow_null = parseBool(attr.value) orelse
                return error.InvalidAllowNull;
        } else if (eql(u8, attr.name, "enum")) {
            if (build.enum_ != null) return error.TooManyEnums;
            build.enum_ = attr.value;
        } else return error.InvalidAttribute;
    }

    if (!build.name) return error.NoName;
    if (!build.type) return error.NoType;

    switch (arg.type) {
        .int => {
            if (build.interface != null) return error.InterfaceInvalid;
            if (build.allow_null != null) return error.AllowNullInvalid;
            if (build.enum_) |enum_name| {
                arg.type = .{ .enum_ = .{
                    .enum_name = enum_name,
                    .is_signed = true,
                }};
            }
        },
        .uint => {
            if (build.interface != null) return error.InterfaceInvalid;
            if (build.allow_null != null) return error.AllowNullInvalid;
            if (build.enum_) |enum_name| {
                arg.type = .{ .enum_ = .{
                    .enum_name = enum_name,
                    .is_signed = true,
                }};
            }
        },
        .fixed => {
            if (build.interface != null) return error.InterfaceInvalid;
            if (build.allow_null != null) return error.AllowNullInvalid;
            if (build.enum_ != null) return error.EnumInvalid;
        },
        .array => {
            if (build.interface != null) return error.InterfaceInvalid;
            if (build.allow_null != null) return error.AllowNullInvalid;
            if (build.enum_ != null) return error.EnumInvalid;
        },
        .fd => {
            if (build.interface != null) return error.InterfaceInvalid;
            if (build.allow_null != null) return error.AllowNullInvalid;
            if (build.enum_ != null) return error.EnumInvalid;
        },
        .string => |*meta| {
            if (build.interface != null) return error.InterfaceInvalid;
            if (build.enum_ != null) return error.EnumInvalid;
            if (build.allow_null) |allow_null| {
                meta.allow_null = allow_null;
            }
        },
        .object => |*meta| {
            if (build.enum_ != null) return error.EnumInvalid;
            if (build.interface) |interface| {
                meta.interface = interface;
            }
            if (build.allow_null) |allow_null| {
                meta.allow_null = allow_null;
            }
        },
        .new_id => |*meta| {
            if (build.allow_null != null) return error.AllowNullInvalid;
            if (build.enum_ != null) return error.EnumInvalid;
            if (build.interface) |interface| {
                meta.interface = interface;
            }
        },
        .enum_ => unreachable,
    }

    if (empty_tag) return arg;

    arg.description = decodeDescription(scanner, token) catch |err|
        switch (err) {
            error.NoStartTag => null,
            else => return err,
        };

    if (!token.expectEndTagName("arg")) return error.NoEndTag;
    token.* = try scanner.next();

    return arg;
}

pub fn decodeEnum(scanner: *Scanner, token: *Token, alloc: Allocator) !Enum {
    var enm = Enum {
        .name = undefined,
        .since = null,
        .is_bit_field = false,
        .description = null,
        .entries = undefined,
    };

    var empty_tag = false;
    if (!token.expectStartTagName("enum")) {
        if (!token.expectEmptyTagName("enum"))
            return error.NoStartTag;
        empty_tag = true;
    } 
    token.* = try scanner.next();

    var got_name = false;
    while (token.expectAttribute()) |attr| : (token.* = try scanner.next()) {
        if (eql(u8, attr.name, "name")) {
            if (got_name) return error.TooManyNames;
            got_name = true;
            enm.name = attr.value;
        } else if (eql(u8, attr.name, "since")) {
            if (enm.since != null) return error.TooManySinces;
            enm.since = std.fmt.parseInt(u8, attr.value, 0) catch |err|
                switch (err) {
                    error.Overflow => return error.SinceOverflow,
                    error.InvalidCharacter => return error.InvalidSince,
                };
        } else if (eql(u8, attr.name, "bitfield")) {
            enm.is_bit_field = parseBool(attr.value) orelse
                return error.InvalidBitfield;
        } else return error.InvalidAttribute;
    }
    if (!got_name) return error.NoName;

    if (empty_tag) return enm;

    enm.description = decodeDescription(scanner, token) catch |err|
        switch (err) {
            error.NoStartTag => null,
            else => return err,
        };

    var entries = ArrayList(Entry).init(alloc);
    errdefer entries.deinit();
    while (token.expectStartTagName("entry") or token.expectEmptyTagName("entry")) {
        const entry = try decodeEntry(scanner, token);
        entries.append(entry) catch return error.AppendError;
    }
    enm.entries = entries.toOwnedSlice() catch return error.ToSliceError;

    if (!token.expectEndTagName("enum")) return error.NoEndTag;
    token.* = try scanner.next();

    return enm;
}

pub fn decodeEntry(scanner: *Scanner, token: *Token) !Entry {
    var entry = Entry {
        .name = undefined,
        .value = 0,
        .summary = null,
        .since = null,
        .dep_since = null,
        .description = null,
    };

    var empty_tag = false;
    if (!token.expectStartTagName("entry")) {
        if (!token.expectEmptyTagName("entry"))
            return error.NoStartTag;
        empty_tag = true;
    } 
    token.* = try scanner.next();

    var got_name = false;
    var got_value = false;
    while (token.expectAttribute()) |attr| : (token.* = try scanner.next()) {
        if (eql(u8, attr.name, "name")) {
            if (got_name) return error.TooManyNames;
            got_name = true;
            entry.name = attr.value;
        } else if (eql(u8, attr.name, "value")) {
            if (got_value) return error.TooManyValues;
            got_value = true;
            entry.value = std.fmt.parseInt(u32, attr.value, 0) catch |err|
                switch (err) {
                    error.Overflow => return error.ValueOverflow,
                    error.InvalidCharacter => return error.InvalidValue,
                };
        } else if (eql(u8, attr.name, "summary")) {
            if (entry.summary != null) return error.TooManySummaries;
            entry.summary = attr.value;
        } else if (eql(u8, attr.name, "since")) {
            entry.since = std.fmt.parseInt(u8, attr.value, 0) catch |err|
                switch (err) {
                    error.Overflow => return error.SinceOverflow,
                    error.InvalidCharacter => return error.InvalidSince,
                };
        } else if (eql(u8, attr.name, "deprecated-since")) {
            entry.dep_since = std.fmt.parseInt(u8, attr.value, 0) catch |err|
                switch (err) {
                    error.Overflow => return error.DeprecatedSinceOverflow,
                    error.InvalidCharacter => {
                        return error.InvalidDeprecatedSince;
                    },
                };
        } else return error.InvalidAttriute;
    }
    if (!got_name) return error.NoName;
    if (!got_value) return error.NoValue;

    if (empty_tag) return entry;

    entry.description = decodeDescription(scanner, token) catch |err|
        switch (err) {
            error.NoStartTag => null,
            else => return err,
        };

    if (!token.expectEndTagName("entry")) return error.NoEndTag;
    token.* = try scanner.next();

    return entry;
}

fn parseArgType(str: []const u8) ?Arg.Type {
    if (eql(u8, str, "int")) {
        return .int;
    } else if (eql(u8, str, "uint")) {
        return .uint;
    } else if (eql(u8, str, "fixed")) {
        return .fixed;
    } else if (eql(u8, str, "string")) {
        return .{ .string = .{
            .allow_null = false
        }};
    } else if (eql(u8, str, "object")) {
        return .{ .object = .{
            .allow_null = false,
            .interface = null
        }};
    } else if (eql(u8, str, "new_id")) {
        return .{ .new_id = .{
            .interface = null
        }};
    } else if (eql(u8, str, "array")) {
        return .array;
    } else if (eql(u8, str, "fd")) {
        return .fd;
    } else return null;
}

fn parseBool(str: []const u8) ?bool {
    if (eql(u8, str, "true")) {
        return true;
    } else if (eql(u8, str, "false")) {
        return false;
    } else return null;
}
