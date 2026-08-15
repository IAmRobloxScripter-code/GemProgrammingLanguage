const std = @import("std");
const gvm = @import("gvm.zig");
const constants = @import("../constants.zig");

pub const Object = union(enum) {
    gem_null: u0,
    uint8: Int(u8),
    uint16: Int(u16),
    uint32: Int(u32),
    uint64: Int(u64),

    float16: Float(f16),
    float32: Float(f32),
    float64: Float(f64),

    int8: Int(i8),
    int16: Int(i16),
    int32: Int(i32),
    int64: Int(i64),
    boolean: Boolean,

    string: String,
    array: Array,

    function: Function,
    method: Method,

    process: GVM_PROCESS,
    class: Class,

    args_container: ArgsContainer,
};

pub fn Int(comptime T: type) type {
    return struct {
        value: T = 0,

        constructor: ?Method = null,
        destructor: ?Method = null,

        add_method: ?Method = null,
        sub_method: ?Method = null,
        mul_method: ?Method = null,
        div_method: ?Method = null,
        mod_method: ?Method = null,
        pow_method: ?Method = null,

        not_method: ?Method = null,
        equal_method: ?Method = null,
        not_equal_method: ?Method = null,
        less_than_method: ?Method = null,
        greater_than_method: ?Method = null,
        less_than_equal_method: ?Method = null,
        greater_than_equal_method: ?Method = null,

        binary_left_shift_method: ?Method = null,
        binary_right_shift_method: ?Method = null,
        binary_and_method: ?Method = null,
        binary_or_method: ?Method = null,
        binary_xor_method: ?Method = null,
        binary_not_method: ?Method = null,

        get_member_access_method: ?Method = null,
        set_member_method: ?Method = null,
        get_subscript_method: ?Method = null,
        set_subscript_method: ?Method = null,

        iterator: ?Method = null,
        stringify: ?Method = null,

        gc_marked: bool = false,
    };
}

pub fn Float(comptime T: type) type {
    return struct {
        value: T = 0,

        constructor: ?Method = null,
        destructor: ?Method = null,

        add_method: ?Method = null,
        sub_method: ?Method = null,
        mul_method: ?Method = null,
        div_method: ?Method = null,
        mod_method: ?Method = null,
        pow_method: ?Method = null,

        not_method: ?Method = null,
        equal_method: ?Method = null,
        not_equal_method: ?Method = null,
        less_than_method: ?Method = null,
        greater_than_method: ?Method = null,
        less_than_equal_method: ?Method = null,
        greater_than_equal_method: ?Method = null,

        binary_left_shift_method: ?Method = null,
        binary_right_shift_method: ?Method = null,
        binary_and_method: ?Method = null,
        binary_or_method: ?Method = null,
        binary_xor_method: ?Method = null,
        binary_not_method: ?Method = null,

        get_member_access_method: ?Method = null,
        set_member_method: ?Method = null,
        get_subscript_method: ?Method = null,
        set_subscript_method: ?Method = null,

        iterator: ?Method = null,
        stringify: ?Method = null,

        gc_marked: bool = false,
    };
}

pub const Boolean = struct {
    value: bool = false,

    constructor: ?Method = null,
    destructor: ?Method = null,

    add_method: ?Method = null,
    sub_method: ?Method = null,
    mul_method: ?Method = null,
    div_method: ?Method = null,
    mod_method: ?Method = null,
    pow_method: ?Method = null,

    not_method: ?Method = null,
    equal_method: ?Method = null,
    not_equal_method: ?Method = null,
    less_than_method: ?Method = null,
    greater_than_method: ?Method = null,
    less_than_equal_method: ?Method = null,
    greater_than_equal_method: ?Method = null,

    binary_left_shift_method: ?Method = null,
    binary_right_shift_method: ?Method = null,
    binary_and_method: ?Method = null,
    binary_or_method: ?Method = null,
    binary_xor_method: ?Method = null,
    binary_not_method: ?Method = null,

    get_member_access_method: ?Method = null,
    set_member_method: ?Method = null,
    get_subscript_method: ?Method = null,
    set_subscript_method: ?Method = null,

    iterator: ?Method = null,
    stringify: ?Method = null,

    gc_marked: bool = false,
};

