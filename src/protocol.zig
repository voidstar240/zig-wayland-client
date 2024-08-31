const std = @import("util.zig");

pub const Display = struct {
    pub const opcode = struct {
        pub const request = struct {
            pub const sync: u16 = 0;
            pub const getRegistry: u16 = 1;
        };
        pub const event = struct {
            pub const @"error": u16 = 0;
            pub const deleteId: u16 = 1;
        };
    };

    pub const Error = enum(u32) {
        invalid_object = 0, // server couldn't find object
        invalid_method = 1, // method doesn't exist on the specified interface or malformed request
        no_memory = 2, // server is out of memory
        implementation = 3, // implementation error in compositor
    };

    pub fn sync() void {}

    pub fn getRegistry() void {}

};

pub const Registry = struct {
    pub const opcode = struct {
        pub const request = struct {
            pub const bind: u16 = 0;
        };
        pub const event = struct {
            pub const global: u16 = 0;
            pub const globalRemove: u16 = 1;
        };
    };

    pub fn bind() void {}

};

pub const Callback = struct {
    pub const opcode = struct {
        pub const request = struct {
        };
        pub const event = struct {
            pub const done: u16 = 0;
        };
    };

};

pub const Compositor = struct {
    pub const opcode = struct {
        pub const request = struct {
            pub const createSurface: u16 = 0;
            pub const createRegion: u16 = 1;
        };
        pub const event = struct {
        };
    };

    pub fn createSurface() void {}

    pub fn createRegion() void {}

};

pub const ShmPool = struct {
    pub const opcode = struct {
        pub const request = struct {
            pub const createBuffer: u16 = 0;
            pub const destroy: u16 = 1;
            pub const resize: u16 = 2;
        };
        pub const event = struct {
        };
    };

    pub fn createBuffer() void {}

    pub fn destroy() void {}

    pub fn resize() void {}

};

