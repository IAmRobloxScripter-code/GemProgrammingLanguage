const std = @import("std");
const args = @import("args.zig");
const constants = @import("constants.zig");

// mmm layla goog
pub fn main(init: std.process.Init) !void {
    const args_state = try args.Args.init(try init.minimal.args.toSlice(constants.ALLOCATOR));
    try args_state.setDefaultArgValue("-m", "64MB");
    try args_state.setDefaultArgValue("-gvm", "main.gvm");
    try args_state.setDefaultArgValue("-gci", "128");

    if (!args_state.isArg("-gvm")) {
        try args_state.setDefaultArgValue("-o", "main.gvm");
    }
}