pub const String = struct {
    value: std.ArrayList(u8) = .empty,

    constructor: ?Method = null,
    destructor: ?Method = null,

    add_method: ?Method = null,
    sub_method: ?Method = null,
    mul_method: ?Method = null,
    div_method: ?Method = null,
    mod_method: ?Method = null,
    pow_method: ?Method = null,

    not_method: ?Method = null,
    equal_method: ?Method = null,
    not_equal_method: ?Method = null,
    less_than_method: ?Method = null,
    greater_than_method: ?Method = null,
    less_than_equal_method: ?Method = null,
    greater_than_equal_method: ?Method = null,

    binary_left_shift_method: ?Method = null,
    binary_right_shift_method: ?Method = null,
    binary_and_method: ?Method = null,
    binary_or_method: ?Method = null,
    binary_xor_method: ?Method = null,
    binary_not_method: ?Method = null,

    get_member_access_method: ?Method = null,
    set_member_method: ?Method = null,
    get_subscript_method: ?Method = null,
    set_subscript_method: ?Method = null,

    iterator: ?Method = null,
    stringify: ?Method = null,

    gc_marked: bool = false,
};

pub const Array = struct {
    size: u64,
    value: std.ArrayList(Object) = .empty,

    constructor: ?Method = null,
    destructor: ?Method = null,

    add_method: ?Method = null,
    sub_method: ?Method = null,
    mul_method: ?Method = null,
    div_method: ?Method = null,
    mod_method: ?Method = null,
    pow_method: ?Method = null,

    not_method: ?Method = null,
    equal_method: ?Method = null,
    not_equal_method: ?Method = null,
    less_than_method: ?Method = null,
    greater_than_method: ?Method = null,
    less_than_equal_method: ?Method = null,
    greater_than_equal_method: ?Method = null,

    binary_left_shift_method: ?Method = null,
    binary_right_shift_method: ?Method = null,
    binary_and_method: ?Method = null,
    binary_or_method: ?Method = null,
    binary_xor_method: ?Method = null,
    binary_not_method: ?Method = null,

    get_member_access_method: ?Method = null,
    set_member_method: ?Method = null,
    get_subscript_method: ?Method = null,
    set_subscript_method: ?Method = null,

    iterator: ?Method = null,
    stringify: ?Method = null,

    gc_marked: bool = false,
};

pub const Function = struct {
    address: u64,
    argc: u64,

    constructor: ?Method = null,
    destructor: ?Method = null,

    iterator: ?Method = null,
    stringify: ?Method = null,

    gc_marked: bool = false,
};

pub const ArgsContainer = struct {
    value: std.ArrayList(*Object) = .empty,

    constructor: ?Method = null,
    destructor: ?Method = null,

    iterator: ?Method = null,
    stringify: ?Method = null,
    gc_marked: bool = false,
};

pub const Method = union(enum) {
    zig: *const fn (*Object) anyerror!*Object,
    gem: Function,
};

pub const ClassMetadata = struct {
    name: []const u8,
    fields: std.StringHashMap(Object),
    methods: std.StringHashMap(*Object),
};

pub const Class = struct {
    fields: std.StringHashMap(*Object),
    methods: std.StringHashMap(*Object),

    constructor: ?Method = null,
    destructor: ?Method = null,

    add_method: ?Method = null,
    sub_method: ?Method = null,
    mul_method: ?Method = null,
    div_method: ?Method = null,
    mod_method: ?Method = null,
    pow_method: ?Method = null,

    not_method: ?Method = null,
    equal_method: ?Method = null,
    not_equal_method: ?Method = null,
    less_than_method: ?Method = null,
    greater_than_method: ?Method = null,
    less_than_equal_method: ?Method = null,
    greater_than_equal_method: ?Method = null,

    binary_left_shift_method: ?Method = null,
    binary_right_shift_method: ?Method = null,
    binary_and_method: ?Method = null,
    binary_or_method: ?Method = null,
    binary_xor_method: ?Method = null,
    binary_not_method: ?Method = null,

    get_member_access_method: ?Method = null,
    set_member_method: ?Method = null,
    get_subscript_method: ?Method = null,
    set_subscript_method: ?Method = null,

    iterator: ?Method = null,
    stringify: ?Method = null,

    gc_marked: bool = false,
};

pub const GVM_PROCESS = struct {
    constructor: ?Method = null,
    destructor: ?Method = null,

    instruction_pointer: u64,
    function: *Object,

    paused: bool,
    dead: bool,

    register: gvm.RegisterFile,
    stack: std.ArrayList(*Object),
    scope_stack: std.ArrayList(*gvm.Scope),

    iterator: ?Method = null,
    stringify: ?Method = null,

    gc_marked: bool = false,
};