pub const Shm = struct {
    pub const opcode = struct {
        pub const request = struct {
            pub const createPool: u16 = 0;
            pub const release: u16 = 1;
        };
        pub const event = struct {
            pub const format: u16 = 0;
        };
    };

    pub const Error = enum(u32) {
        invalid_format = 0, // buffer format is not known
        invalid_stride = 1, // invalid size or stride during pool or buffer creation
        invalid_fd = 2, // mmapping the file descriptor failed
    };

    pub const Format = enum(u32) {
        argb8888 = 0, // 32-bit ARGB format, [31:0] A:R:G:B 8:8:8:8 little endian
        xrgb8888 = 1, // 32-bit RGB format, [31:0] x:R:G:B 8:8:8:8 little endian
        c8 = 538982467, // 8-bit color index format, [7:0] C
        rgb332 = 943867730, // 8-bit RGB format, [7:0] R:G:B 3:3:2
        bgr233 = 944916290, // 8-bit BGR format, [7:0] B:G:R 2:3:3
        xrgb4444 = 842093144, // 16-bit xRGB format, [15:0] x:R:G:B 4:4:4:4 little endian
        xbgr4444 = 842089048, // 16-bit xBGR format, [15:0] x:B:G:R 4:4:4:4 little endian
        rgbx4444 = 842094674, // 16-bit RGBx format, [15:0] R:G:B:x 4:4:4:4 little endian
        bgrx4444 = 842094658, // 16-bit BGRx format, [15:0] B:G:R:x 4:4:4:4 little endian
        argb4444 = 842093121, // 16-bit ARGB format, [15:0] A:R:G:B 4:4:4:4 little endian
        abgr4444 = 842089025, // 16-bit ABGR format, [15:0] A:B:G:R 4:4:4:4 little endian
        rgba4444 = 842088786, // 16-bit RBGA format, [15:0] R:G:B:A 4:4:4:4 little endian
        bgra4444 = 842088770, // 16-bit BGRA format, [15:0] B:G:R:A 4:4:4:4 little endian
        xrgb1555 = 892424792, // 16-bit xRGB format, [15:0] x:R:G:B 1:5:5:5 little endian
        xbgr1555 = 892420696, // 16-bit xBGR 1555 format, [15:0] x:B:G:R 1:5:5:5 little endian
        rgbx5551 = 892426322, // 16-bit RGBx 5551 format, [15:0] R:G:B:x 5:5:5:1 little endian
        bgrx5551 = 892426306, // 16-bit BGRx 5551 format, [15:0] B:G:R:x 5:5:5:1 little endian
        argb1555 = 892424769, // 16-bit ARGB 1555 format, [15:0] A:R:G:B 1:5:5:5 little endian
        abgr1555 = 892420673, // 16-bit ABGR 1555 format, [15:0] A:B:G:R 1:5:5:5 little endian
        rgba5551 = 892420434, // 16-bit RGBA 5551 format, [15:0] R:G:B:A 5:5:5:1 little endian
        bgra5551 = 892420418, // 16-bit BGRA 5551 format, [15:0] B:G:R:A 5:5:5:1 little endian
        rgb565 = 909199186, // 16-bit RGB 565 format, [15:0] R:G:B 5:6:5 little endian
        bgr565 = 909199170, // 16-bit BGR 565 format, [15:0] B:G:R 5:6:5 little endian
        rgb888 = 875710290, // 24-bit RGB format, [23:0] R:G:B little endian
        bgr888 = 875710274, // 24-bit BGR format, [23:0] B:G:R little endian
        xbgr8888 = 875709016, // 32-bit xBGR format, [31:0] x:B:G:R 8:8:8:8 little endian
        rgbx8888 = 875714642, // 32-bit RGBx format, [31:0] R:G:B:x 8:8:8:8 little endian
        bgrx8888 = 875714626, // 32-bit BGRx format, [31:0] B:G:R:x 8:8:8:8 little endian
        abgr8888 = 875708993, // 32-bit ABGR format, [31:0] A:B:G:R 8:8:8:8 little endian
        rgba8888 = 875708754, // 32-bit RGBA format, [31:0] R:G:B:A 8:8:8:8 little endian
        bgra8888 = 875708738, // 32-bit BGRA format, [31:0] B:G:R:A 8:8:8:8 little endian
        xrgb2101010 = 808669784, // 32-bit xRGB format, [31:0] x:R:G:B 2:10:10:10 little endian
        xbgr2101010 = 808665688, // 32-bit xBGR format, [31:0] x:B:G:R 2:10:10:10 little endian
        rgbx1010102 = 808671314, // 32-bit RGBx format, [31:0] R:G:B:x 10:10:10:2 little endian
        bgrx1010102 = 808671298, // 32-bit BGRx format, [31:0] B:G:R:x 10:10:10:2 little endian
        argb2101010 = 808669761, // 32-bit ARGB format, [31:0] A:R:G:B 2:10:10:10 little endian
        abgr2101010 = 808665665, // 32-bit ABGR format, [31:0] A:B:G:R 2:10:10:10 little endian
        rgba1010102 = 808665426, // 32-bit RGBA format, [31:0] R:G:B:A 10:10:10:2 little endian
        bgra1010102 = 808665410, // 32-bit BGRA format, [31:0] B:G:R:A 10:10:10:2 little endian
        yuyv = 1448695129, // packed YCbCr format, [31:0] Cr0:Y1:Cb0:Y0 8:8:8:8 little endian
        yvyu = 1431918169, // packed YCbCr format, [31:0] Cb0:Y1:Cr0:Y0 8:8:8:8 little endian
        uyvy = 1498831189, // packed YCbCr format, [31:0] Y1:Cr0:Y0:Cb0 8:8:8:8 little endian
        vyuy = 1498765654, // packed YCbCr format, [31:0] Y1:Cb0:Y0:Cr0 8:8:8:8 little endian
        ayuv = 1448433985, // packed AYCbCr format, [31:0] A:Y:Cb:Cr 8:8:8:8 little endian
        nv12 = 842094158, // 2 plane YCbCr Cr:Cb format, 2x2 subsampled Cr:Cb plane
        nv21 = 825382478, // 2 plane YCbCr Cb:Cr format, 2x2 subsampled Cb:Cr plane
        nv16 = 909203022, // 2 plane YCbCr Cr:Cb format, 2x1 subsampled Cr:Cb plane
        nv61 = 825644622, // 2 plane YCbCr Cb:Cr format, 2x1 subsampled Cb:Cr plane
        yuv410 = 961959257, // 3 plane YCbCr format, 4x4 subsampled Cb (1) and Cr (2) planes
        yvu410 = 961893977, // 3 plane YCbCr format, 4x4 subsampled Cr (1) and Cb (2) planes
        yuv411 = 825316697, // 3 plane YCbCr format, 4x1 subsampled Cb (1) and Cr (2) planes
        yvu411 = 825316953, // 3 plane YCbCr format, 4x1 subsampled Cr (1) and Cb (2) planes
        yuv420 = 842093913, // 3 plane YCbCr format, 2x2 subsampled Cb (1) and Cr (2) planes
        yvu420 = 842094169, // 3 plane YCbCr format, 2x2 subsampled Cr (1) and Cb (2) planes
        yuv422 = 909202777, // 3 plane YCbCr format, 2x1 subsampled Cb (1) and Cr (2) planes
        yvu422 = 909203033, // 3 plane YCbCr format, 2x1 subsampled Cr (1) and Cb (2) planes
        yuv444 = 875713881, // 3 plane YCbCr format, non-subsampled Cb (1) and Cr (2) planes
        yvu444 = 875714137, // 3 plane YCbCr format, non-subsampled Cr (1) and Cb (2) planes
        r8 = 538982482, // [7:0] R
        r16 = 540422482, // [15:0] R little endian
        rg88 = 943212370, // [15:0] R:G 8:8 little endian
        gr88 = 943215175, // [15:0] G:R 8:8 little endian
        rg1616 = 842221394, // [31:0] R:G 16:16 little endian
        gr1616 = 842224199, // [31:0] G:R 16:16 little endian
        xrgb16161616f = 1211388504, // [63:0] x:R:G:B 16:16:16:16 little endian
        xbgr16161616f = 1211384408, // [63:0] x:B:G:R 16:16:16:16 little endian
        argb16161616f = 1211388481, // [63:0] A:R:G:B 16:16:16:16 little endian
        abgr16161616f = 1211384385, // [63:0] A:B:G:R 16:16:16:16 little endian
        xyuv8888 = 1448434008, // [31:0] X:Y:Cb:Cr 8:8:8:8 little endian
        vuy888 = 875713878, // [23:0] Cr:Cb:Y 8:8:8 little endian
        vuy101010 = 808670550, // Y followed by U then V, 10:10:10. Non-linear modifier only
        y210 = 808530521, // [63:0] Cr0:0:Y1:0:Cb0:0:Y0:0 10:6:10:6:10:6:10:6 little endian per 2 Y pixels
        y212 = 842084953, // [63:0] Cr0:0:Y1:0:Cb0:0:Y0:0 12:4:12:4:12:4:12:4 little endian per 2 Y pixels
        y216 = 909193817, // [63:0] Cr0:Y1:Cb0:Y0 16:16:16:16 little endian per 2 Y pixels
        y410 = 808531033, // [31:0] A:Cr:Y:Cb 2:10:10:10 little endian
        y412 = 842085465, // [63:0] A:0:Cr:0:Y:0:Cb:0 12:4:12:4:12:4:12:4 little endian
        y416 = 909194329, // [63:0] A:Cr:Y:Cb 16:16:16:16 little endian
        xvyu2101010 = 808670808, // [31:0] X:Cr:Y:Cb 2:10:10:10 little endian
        xvyu12_16161616 = 909334104, // [63:0] X:0:Cr:0:Y:0:Cb:0 12:4:12:4:12:4:12:4 little endian
        xvyu16161616 = 942954072, // [63:0] X:Cr:Y:Cb 16:16:16:16 little endian
        y0l0 = 810299481, // [63:0]   A3:A2:Y3:0:Cr0:0:Y2:0:A1:A0:Y1:0:Cb0:0:Y0:0  1:1:8:2:8:2:8:2:1:1:8:2:8:2:8:2 little endian
        x0l0 = 810299480, // [63:0]   X3:X2:Y3:0:Cr0:0:Y2:0:X1:X0:Y1:0:Cb0:0:Y0:0  1:1:8:2:8:2:8:2:1:1:8:2:8:2:8:2 little endian
        y0l2 = 843853913, // [63:0]   A3:A2:Y3:Cr0:Y2:A1:A0:Y1:Cb0:Y0  1:1:10:10:10:1:1:10:10:10 little endian
        x0l2 = 843853912, // [63:0]   X3:X2:Y3:Cr0:Y2:X1:X0:Y1:Cb0:Y0  1:1:10:10:10:1:1:10:10:10 little endian
        yuv420_8bit = 942691673,
        yuv420_10bit = 808539481,
        xrgb8888_a8 = 943805016,
        xbgr8888_a8 = 943800920,
        rgbx8888_a8 = 943806546,
        bgrx8888_a8 = 943806530,
        rgb888_a8 = 943798354,
        bgr888_a8 = 943798338,
        rgb565_a8 = 943797586,
        bgr565_a8 = 943797570,
        nv24 = 875714126, // non-subsampled Cr:Cb plane
        nv42 = 842290766, // non-subsampled Cb:Cr plane
        p210 = 808530512, // 2x1 subsampled Cr:Cb plane, 10 bit per channel
        p010 = 808530000, // 2x2 subsampled Cr:Cb plane 10 bits per channel
        p012 = 842084432, // 2x2 subsampled Cr:Cb plane 12 bits per channel
        p016 = 909193296, // 2x2 subsampled Cr:Cb plane 16 bits per channel
        axbxgxrx106106106106 = 808534593, // [63:0] A:x:B:x:G:x:R:x 10:6:10:6:10:6:10:6 little endian
        nv15 = 892425806, // 2x2 subsampled Cr:Cb plane
        q410 = 808531025,
        q401 = 825242705,
        xrgb16161616 = 942953048, // [63:0] x:R:G:B 16:16:16:16 little endian
        xbgr16161616 = 942948952, // [63:0] x:B:G:R 16:16:16:16 little endian
        argb16161616 = 942953025, // [63:0] A:R:G:B 16:16:16:16 little endian
        abgr16161616 = 942948929, // [63:0] A:B:G:R 16:16:16:16 little endian
        c1 = 538980675, // [7:0] C0:C1:C2:C3:C4:C5:C6:C7 1:1:1:1:1:1:1:1 eight pixels/byte
        c2 = 538980931, // [7:0] C0:C1:C2:C3 2:2:2:2 four pixels/byte
        c4 = 538981443, // [7:0] C0:C1 4:4 two pixels/byte
        d1 = 538980676, // [7:0] D0:D1:D2:D3:D4:D5:D6:D7 1:1:1:1:1:1:1:1 eight pixels/byte
        d2 = 538980932, // [7:0] D0:D1:D2:D3 2:2:2:2 four pixels/byte
        d4 = 538981444, // [7:0] D0:D1 4:4 two pixels/byte
        d8 = 538982468, // [7:0] D
        r1 = 538980690, // [7:0] R0:R1:R2:R3:R4:R5:R6:R7 1:1:1:1:1:1:1:1 eight pixels/byte
        r2 = 538980946, // [7:0] R0:R1:R2:R3 2:2:2:2 four pixels/byte
        r4 = 538981458, // [7:0] R0:R1 4:4 two pixels/byte
        r10 = 540029266, // [15:0] x:R 6:10 little endian
        r12 = 540160338, // [15:0] x:R 4:12 little endian
        avuy8888 = 1498764865, // [31:0] A:Cr:Cb:Y 8:8:8:8 little endian
        xvuy8888 = 1498764888, // [31:0] X:Cr:Cb:Y 8:8:8:8 little endian
        p030 = 808661072, // 2x2 subsampled Cr:Cb plane 10 bits per channel packed
    };

    pub fn createPool() void {}

    pub fn release() void {}

};

