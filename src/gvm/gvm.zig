const std = @import("std");
const args = @import("../args.zig");
const constants = @import("../constants.zig");
const objects = @import("object.zig");
const bytecode = @import("../bytecode.zig");

const ALLOCATOR = constants.ALLOCATOR;

pub const ScopeType = enum {
    branch,
    loop,
};

pub const FunctionScope = struct {
    return_address: u64,
    variables: std.AutoHashMap(u32, *objects.Object),
};

pub const BlockScope = struct {
    scope_type: ScopeType,
    variables: std.AutoHashMap(u32, *objects.Object),
};

pub const Scope = union(enum) {
    function_scope: FunctionScope,
    block_scope: BlockScope,
};

pub const Registers = enum(u8) {
    REG1,
    REG2,
    REG3,
    REG4,
    REG5,
    REG6,
    REG7,
    REG8,

    PRIV_REG1,
    PRIV_REG2,
    PRIV_REG3,
    PRIV_REG4,

    RET_REG,

    _count,
};

pub const RegisterFile = struct {
    registers: [
        @intFromEnum(
            Registers._count,
        )
    ]?*objects.Object = [_]?*objects.Object{null} ** @intFromEnum(
        Registers._count,
    ),

    pub inline fn get(self: *RegisterFile, register: Registers) ?*objects.Object {
        return self.registers[@intFromEnum(register)];
    }

    pub inline fn set(self: *RegisterFile, register: Registers, object: ?*objects.Object) void {
        self.registers[@intFromEnum(register)] = object;
    }
};

