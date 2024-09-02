pub const Version = u8;

pub const Protocol = struct {
    name: []const u8,
    copyright: ?[]const u8,
    description: ?Description,
    interfaces: []Interface,
};

pub const Interface = struct {
    name: []const u8,
    version: Version,
    description: ?Description,
    requests: []Method,
    events: []Method,
    enums: []Enum,
};

pub const Method = struct {
    name: []const u8,
    is_destructor: bool,
    since: ?Version,
    dep_since: ?Version,
    description: ?Description,
    args: []Arg,
};

pub const Arg = struct {
    name: []const u8,
    type: Type,
    summary: ?[]const u8,
    description: ?Description,

    pub const Type = union(enum) {
        int: void,
        uint: void,
        fixed: void,
        array: void,
        fd: void,
        string: StringMeta,
        object: ObjectMeta,
        new_id: NewIdMeta,
        enum_: EnumMeta,

        const StringMeta = struct {
            allow_null: bool,
        };

        const ObjectMeta = struct {
            interface: ?[]const u8,
            allow_null: bool,
        };

        const NewIdMeta = struct {
            interface: ?[]const u8,
        };

        const EnumMeta = struct {
            enum_name: []const u8,
            is_signed: bool,
        };
    };
};

pub const Enum = struct {
    name: []const u8,
    since: ?Version,
    is_bit_field: bool,
    description: ?Description,
    entries: []Entry,
};

pub const Entry = struct {
    name: []const u8,
    value: u32,
    summary: ?[]const u8,
    since: ?Version,
    dep_since: ?Version,
    description: ?Description,
};

pub const Description = struct {
    summary: []const u8,
    body: ?[]const u8,
};