pub const Buffer = struct {
    pub const opcode = struct {
        pub const request = struct {
            pub const destroy: u16 = 0;
        };
        pub const event = struct {
            pub const release: u16 = 0;
        };
    };

    pub fn destroy() void {}

};

pub const DataOffer = struct {
    pub const opcode = struct {
        pub const request = struct {
            pub const accept: u16 = 0;
            pub const receive: u16 = 1;
            pub const destroy: u16 = 2;
            pub const finish: u16 = 3;
            pub const setActions: u16 = 4;
        };
        pub const event = struct {
            pub const offer: u16 = 0;
            pub const sourceActions: u16 = 1;
            pub const action: u16 = 2;
        };
    };

    pub const Error = enum(u32) {
        invalid_finish = 0, // finish request was called untimely
        invalid_action_mask = 1, // action mask contains invalid values
        invalid_action = 2, // action argument has an invalid value
        invalid_offer = 3, // offer doesn't accept this request
    };

    pub fn accept() void {}

    pub fn receive() void {}

    pub fn destroy() void {}

    pub fn finish() void {}

    pub fn setActions() void {}

};

pub const DataSource = struct {
    pub const opcode = struct {
        pub const request = struct {
            pub const offer: u16 = 0;
            pub const destroy: u16 = 1;
            pub const setActions: u16 = 2;
        };
        pub const event = struct {
            pub const target: u16 = 0;
            pub const send: u16 = 1;
            pub const cancelled: u16 = 2;
            pub const dndDropPerformed: u16 = 3;
            pub const dndFinished: u16 = 4;
            pub const action: u16 = 5;
        };
    };

    pub const Error = enum(u32) {
        invalid_action_mask = 0, // action mask contains invalid values
        invalid_source = 1, // source doesn't accept this request
    };

    pub fn offer() void {}

    pub fn destroy() void {}

    pub fn setActions() void {}

};