pub const GVM = struct {
    args_state: args.Args,
    max_memory: u64,
    gc_interval: u32,
    gc_interval_count: u32,
    objects: std.ArrayList(*objects.Object),
    constants: std.AutoHashMap(u32, objects.Object),
    galena_null: *objects.Object,
    zero: *objects.Object,

    processes: std.ArrayList(objects.GVM_PROCESS),
    class_metadatas: std.StringHashMap(u32, objects.ClassMetadata),

    bytes: []u8,
    instruction_pointer_start: u64,

    major_version: u16 = 0,
    minor_version: u16 = 0,

    global_registers: RegisterFile,

    pub fn countMemoryUsage(self: *GVM) u64 {
        var usage: u64 = 0;

        for (self.objects.items) |object| {
            usage += switch (object.*) {
                inline else => |value| @sizeOf(@TypeOf(value)),
            };
        }

        return usage;
    }

    pub fn isDigit(char: u8) bool {
        return char >= '0' and char <= '9';
    }

    pub fn parseMemoryArg(args_state: args.Args) !u64 {
        const string_value = args_state.getArgValue("-m");

        const number: std.ArrayList(u8) = .empty;

        var index: i32 = 0;
        while (string_value.len > index and isDigit(string_value.ptr[index])) {
            try number.append(ALLOCATOR, string_value[index]);
            index += 1;
        }

        const suffix: std.ArrayList(u8) = .empty;

        while (string_value.len > index) {
            try suffix.append(ALLOCATOR, string_value[index]);
            index += 1;
        }

        const memory = try std.fmt.parseInt(u64, number.items, 10);
        var memory_in_bytes: u64 = 0;

        if (std.mem.eql(u8, suffix.items, "B")) {
            memory_in_bytes = memory;
        } else if (std.mem.eql(u8, suffix.items, "KB")) {
            memory_in_bytes = @as(u64, memory) * 1024;
        } else if (std.mem.eql(u8, suffix.items, "MB")) {
            memory_in_bytes = @as(u64, memory) * 1024 * 1024;
        } else if (std.mem.eql(u8, suffix.items, "GB")) {
            memory_in_bytes = @as(u64, memory) * 1024 * 1024 * 1024;
        } else {
            return error.InvalidArgumentValue;
        }

        return memory_in_bytes;
    }

    pub fn init(args_state: args.Args) !GVM {
        const galena_null = try ALLOCATOR.create(objects.Object);
        galena_null.* = .{ .galena_null = 0 };
        const zero = try ALLOCATOR.create(objects.Object);
        zero.* = .{ .uint8 = 0 };

        return .{
            .args_state = args_state,
            .max_memory = try parseMemoryArg(args_state),
            .gc_interval = try std.fmt.parseInt(u32, args_state.getArgValue("-gci"), 10),
            .gc_interval_count = 0,
            .instruction_pointer_start = 0,
            .objects = .empty,
            .constants = .init(ALLOCATOR),
            .class_metadatas = .init(ALLOCATOR),
            .processes = .empty,
            .galena_null = galena_null,
            .zero = zero,
        };
    }

    pub fn createProcess(_: *GVM, function: *objects.Object) !*objects.Object {
        const process = try ALLOCATOR.create(objects.Object);
        process.* = .{
            .process = .{
                .instruction_pointer = function.function.address,
                .function = function,
                .stack = .empty,
                .scope_stack = .empty,
                .return_stack = .empty,
                .register = objects.RegisterFile{},
                .paused = false,
                .dead = false,
                .flags = .{
                    .zero = false,
                    .negative = false,
                },
            },
        };

        return process;
    }

    pub fn mark(self: *GVM, list: std.ArrayList(*objects.Object)) anyerror!void {
        for (list.items) |item| {
            switch (item.*) {
                .array => {
                    item.array.gc_marked = true;
                    try self.mark(item.array.value);
                },
                .class => {
                    var fields: std.ArrayList(*objects.Object) = .empty;
                    var iterator = item.class.fields.valueIterator();

                    while (iterator.next()) |field| {
                        try fields.append(ALLOCATOR, field);
                    }

                    item.class.gc_marked = true;
                    try self.mark(fields);
                    fields.deinit(ALLOCATOR);
                },
                .args_container => {
                    item.args_container.gc_marked = true;
                    try self.mark(item.args_container.value);
                },
                inline else => |*value| value.gc_marked = true,
            }
        }
    }

    pub fn collectGarbage(self: *GVM) !void {
        for (self.processes.items) |process| {
            try self.mark(process.stack);
        }
    }

    pub fn read_header(self: *GVM) !void {
        if (!(self.bytes[0] == 'G' and self.bytes[1] == 'V' and self.bytes[2] == 'M')) {
            return error.InvalidMagicNumber;
        }
        self.instruction_pointer_start = 3;

        const minor_version = self.readu32(self.instruction_pointer_start);
        self.instruction_pointer_start += 4;
        const major_version = self.readu32(self.instruction_pointer_start);
        self.instruction_pointer_start += 4;

        if (major_version < self.major_version or
            (major_version == self.major_version and
                minor_version < self.minor_version))
        {
            return error.OldVersion;
        }

        const constant_count = self.readu32(self.instruction_pointer_start);
        self.instruction_pointer_start += 4;

        for (0..constant_count) |constant_index| {
            const instruction_type: bytecode.BytecodeType = @enumFromInt(
                self.bytes[self.instruction_pointer_start],
            );
            self.instruction_pointer_start += 1;

            switch (instruction_type) {
                .uint8 => {
                    try self.constants.put(constant_index, objects.Object{
                        .uint8 = .{ .value = self.readu8(self.instruction_pointer_start) },
                    });
                    self.instruction_pointer_start += 1;
                },

                .uint16 => {
                    try self.constants.put(constant_index, objects.Object{
                        .uint16 = .{ .value = self.readu16(self.instruction_pointer_start) },
                    });
                    self.instruction_pointer_start += 2;
                },

                .uint32 => {
                    try self.constants.put(constant_index, objects.Object{
                        .uint32 = .{ .value = self.readu32(self.instruction_pointer_start) },
                    });
                    self.instruction_pointer_start += 4;
                },

                .uint64 => {
                    try self.constants.put(constant_index, objects.Object{
                        .uint64 = .{ .value = self.readu64(self.instruction_pointer_start) },
                    });
                    self.instruction_pointer_start += 8;
                },

                .int8 => {
                    try self.constants.put(constant_index, objects.Object{
                        .int8 = .{ .value = self.readi8(self.instruction_pointer_start) },
                    });
                    self.instruction_pointer_start += 1;
                },

                .int16 => {
                    try self.constants.put(constant_index, objects.Object{
                        .int16 = .{ .value = self.readi16(self.instruction_pointer_start) },
                    });
                    self.instruction_pointer_start += 2;
                },

                .int32 => {
                    try self.constants.put(constant_index, objects.Object{
                        .int32 = .{ .value = self.readi32(self.instruction_pointer_start) },
                    });
                    self.instruction_pointer_start += 4;
                },

                .int64 => {
                    try self.constants.put(constant_index, objects.Object{
                        .int64 = .{ .value = self.readi64(self.instruction_pointer_start) },
                    });
                    self.instruction_pointer_start += 8;
                },

                .float16 => {
                    try self.constants.put(constant_index, objects.Object{
                        .float16 = .{ .value = self.readf16(self.instruction_pointer_start) },
                    });
                    self.instruction_pointer_start += 8;
                },

                .float32 => {
                    try self.constants.put(constant_index, objects.Object{
                        .float32 = .{ .value = self.readf32(self.instruction_pointer_start) },
                    });
                    self.instruction_pointer_start += 8;
                },

                .float64 => {
                    try self.constants.put(constant_index, objects.Object{
                        .float64 = .{ .value = self.readf64(self.instruction_pointer_start) },
                    });
                    self.instruction_pointer_start += 8;
                },

                .string => {
                    const length = self.readu64(self.instruction_pointer_start);
                    self.instruction_pointer_start += 8;

                    var string: std.ArrayList(u8) = .empty;

                    for (0..length) |_| {
                        try string.append(ALLOCATOR, self.bytes[self.instruction_pointer_start]);
                        self.instruction_pointer_start += 1;
                    }

                    try self.constants.put(constant_index, objects.Object{
                        .string = .{ .value = string },
                    });
                },
            }
        }

        const class_count = self.readu64(self.instruction_pointer_start);
        self.instruction_pointer_start += 8;

        for (0..class_count) |_| {
            const class_metadata = try self.read_class_file();
            try self.class_metadatas.put(class_metadata.name, class_metadata);
        }
    }

    pub fn read_class_file(self: *GVM) !objects.ClassMetadata {
        // class metadata be like
        // name
        // super
        // [interfaces - maybe later]
        // field_count
        // fields
        // method_count
        // methods

        const name_length = self.readu64(self.instruction_pointer_start);
        self.instruction_pointer_start += 8;

        var name: std.ArrayList(u8) = .empty;
        for (0..name_length) |_| {
            try name.append(ALLOCATOR, self.readu8(self.instruction_pointer_start));
            self.instruction_pointer_start += 1;
        }

        const super_length = self.readu64(self.instruction_pointer_start);
        self.instruction_pointer_start += 8;

        var super: std.ArrayList(u8) = .empty;
        for (0..super_length) |_| {
            try super.append(ALLOCATOR, self.readu8(self.instruction_pointer_start));
            self.instruction_pointer_start += 1;
        }

        const field_count = self.readu64(self.instruction_pointer_start);
        self.instruction_pointer_start += 8;

        var fields: std.StringHashMap(objects.Object) = .init(ALLOCATOR);

        // field_name field_default_value_register
        for (0..field_count) |_| {
            const field_name_length = self.readu64(self.instruction_pointer_start);
            self.instruction_pointer_start += 8;

            var field_name: std.ArrayList(u8) = .empty;
            for (0..field_name_length) |_| {
                try field_name.append(
                    ALLOCATOR,
                    self.readu8(self.instruction_pointer_start),
                );
                self.instruction_pointer_start += 1;
            }

            const value_id = self.readu8(self.instruction_pointer_start);
            self.instruction_pointer_start += 1;
            try fields.put(
                field_name,
                self.global_registers.get(
                    @enumFromInt(value_id),
                ) orelse self.galena_null,
            );
        }

        const method_count = self.readu64(self.instruction_pointer_start);
        self.instruction_pointer_start += 8;

        var methods: std.StringHashMap(objects.Object) = .init(ALLOCATOR);

        // method_name method_argc method_bytecode_size
        for (0..method_count) |_| {
            const method_name_length = self.readu64(self.instruction_pointer_start);
            self.instruction_pointer_start += 8;

            var method_name: std.ArrayList(u8) = .empty;
            for (0..method_name_length) |_| {
                try method_name.append(
                    ALLOCATOR,
                    self.readu8(self.instruction_pointer_start),
                );
                self.instruction_pointer_start += 1;
            }

            const argc = self.readu64(self.instruction_pointer_start);
            self.instruction_pointer_start += 8;

            const bytecode_size = self.readu64(self.instruction_pointer_start);
            self.instruction_pointer_start += 8;

            const method_address = self.instruction_pointer_start;
            self.instruction_pointer_start += bytecode_size;

            const method: objects.Object = .{ .method = .{ .galena = .{
                .argc = argc,
                .address = method_address,
            } } };

            try methods.put(method_name, method);
        }

        return .{
            .name = name,
            .super = super,
            .fields = fields,
            .methods = methods,
        };
    }

    pub fn execute(self: *GVM) !void {
        for (self.processes.items, 0..5) |process, _| {
            self.step(process);

            if (process.scope_stack.items.len <= 0 or process.instruction_pointer >= self.bytes.len) {
                process.dead = true;
                break;
            }
        }
    }

    pub inline fn readu8(self: *GVM, instruction_pointer: u64) u8 {
        return self.bytes[instruction_pointer];
    }

    pub inline fn readu16(self: *GVM, instruction_pointer: u64) u16 {
        return @as(u16, self.bytes[instruction_pointer]) |
            (@as(u16, self.bytes[instruction_pointer + 1]) << 8);
    }

    pub inline fn readu32(self: *GVM, instruction_pointer: u64) u32 {
        return @as(u32, self.bytes[instruction_pointer]) |
            (@as(u32, self.bytes[instruction_pointer + 1]) << 8) |
            (@as(u32, self.bytes[instruction_pointer + 2]) << 16) |
            (@as(u32, self.bytes[instruction_pointer + 3]) << 24);
    }

    pub inline fn readu64(self: *GVM, instruction_pointer: u64) u64 {
        return @as(u64, self.bytes[instruction_pointer]) |
            (@as(u64, self.bytes[instruction_pointer + 1]) << 8) |
            (@as(u64, self.bytes[instruction_pointer + 2]) << 16) |
            (@as(u64, self.bytes[instruction_pointer + 3]) << 24) |
            (@as(u64, self.bytes[instruction_pointer + 4]) << 32) |
            (@as(u64, self.bytes[instruction_pointer + 5]) << 40) |
            (@as(u64, self.bytes[instruction_pointer + 6]) << 48) |
            (@as(u64, self.bytes[instruction_pointer + 7]) << 56);
    }

    pub inline fn readi8(self: *GVM, instruction_pointer: u64) i8 {
        return @bitCast(readu8(self, instruction_pointer));
    }

    pub inline fn readi16(self: *GVM, instruction_pointer: u64) i16 {
        return @bitCast(readu16(self, instruction_pointer));
    }

    pub inline fn readi32(self: *GVM, instruction_pointer: u64) i32 {
        return @bitCast(readu32(self, instruction_pointer));
    }

    pub inline fn readi64(self: *GVM, instruction_pointer: u64) i64 {
        return @bitCast(readu64(self, instruction_pointer));
    }

    pub inline fn readf16(self: *GVM, instruction_pointer: u64) f16 {
        return @bitCast(readu16(self, instruction_pointer));
    }

    pub inline fn readf32(self: *GVM, instruction_pointer: u64) f32 {
        return @bitCast(readu32(self, instruction_pointer));
    }

    pub inline fn readf64(self: *GVM, instruction_pointer: u64) f64 {
        return @bitCast(readu64(self, instruction_pointer));
    }

    pub inline fn getScope(_: *GVM, process: *objects.GVM_PROCESS) *Scope {
        return process.scope_stack.items[process.scope_stack.items.len - 1];
    }

    pub fn call(self: *GVM, process: *objects.GVM_PROCESS, source: Registers) !void {
        const function = process.register.get(source) orelse self.galena_null;

        switch (function.method.*) {
            .galena => {
                const return_address = process.instruction_pointer;
                process.instruction_pointer = function.method.galena.address;
                const function_args = process.stack.pop() orelse self.galena_null;
                var arg_index: u32 = 0;

                var stack_frame = try ALLOCATOR.create(Scope);
                stack_frame.* = .{
                    .function_scope = .{
                        .variables = .init(ALLOCATOR),
                        .return_address = return_address,
                    },
                };

                for (function_args.args_container.value.items) |arg| {
                    try stack_frame.function_scope.variables.put(arg_index, arg);
                    arg_index += 1;
                }

                try process.scope_stack.append(ALLOCATOR, stack_frame);
            },
            .zig => {
                const function_args = process.stack.pop() orelse self.galena_null;
                const result = try function.method.zig(function_args);

                process.register.set(.RET_REG, result);
            },
        }
    }

    pub fn createArgs(_: *GVM) !*objects.Object {
        const object = try ALLOCATOR.create(objects.Object);
        object.* = .{ .args_container = .{
            .value = .empty,
        } };

        return object;
    }

    pub fn callBinaryMethod(
        self: *GVM,
        process: *objects.GVM_PROCESS,
        comptime method_name: []const u8,
    ) !void {
        const destination_id = self.readu8(process.instruction_pointer);
        process.instruction_pointer += 1;

        const left_id = self.readu8(process.instruction_pointer);
        process.instruction_pointer += 1;

        const right_id = self.readu8(process.instruction_pointer);
        process.instruction_pointer += 1;

        const function_params = try self.createArgs();
        try function_params.args_container.value.append(
            ALLOCATOR,
            process.register.get(
                @enumFromInt(left_id),
            ) orelse self.galena_null,
        );

        try function_params.args_container.value.append(
            ALLOCATOR,
            process.register.get(
                @enumFromInt(right_id),
            ) orelse self.galena_null,
        );

        process.register.set(
            @enumFromInt(destination_id),
            switch (function_params.args_container.value.items[0].*) {
                inline else => |*value| @field(value, method_name),
            },
        );

        try self.call(process, destination_id);
        process.register.set(
            @enumFromInt(destination_id),
            process.register.get(.RET_REG) orelse self.galena_null,
        );
    }

    pub fn step(self: *GVM, process: *objects.GVM_PROCESS) !void {
        const instruction = self.bytes[process.instruction_pointer];

        switch (@as(bytecode.Instructions, @enumFromInt(instruction))) {
            .load_constant => {
                process.instruction_pointer += 1;
                const constant_id = self.readu32(process.instruction_pointer);
                process.instruction_pointer += 4;

                const destination_id = self.readu8(process.instruction_pointer);
                process.instruction_pointer += 1;

                const constant = self.constants.getPtr(constant_id) orelse return error.InvalidConstantId;
                process.register.set(@enumFromInt(destination_id), constant);
            },
            .mov => {
                process.instruction_pointer += 1;
                const destination_id = self.readu8(process.instruction_pointer);
                process.instruction_pointer += 1;

                const source_id = self.readu8(process.instruction_pointer);
                process.instruction_pointer += 1;

                process.register.set(
                    @enumFromInt(destination_id),
                    process.register.get(
                        @enumFromInt(source_id),
                    ) orelse null,
                );
            },
            .push => {
                process.instruction_pointer += 1;
                const source_id = self.readu8(process.instruction_pointer);
                process.instruction_pointer += 1;

                try process.stack.append(ALLOCATOR, process.register.get(
                    @enumFromInt(source_id),
                ) orelse self.galena_null);
            },
            .pop => {
                process.instruction_pointer += 1;
                const destination_id = self.readu8(process.instruction_pointer);
                process.instruction_pointer += 1;

                process.register.set(
                    @enumFromInt(destination_id),
                    process.stack.pop() orelse self.galena_null,
                );
            },
            .store_variable => {
                process.instruction_pointer += 1;
                var scope = self.getScope(process);

                const variable_id = self.readu32(process.instruction_pointer);
                process.instruction_pointer += 4;

                const source_id = self.readu8(process.instruction_pointer);
                process.instruction_pointer += 1;

                switch (scope.*) {
                    .block_scope => {
                        try scope.block_scope.variables.put(
                            variable_id,
                            process.register.get(
                                @enumFromInt(source_id),
                            ) orelse self.galena_null,
                        );
                    },
                    .function_scope => {
                        try scope.function_scope.variables.put(
                            variable_id,
                            process.register.get(
                                @enumFromInt(source_id),
                            ) orelse self.galena_null,
                        );
                    },
                }
            },
            .load_variable => {
                process.instruction_pointer += 1;

                const variable_id = self.readu32(process.instruction_pointer);
                process.instruction_pointer += 4;

                const destination_id = self.readu8(process.instruction_pointer);
                process.instruction_pointer += 1;

                const scope = self.getScope(process);

                switch (scope.*) {
                    .block_scope => {
                        process.register.set(
                            @enumFromInt(destination_id),
                            scope.block_scope.variables.get(
                                variable_id,
                            ) orelse self.galena_null,
                        );
                    },
                    .function_scope => {
                        process.register.set(
                            @enumFromInt(destination_id),
                            scope.function_scope.variables.get(
                                variable_id,
                            ) orelse self.galena_null,
                        );
                    },
                }
            },
            .jmp => {
                process.instruction_pointer += 1;

                const destination = self.readu64(process.instruction_pointer);
                process.instruction_pointer = destination;
            },
            .jmp_if_true => {
                process.instruction_pointer += 1;

                const status_id = self.readu8(process.instruction_pointer);
                process.instruction_pointer += 1;

                const destination = self.readu64(process.instruction_pointer);
                const status = process.register.get(@enumFromInt(status_id)) orelse self.zero;
                if (status.boolean.value == true) {
                    process.instruction_pointer = destination;
                } else {
                    process.instruction_pointer += 8;
                }
            },
            .jmp_if_false => {
                process.instruction_pointer += 1;

                const status_id = self.readu8(process.instruction_pointer);
                process.instruction_pointer += 1;

                const destination = self.readu64(process.instruction_pointer);
                const status = process.register.get(@enumFromInt(status_id)) orelse self.zero;
                if (status.boolean.value == false) {
                    process.instruction_pointer = destination;
                } else {
                    process.instruction_pointer += 8;
                }
            },
            .ret => {
                const stack_frame = process.scope_stack.pop() orelse return error.cannotReturnOutOfScope;
                process.instruction_pointer = stack_frame.function_scope.return_address;
                ALLOCATOR.destroy(stack_frame);
            },
            .add,
            .sub,
            .mul,
            .div,
            .mod,
            .pow,
            .get_member_access,
            .get_subscript,
            .binary_left_shift,
            .binary_right_shift,
            .binary_and,
            .binary_or,
            .binary_xor,
            .equal,
            .not_equal,
            .less_than,
            .greater_than,
            .less_than_equal,
            .greater_than_equal,
            => {
                process.instruction_pointer += 1;
                const name = @tagName(instruction);
                const method = std.fmt.comptimePrint("{}_method", .{name});

                try self.callBinaryMethod(process, method);
            },
            .binary_not => {
                process.instruction_pointer += 1;
                const destination_id = self.readu8(process.instruction_pointer);
                process.instruction_pointer += 1;

                const value_id = self.readu8(process.instruction_pointer);
                process.instruction_pointer += 1;

                const function_params = try self.createArgs();
                try function_params.args_container.value.append(
                    ALLOCATOR,
                    process.register.get(
                        @enumFromInt(value_id),
                    ) orelse self.galena_null,
                );

                process.register.set(
                    @enumFromInt(destination_id),
                    switch (function_params.args_container.value.items[0].*) {
                        inline else => |*value| value.binary_not_method,
                    },
                );

                try self.call(process, destination_id);
                process.register.set(
                    @enumFromInt(destination_id),
                    process.register.get(.RET_REG) orelse self.galena_null,
                );
            },
            .not => {
                process.instruction_pointer += 1;
                const destination_id = self.readu8(process.instruction_pointer);
                process.instruction_pointer += 1;

                const value_id = self.readu8(process.instruction_pointer);
                process.instruction_pointer += 1;

                const function_params = try self.createArgs();
                try function_params.args_container.value.append(
                    ALLOCATOR,
                    process.register.get(
                        @enumFromInt(value_id),
                    ) orelse self.galena_null,
                );

                process.register.set(
                    @enumFromInt(destination_id),
                    switch (function_params.args_container.value.items[0].*) {
                        inline else => |*value| value.not_method,
                    },
                );

                try self.call(process, destination_id);
                process.register.set(
                    @enumFromInt(destination_id),
                    process.register.get(.RET_REG) orelse self.galena_null,
                );
            },
            .call => {
                process.instruction_pointer += 1;
                const function_id = self.readu8(process.instruction_pointer);
                process.instruction_pointer += 1;

                try self.call(process, @enumFromInt(function_id));
            },
            .push_arg => {
                process.instruction_pointer += 1;
                const destination_id = self.readu8(process.instruction_pointer);
                process.instruction_pointer += 1;

                var args_container = process.register.get(@enumFromInt(destination_id)) orelse self.galena_null;
                try args_container.args_container.value.append(
                    ALLOCATOR,
                    process.stack.pop() orelse self.galena_null,
                );
            },
            .set_member => {
                process.instruction_pointer += 1;
                const object_id = self.readu8(process.instruction_pointer);
                process.instruction_pointer += 1;

                const member_id = self.readu8(process.instruction_pointer);
                process.instruction_pointer += 1;

                const value_id = self.readu8(process.instruction_pointer);
                process.instruction_pointer += 1;

                const function_params = try self.createArgs();
                try function_params.args_container.value.append(
                    ALLOCATOR,
                    process.register.get(
                        @enumFromInt(object_id),
                    ) orelse self.galena_null,
                );

                try function_params.args_container.value.append(
                    ALLOCATOR,
                    process.register.get(
                        @enumFromInt(member_id),
                    ) orelse self.galena_null,
                );

                try function_params.args_container.value.append(
                    ALLOCATOR,
                    process.register.get(
                        @enumFromInt(value_id),
                    ) orelse self.galena_null,
                );

                process.register.set(.PRIV_REG4, switch (function_params.args_container.value.items[0].*) {
                    inline else => |*value| value.set_member_method,
                });

                try self.call(process, .PRIV_REG4);
            },
            .set_subscript => {
                process.instruction_pointer += 1;
                const object_id = self.readu8(process.instruction_pointer);
                process.instruction_pointer += 1;

                const member_id = self.readu8(process.instruction_pointer);
                process.instruction_pointer += 1;

                const length = self.readu64(process.instruction_pointer);
                process.instruction_pointer += 8;

                var subscript: std.ArrayList(u8) = .empty;

                for (0..length) |_| {
                    try subscript.append(ALLOCATOR, self.bytes[process.instruction_pointer]);
                    process.instruction_pointer += 1;
                }

                const function_params = try self.createArgs();
                try function_params.args_container.value.append(
                    ALLOCATOR,
                    process.register.get(
                        @enumFromInt(object_id),
                    ) orelse self.galena_null,
                );

                try function_params.args_container.value.append(
                    ALLOCATOR,
                    process.register.get(
                        @enumFromInt(member_id),
                    ) orelse self.galena_null,
                );

                try function_params.args_container.value.append(
                    ALLOCATOR,
                    subscript,
                );

                process.register.set(.PRIV_REG4, switch (function_params.args_container.value.items[0].*) {
                    inline else => |*value| value.set_subscript_method,
                });

                try self.call(process, .PRIV_REG4);
            },
        }
    }
};
