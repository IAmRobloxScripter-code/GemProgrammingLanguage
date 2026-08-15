const std = @import("std");
const constants = @import("constants.zig");

const ALLOCATOR = constants.ALLOCATOR;

pub const Args = struct {
    argc: i32,
    argv: std.ArrayList([]const u8),
    default_values: std.StringHashMap([]const u8),

    pub fn init(args: []const []const u8) !Args {
        var array: std.ArrayList([]const u8) = .empty;

        for (args) |arg| {
            try array.append(ALLOCATOR, arg);
        }

        return .{
            .argc = args.len,
            .argv = array,
            .default_values = .init(ALLOCATOR),
        };
    }

    pub fn isArg(self: *Args, arg: []const u8) bool {
        for (self.argv.items) |item| {
            if (std.mem.eql(u8, arg, item)) {
                return true;
            }
        }

        return false;
    }

    pub fn setDefaultArgValue(self: *Args, arg: []const u8, value: []const u8) !void {
        try self.default_values.put(arg, value);
    }

    pub fn getArgValue(self: *Args, arg: []const u8) []const u8 {
        if (!self.isArg(arg)) return self.default_values.get(arg);

        for (0..self.argc - 1) |index| {
            const item = self.argv.items[index];
            if (std.mem.eql(u8, arg, item)) {
                if (index + 1 >= self.argc) {
                    return self.default_values.get(arg) orelse "";
                }

                return self.argv.items[index + 1];
            }
        }
    }
};
