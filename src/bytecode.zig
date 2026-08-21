pub const Instructions = enum {
    load_constant,

    mov,

    push,
    pop,

    not,
    add,
    sub,
    mul,
    div,
    mod,
    pow,
    get_member_access,
    get_subscript,

    set_member,
    set_subscript,

    binary_left_shift,
    binary_right_shift,
    binary_and,
    binary_or,
    binary_xor,
    binary_not,

    equal,
    not_equal,
    less_than,
    greater_than,
    less_than_equal,
    greater_than_equal,

    jmp,
    jmp_if_true,
    jmp_if_false,

    store_variable,
    load_variable,

    // begin_class_metadata,
    // create_class_field,

    // register_class_method,
    // register_class_metadata,

    create_class,
    destroy_class,

    push_arg,
    call,

    ret,
};

pub const BytecodeType = enum {
    uint8,
    u1nt16,
    uint32,
    uint64,
    int8,
    int16,
    int32,
    int64,
    float16,
    float32,
    float64,
    string,
};
