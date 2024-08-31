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
const clean = @import("clean.zig");
const generate = @import("generate.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    if (args.len < 3) { return error.TooFewArgs; }
    else if (args.len > 3) { return error.TooManyArgs; }

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

    try clean.cleanProtocol(&protocol, "wl_", alloc);
    
    const out_path = args[2];
    var out_file = try std.fs.cwd().createFile(out_path, .{});
    defer out_file.close();
    const writer = out_file.writer();

    // TODO generate code
    try generate.generateProtocol(&protocol, &writer);
}

