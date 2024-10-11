////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//   This is the main file for the wayland scanner. The main file for the     //
//   wayland-client library is src/root.zig. All files in the src/scanner/    //
//   directory are used by the scanner only. The scanner is used during the   //
//   `update` build step to regenerate the wayland protocol files.            //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

const std = @import("std");

const types = @import("types.zig");
const xml = @import("scanner.zig");
const decode = @import("decode.zig");
const generate = @import("generate.zig");

pub var gen_args: GenArgs = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    if (args.len < 5) { return error.TooFewArgs; }

    const in_path = args[1];
    var in_file = try std.fs.cwd().openFile(in_path, .{});
    defer in_file.close();
    const in_data = try in_file.readToEndAlloc(alloc, 1048567); // 1 MB max size
    var scanner = xml.Scanner.init(in_data);

    var protocol = decode.decodeProtocol(&scanner, alloc) catch |err| {
        const pos = scanner.getCurPos();
        std.debug.print("\nERROR:\n  {s} at line {d} col {d}.\n",
            .{@errorName(err), pos.line, pos.col});
        scanner.printLineDebug(pos);
        std.debug.print("\n", .{});
        std.posix.exit(1);
    };

    const out_path = args[2];
    var out_file = try std.fs.cwd().createFile(out_path, .{});
    defer out_file.close();
    const writer = out_file.writer();

    var imports = std.ArrayList(Import).init(alloc);
    var replaces = std.ArrayList(Replace).init(alloc);
    outer: for (args[4..]) |arg| {
        var it = std.mem.tokenizeAny(u8, arg, &.{' ', ':'});
        const cmd = it.next() orelse return error.EmptyArg;
        if (std.mem.eql(u8, cmd, "-I")) {
            const name = it.next() orelse return error.NoName;
            const path = it.next() orelse return error.NoPath;
            for (imports.items) |*import| {
                if (std.mem.eql(u8, import.name, name)) {
                    const new_len = import.paths.len + 1;
                    const new_paths = try alloc.alloc([]const u8, new_len);
                    for (0..(new_len - 1)) |i| {
                        new_paths[i] = import.paths[i];
                    }
                    new_paths[new_len - 1] = path;
                    import.paths = new_paths;
                    continue :outer;
                }
            }
            const paths = try alloc.alloc([]const u8, 1);
            paths[0] = path;
            try imports.append(Import { .name = name, .paths = paths });
        } else if (std.mem.eql(u8, cmd, "-R")) {
            try replaces.append(Replace {
                .prefix = it.next() orelse return error.NoPrefix,
                .name = it.next() orelse return error.NoName,
            });
        } else return error.InvalidCommand;
    }
    gen_args = GenArgs {
        .types_namespace = args[3],
        .imports = try imports.toOwnedSlice(),
        .replaces = try replaces.toOwnedSlice(),
    };
    try generate.generateProtocol(&protocol, &writer);
}

pub const GenArgs = struct {
    types_namespace: []const u8,
    imports: []Import,
    replaces: []Replace,
};

pub const Import = struct {
    name: []const u8,
    paths: [][]const u8,
};

pub const Replace = struct {
    prefix: []const u8,
    name: []const u8,
};