pub const DataDevice = struct {
    pub const opcode = struct {
        pub const request = struct {
            pub const startDrag: u16 = 0;
            pub const setSelection: u16 = 1;
            pub const release: u16 = 2;
        };
        pub const event = struct {
            pub const dataOffer: u16 = 0;
            pub const enter: u16 = 1;
            pub const leave: u16 = 2;
            pub const motion: u16 = 3;
            pub const drop: u16 = 4;
            pub const selection: u16 = 5;
        };
    };

    pub const Error = enum(u32) {
        role = 0, // given wl_surface has another role
        used_source = 1, // source has already been used
    };

    pub fn startDrag() void {}

    pub fn setSelection() void {}

    pub fn release() void {}

};

pub const DataDeviceManager = struct {
    pub const opcode = struct {
        pub const request = struct {
            pub const createDataSource: u16 = 0;
            pub const getDataDevice: u16 = 1;
        };
        pub const event = struct {
        };
    };

    pub const DndAction = enum(u32) {
        none = 0, // no action
        copy = 1, // copy action
        move = 2, // move action
        ask = 4, // ask action
    };

    pub fn createDataSource() void {}

    pub fn getDataDevice() void {}

};

pub const Shell = struct {
    pub const opcode = struct {
        pub const request = struct {
            pub const getShellSurface: u16 = 0;
        };
        pub const event = struct {
        };
    };

    pub const Error = enum(u32) {
        role = 0, // given wl_surface has another role
    };

    pub fn getShellSurface() void {}

};

