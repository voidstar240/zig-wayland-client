////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//   This is the main file for the zwayland scanner. The main file for the    //
//   zwayland library is src/root.zig. All files in the src/scanner/          //
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

    var imports = try std.ArrayList(Import).initCapacity(alloc, args[5..].len);
    for (args[5..]) |arg| {
        var it = std.mem.tokenize(u8, arg, &.{' '});
        const import = Import {
            .path = it.next() orelse return error.NoImportTokens,
            .name = it.next() orelse return error.NoImportName,
            .prefix = it.next(),
        };
        try imports.append(import);
    }
    gen_args = GenArgs {
        .types_namespace = args[3],
        .this_prefix = args[4],
        .imports = try imports.toOwnedSlice(),
    };
    try generate.generateProtocol(&protocol, &writer);
}

pub const GenArgs = struct {
    types_namespace: []const u8,
    this_prefix: []const u8,
    imports: []Import,
};

pub const Import = struct {
    path: []const u8,
    name: []const u8,
    prefix: ?[]const u8,
};