pub const ShellSurface = struct {
    pub const opcode = struct {
        pub const request = struct {
            pub const pong: u16 = 0;
            pub const move: u16 = 1;
            pub const resize: u16 = 2;
            pub const setToplevel: u16 = 3;
            pub const setTransient: u16 = 4;
            pub const setFullscreen: u16 = 5;
            pub const setPopup: u16 = 6;
            pub const setMaximized: u16 = 7;
            pub const setTitle: u16 = 8;
            pub const setClass: u16 = 9;
        };
        pub const event = struct {
            pub const ping: u16 = 0;
            pub const configure: u16 = 1;
            pub const popupDone: u16 = 2;
        };
    };

    pub const Resize = enum(u32) {
        none = 0, // no edge
        top = 1, // top edge
        bottom = 2, // bottom edge
        left = 4, // left edge
        top_left = 5, // top and left edges
        bottom_left = 6, // bottom and left edges
        right = 8, // right edge
        top_right = 9, // top and right edges
        bottom_right = 10, // bottom and right edges
    };

    pub const Transient = enum(u32) {
        inactive = 1, // do not set keyboard focus
    };

    pub const FullscreenMethod = enum(u32) {
        default = 0, // no preference, apply default policy
        scale = 1, // scale, preserve the surface's aspect ratio and center on output
        driver = 2, // switch output mode to the smallest mode that can fit the surface, add black borders to compensate size mismatch
        fill = 3, // no upscaling, center on output and add black borders to compensate size mismatch
    };

    pub fn pong() void {}

    pub fn move() void {}

    pub fn resize() void {}

    pub fn setToplevel() void {}

    pub fn setTransient() void {}

    pub fn setFullscreen() void {}

    pub fn setPopup() void {}

    pub fn setMaximized() void {}

    pub fn setTitle() void {}

    pub fn setClass() void {}

};

pub const Surface = struct {
    pub const opcode = struct {
        pub const request = struct {
            pub const destroy: u16 = 0;
            pub const attach: u16 = 1;
            pub const damage: u16 = 2;
            pub const frame: u16 = 3;
            pub const setOpaqueRegion: u16 = 4;
            pub const setInputRegion: u16 = 5;
            pub const commit: u16 = 6;
            pub const setBufferTransform: u16 = 7;
            pub const setBufferScale: u16 = 8;
            pub const damageBuffer: u16 = 9;
            pub const offset: u16 = 10;
        };
        pub const event = struct {
            pub const enter: u16 = 0;
            pub const leave: u16 = 1;
            pub const preferredBufferScale: u16 = 2;
            pub const preferredBufferTransform: u16 = 3;
        };
    };

    pub const Error = enum(u32) {
        invalid_scale = 0, // buffer scale value is invalid
        invalid_transform = 1, // buffer transform value is invalid
        invalid_size = 2, // buffer size is invalid
        invalid_offset = 3, // buffer offset is invalid
        defunct_role_object = 4, // surface was destroyed before its role object
    };

    pub fn destroy() void {}

    pub fn attach() void {}

    pub fn damage() void {}

    pub fn frame() void {}

    pub fn setOpaqueRegion() void {}

    pub fn setInputRegion() void {}

    pub fn commit() void {}

    pub fn setBufferTransform() void {}

    pub fn setBufferScale() void {}

    pub fn damageBuffer() void {}

    pub fn offset() void {}

};

pub const Seat = struct {
    pub const opcode = struct {
        pub const request = struct {
            pub const getPointer: u16 = 0;
            pub const getKeyboard: u16 = 1;
            pub const getTouch: u16 = 2;
            pub const release: u16 = 3;
        };
        pub const event = struct {
            pub const capabilities: u16 = 0;
            pub const name: u16 = 1;
        };
    };

    pub const Capability = enum(u32) {
        pointer = 1, // the seat has pointer devices
        keyboard = 2, // the seat has one or more keyboards
        touch = 4, // the seat has touch devices
    };

    pub const Error = enum(u32) {
        missing_capability = 0, // get_pointer, get_keyboard or get_touch called on seat without the matching capability
    };

    pub fn getPointer() void {}

    pub fn getKeyboard() void {}

    pub fn getTouch() void {}

    pub fn release() void {}

};

pub const Pointer = struct {
    pub const opcode = struct {
        pub const request = struct {
            pub const setCursor: u16 = 0;
            pub const release: u16 = 1;
        };
        pub const event = struct {
            pub const enter: u16 = 0;
            pub const leave: u16 = 1;
            pub const motion: u16 = 2;
            pub const button: u16 = 3;
            pub const axis: u16 = 4;
            pub const frame: u16 = 5;
            pub const axisSource: u16 = 6;
            pub const axisStop: u16 = 7;
            pub const axisDiscrete: u16 = 8;
            pub const axisValue120: u16 = 9;
            pub const axisRelativeDirection: u16 = 10;
        };
    };

    pub const Error = enum(u32) {
        role = 0, // given wl_surface has another role
    };

    pub const ButtonState = enum(u32) {
        released = 0, // the button is not pressed
        pressed = 1, // the button is pressed
    };

    pub const Axis = enum(u32) {
        vertical_scroll = 0, // vertical axis
        horizontal_scroll = 1, // horizontal axis
    };

    pub const AxisSource = enum(u32) {
        wheel = 0, // a physical wheel rotation
        finger = 1, // finger on a touch surface
        continuous = 2, // continuous coordinate space
        wheel_tilt = 3, // a physical wheel tilt
    };

    pub const AxisRelativeDirection = enum(u32) {
        identical = 0, // physical motion matches axis direction
        inverted = 1, // physical motion is the inverse of the axis direction
    };

    pub fn setCursor() void {}

    pub fn release() void {}

};

pub const Keyboard = struct {
    pub const opcode = struct {
        pub const request = struct {
            pub const release: u16 = 0;
        };
        pub const event = struct {
            pub const keymap: u16 = 0;
            pub const enter: u16 = 1;
            pub const leave: u16 = 2;
            pub const key: u16 = 3;
            pub const modifiers: u16 = 4;
            pub const repeatInfo: u16 = 5;
        };
    };

    pub const KeymapFormat = enum(u32) {
        no_keymap = 0, // no keymap; client must understand how to interpret the raw keycode
        xkb_v1 = 1, // libxkbcommon compatible, null-terminated string; to determine the xkb keycode, clients must add 8 to the key event keycode
    };

    pub const KeyState = enum(u32) {
        released = 0, // key is not pressed
        pressed = 1, // key is pressed
    };

    pub fn release() void {}

};

pub const Touch = struct {
    pub const opcode = struct {
        pub const request = struct {
            pub const release: u16 = 0;
        };
        pub const event = struct {
            pub const down: u16 = 0;
            pub const up: u16 = 1;
            pub const motion: u16 = 2;
            pub const frame: u16 = 3;
            pub const cancel: u16 = 4;
            pub const shape: u16 = 5;
            pub const orientation: u16 = 6;
        };
    };

    pub fn release() void {}

};

pub const Output = struct {
    pub const opcode = struct {
        pub const request = struct {
            pub const release: u16 = 0;
        };
        pub const event = struct {
            pub const geometry: u16 = 0;
            pub const mode: u16 = 1;
            pub const done: u16 = 2;
            pub const scale: u16 = 3;
            pub const name: u16 = 4;
            pub const description: u16 = 5;
        };
    };

    pub const Subpixel = enum(u32) {
        unknown = 0, // unknown geometry
        none = 1, // no geometry
        horizontal_rgb = 2, // horizontal RGB
        horizontal_bgr = 3, // horizontal BGR
        vertical_rgb = 4, // vertical RGB
        vertical_bgr = 5, // vertical BGR
    };

    pub const Transform = enum(u32) {
        normal = 0, // no transform
        @"90" = 1, // 90 degrees counter-clockwise
        @"180" = 2, // 180 degrees counter-clockwise
        @"270" = 3, // 270 degrees counter-clockwise
        flipped = 4, // 180 degree flip around a vertical axis
        flipped_90 = 5, // flip and rotate 90 degrees counter-clockwise
        flipped_180 = 6, // flip and rotate 180 degrees counter-clockwise
        flipped_270 = 7, // flip and rotate 270 degrees counter-clockwise
    };

    pub const Mode = enum(u32) {
        current = 1, // indicates this is the current mode
        preferred = 2, // indicates this is the preferred mode
    };

    pub fn release() void {}

};

pub const Region = struct {
    pub const opcode = struct {
        pub const request = struct {
            pub const destroy: u16 = 0;
            pub const add: u16 = 1;
            pub const subtract: u16 = 2;
        };
        pub const event = struct {
        };
    };

    pub fn destroy() void {}

    pub fn add() void {}

    pub fn subtract() void {}

};

pub const Subcompositor = struct {
    pub const opcode = struct {
        pub const request = struct {
            pub const destroy: u16 = 0;
            pub const getSubsurface: u16 = 1;
        };
        pub const event = struct {
        };
    };

    pub const Error = enum(u32) {
        bad_surface = 0, // the to-be sub-surface is invalid
        bad_parent = 1, // the to-be sub-surface parent is invalid
    };

    pub fn destroy() void {}

    pub fn getSubsurface() void {}

};

pub const Subsurface = struct {
    pub const opcode = struct {
        pub const request = struct {
            pub const destroy: u16 = 0;
            pub const setPosition: u16 = 1;
            pub const placeAbove: u16 = 2;
            pub const placeBelow: u16 = 3;
            pub const setSync: u16 = 4;
            pub const setDesync: u16 = 5;
        };
        pub const event = struct {
        };
    };

    pub const Error = enum(u32) {
        bad_surface = 0, // wl_surface is not a sibling or the parent
    };

    pub fn destroy() void {}

    pub fn setPosition() void {}

    pub fn placeAbove() void {}

    pub fn placeBelow() void {}

    pub fn setSync() void {}

    pub fn setDesync() void {}

};

