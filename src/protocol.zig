// Copyright © 2008-2011 Kristian Høgsberg
// Copyright © 2010-2011 Intel Corporation
// Copyright © 2012-2013 Collabora, Ltd.
// 
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation files
// (the "Software"), to deal in the Software without restriction,
// including without limitation the rights to use, copy, modify, merge,
// publish, distribute, sublicense, and/or sell copies of the Software,
// and to permit persons to whom the Software is furnished to do so,
// subject to the following conditions:
// 
// The above copyright notice and this permission notice (including the
// next paragraph) shall be included in all copies or substantial
// portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT.  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

const util = @import("util.zig");
const ints = struct {
    usingnamespace @import("protocol.zig");
};

const Object = util.Object;
const Fixed = util.Fixed;
const FD = util.FD;
const WaylandState = util.WaylandState;


/// The core global object.  This is a special singleton object.  It
/// is used for internal Wayland protocol features.
pub const wl_display = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

    pub const opcode = struct {
        pub const request = struct {
            pub const sync: u16 = 0;
            pub const get_registry: u16 = 1;
        };
        pub const event = struct {
            pub const @"error": u16 = 0;
            pub const delete_id: u16 = 1;
        };
    };

    /// These errors are global and can be emitted in response to any
    /// server request.
    pub const Error = enum(u32) {
        invalid_object = 0, // server couldn't find object
        invalid_method = 1, // method doesn't exist on the specified interface or malformed request
        no_memory = 2, // server is out of memory
        implementation = 3, // implementation error in compositor
    };

    /// The sync request asks the server to emit the 'done' event
    /// on the returned wl_callback object.  Since requests are
    /// handled in-order and events are delivered in-order, this can
    /// be used as a barrier to ensure all previous requests and the
    /// resulting events have been handled.
    /// 
    /// The object returned by this request will be destroyed by the
    /// compositor after the callback is fired and as such the client must not
    /// attempt to use it after that point.
    /// 
    /// The callback_data passed in the callback is undefined and should be ignored.
    pub fn sync(self: Self) !ints.wl_callback {
        const new_id = self.global.nextObjectId();
        const new_obj = ints.wl_callback {
            .id = new_id,
            .global = self.global,
        };

        const op = Self.opcode.request.sync;
        try self.global.sendRequest(self.id, op, .{ new_id, });
        return new_obj;
    }

    /// This request creates a registry object that allows the client
    /// to list and bind the global objects available from the
    /// compositor.
    /// 
    /// It should be noted that the server side resources consumed in
    /// response to a get_registry request can only be released when the
    /// client disconnects, not when the client side proxy is destroyed.
    /// Therefore, clients should invoke get_registry as infrequently as
    /// possible to avoid wasting memory.
    pub fn getRegistry(self: Self) !ints.wl_registry {
        const new_id = self.global.nextObjectId();
        const new_obj = ints.wl_registry {
            .id = new_id,
            .global = self.global,
        };

        const op = Self.opcode.request.get_registry;
        try self.global.sendRequest(self.id, op, .{ new_id, });
        return new_obj;
    }

};

/// The singleton global registry object.  The server has a number of
/// global objects that are available to all clients.  These objects
/// typically represent an actual object in the server (for example,
/// an input device) or they are singleton objects that provide
/// extension functionality.
/// 
/// When a client creates a registry object, the registry object
/// will emit a global event for each global currently in the
/// registry.  Globals come and go as a result of device or
/// monitor hotplugs, reconfiguration or other events, and the
/// registry will send out global and global_remove events to
/// keep the client up to date with the changes.  To mark the end
/// of the initial burst of events, the client can use the
/// wl_display.sync request immediately after calling
/// wl_display.get_registry.
/// 
/// A client can bind to a global object by using the bind
/// request.  This creates a client-side handle that lets the object
/// emit events to the client and lets the client invoke requests on
/// the object.
pub const wl_registry = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

    pub const opcode = struct {
        pub const request = struct {
            pub const bind: u16 = 0;
        };
        pub const event = struct {
            pub const global: u16 = 0;
            pub const global_remove: u16 = 1;
        };
    };

    /// Binds a new, client-created object to the server using the
    /// specified name as the identifier.
    pub fn bind(self: Self, name: u32) !Object {
        const new_id = self.global.nextObjectId();
        const new_obj = Object {
            .id = new_id,
            .global = self.global,
        };

        const op = Self.opcode.request.bind;
        try self.global.sendRequest(self.id, op, .{ name, new_id, });
        return new_obj;
    }

};

/// Clients can handle the 'done' event to get notified when
/// the related request is done.
/// 
/// Note, because wl_callback objects are created from multiple independent
/// factory interfaces, the wl_callback interface is frozen at version 1.
pub const wl_callback = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

    pub const opcode = struct {
        pub const event = struct {
            pub const done: u16 = 0;
        };
    };

};

/// A compositor.  This object is a singleton global.  The
/// compositor is in charge of combining the contents of multiple
/// surfaces into one displayable output.
pub const wl_compositor = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

    pub const opcode = struct {
        pub const request = struct {
            pub const create_surface: u16 = 0;
            pub const create_region: u16 = 1;
        };
    };

    /// Ask the compositor to create a new surface.
    pub fn createSurface(self: Self) !ints.wl_surface {
        const new_id = self.global.nextObjectId();
        const new_obj = ints.wl_surface {
            .id = new_id,
            .global = self.global,
        };

        const op = Self.opcode.request.create_surface;
        try self.global.sendRequest(self.id, op, .{ new_id, });
        return new_obj;
    }

    /// Ask the compositor to create a new region.
    pub fn createRegion(self: Self) !ints.wl_region {
        const new_id = self.global.nextObjectId();
        const new_obj = ints.wl_region {
            .id = new_id,
            .global = self.global,
        };

        const op = Self.opcode.request.create_region;
        try self.global.sendRequest(self.id, op, .{ new_id, });
        return new_obj;
    }

};

/// The wl_shm_pool object encapsulates a piece of memory shared
/// between the compositor and client.  Through the wl_shm_pool
/// object, the client can allocate shared memory wl_buffer objects.
/// All objects created through the same pool share the same
/// underlying mapped memory. Reusing the mapped memory avoids the
/// setup/teardown overhead and is useful when interactively resizing
/// a surface or for many small buffers.
pub const wl_shm_pool = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

    pub const opcode = struct {
        pub const request = struct {
            pub const create_buffer: u16 = 0;
            pub const destroy: u16 = 1;
            pub const resize: u16 = 2;
        };
    };

    /// Create a wl_buffer object from the pool.
    /// 
    /// The buffer is created offset bytes into the pool and has
    /// width and height as specified.  The stride argument specifies
    /// the number of bytes from the beginning of one row to the beginning
    /// of the next.  The format is the pixel format of the buffer and
    /// must be one of those advertised through the wl_shm.format event.
    /// 
    /// A buffer will keep a reference to the pool it was created from
    /// so it is valid to destroy the pool immediately after creating
    /// a buffer from it.
    pub fn createBuffer(self: Self, offset: i32, width: i32, height: i32, stride: i32, format: ints.wl_shm.Format) !ints.wl_buffer {
        const new_id = self.global.nextObjectId();
        const new_obj = ints.wl_buffer {
            .id = new_id,
            .global = self.global,
        };

        const op = Self.opcode.request.create_buffer;
        try self.global.sendRequest(self.id, op, .{ new_id, offset, width, height, stride, format, });
        return new_obj;
    }

    /// Destroy the shared memory pool.
    /// 
    /// The mmapped memory will be released when all
    /// buffers that have been created from this pool
    /// are gone.
    pub fn destroy(self: Self) !void {
        const op = Self.opcode.request.destroy;
        try self.global.sendRequest(self.id, op, .{ });
    }

    /// This request will cause the server to remap the backing memory
    /// for the pool from the file descriptor passed when the pool was
    /// created, but using the new size.  This request can only be
    /// used to make the pool bigger.
    /// 
    /// This request only changes the amount of bytes that are mmapped
    /// by the server and does not touch the file corresponding to the
    /// file descriptor passed at creation time. It is the client's
    /// responsibility to ensure that the file is at least as big as
    /// the new pool size.
    pub fn resize(self: Self, size: i32) !void {
        const op = Self.opcode.request.resize;
        try self.global.sendRequest(self.id, op, .{ size, });
    }

};

/// A singleton global object that provides support for shared
/// memory.
/// 
/// Clients can create wl_shm_pool objects using the create_pool
/// request.
/// 
/// On binding the wl_shm object one or more format events
/// are emitted to inform clients about the valid pixel formats
/// that can be used for buffers.
pub const wl_shm = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

    pub const opcode = struct {
        pub const request = struct {
            pub const create_pool: u16 = 0;
            pub const release: u16 = 1;
        };
        pub const event = struct {
            pub const format: u16 = 0;
        };
    };

    /// These errors can be emitted in response to wl_shm requests.
    pub const Error = enum(u32) {
        invalid_format = 0, // buffer format is not known
        invalid_stride = 1, // invalid size or stride during pool or buffer creation
        invalid_fd = 2, // mmapping the file descriptor failed
    };

    /// This describes the memory layout of an individual pixel.
    /// 
    /// All renderers should support argb8888 and xrgb8888 but any other
    /// formats are optional and may not be supported by the particular
    /// renderer in use.
    /// 
    /// The drm format codes match the macros defined in drm_fourcc.h, except
    /// argb8888 and xrgb8888. The formats actually supported by the compositor
    /// will be reported by the format event.
    /// 
    /// For all wl_shm formats and unless specified in another protocol
    /// extension, pre-multiplied alpha is used for pixel values.
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

    /// Create a new wl_shm_pool object.
    /// 
    /// The pool can be used to create shared memory based buffer
    /// objects.  The server will mmap size bytes of the passed file
    /// descriptor, to use as backing memory for the pool.
    pub fn createPool(self: Self, fd: FD, size: i32) !ints.wl_shm_pool {
        const new_id = self.global.nextObjectId();
        const new_obj = ints.wl_shm_pool {
            .id = new_id,
            .global = self.global,
        };

        const op = Self.opcode.request.create_pool;
        try self.global.sendRequest(self.id, op, .{ new_id, fd, size, });
        return new_obj;
    }

    /// Using this request a client can tell the server that it is not going to
    /// use the shm object anymore.
    /// 
    /// Objects created via this interface remain unaffected.
    pub fn release(self: Self) !void {
        const op = Self.opcode.request.release;
        try self.global.sendRequest(self.id, op, .{ });
    }

};

/// A buffer provides the content for a wl_surface. Buffers are
/// created through factory interfaces such as wl_shm, wp_linux_buffer_params
/// (from the linux-dmabuf protocol extension) or similar. It has a width and
/// a height and can be attached to a wl_surface, but the mechanism by which a
/// client provides and updates the contents is defined by the buffer factory
/// interface.
/// 
/// Color channels are assumed to be electrical rather than optical (in other
/// words, encoded with a transfer function) unless otherwise specified. If
/// the buffer uses a format that has an alpha channel, the alpha channel is
/// assumed to be premultiplied into the electrical color channel values
/// (after transfer function encoding) unless otherwise specified.
/// 
/// Note, because wl_buffer objects are created from multiple independent
/// factory interfaces, the wl_buffer interface is frozen at version 1.
pub const wl_buffer = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

    pub const opcode = struct {
        pub const request = struct {
            pub const destroy: u16 = 0;
        };
        pub const event = struct {
            pub const release: u16 = 0;
        };
    };

    /// Destroy a buffer. If and how you need to release the backing
    /// storage is defined by the buffer factory interface.
    /// 
    /// For possible side-effects to a surface, see wl_surface.attach.
    pub fn destroy(self: Self) !void {
        const op = Self.opcode.request.destroy;
        try self.global.sendRequest(self.id, op, .{ });
    }

};

/// A wl_data_offer represents a piece of data offered for transfer
/// by another client (the source client).  It is used by the
/// copy-and-paste and drag-and-drop mechanisms.  The offer
/// describes the different mime types that the data can be
/// converted to and provides the mechanism for transferring the
/// data directly from the source client.
pub const wl_data_offer = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

    pub const opcode = struct {
        pub const request = struct {
            pub const accept: u16 = 0;
            pub const receive: u16 = 1;
            pub const destroy: u16 = 2;
            pub const finish: u16 = 3;
            pub const set_actions: u16 = 4;
        };
        pub const event = struct {
            pub const offer: u16 = 0;
            pub const source_actions: u16 = 1;
            pub const action: u16 = 2;
        };
    };

    pub const Error = enum(u32) {
        invalid_finish = 0, // finish request was called untimely
        invalid_action_mask = 1, // action mask contains invalid values
        invalid_action = 2, // action argument has an invalid value
        invalid_offer = 3, // offer doesn't accept this request
    };

    /// Indicate that the client can accept the given mime type, or
    /// NULL for not accepted.
    /// 
    /// For objects of version 2 or older, this request is used by the
    /// client to give feedback whether the client can receive the given
    /// mime type, or NULL if none is accepted; the feedback does not
    /// determine whether the drag-and-drop operation succeeds or not.
    /// 
    /// For objects of version 3 or newer, this request determines the
    /// final result of the drag-and-drop operation. If the end result
    /// is that no mime types were accepted, the drag-and-drop operation
    /// will be cancelled and the corresponding drag source will receive
    /// wl_data_source.cancelled. Clients may still use this event in
    /// conjunction with wl_data_source.action for feedback.
    pub fn accept(self: Self, serial: u32, mime_type: ?[:0]const u8) !void {
        const op = Self.opcode.request.accept;
        try self.global.sendRequest(self.id, op, .{ serial, mime_type, });
    }

    /// To transfer the offered data, the client issues this request
    /// and indicates the mime type it wants to receive.  The transfer
    /// happens through the passed file descriptor (typically created
    /// with the pipe system call).  The source client writes the data
    /// in the mime type representation requested and then closes the
    /// file descriptor.
    /// 
    /// The receiving client reads from the read end of the pipe until
    /// EOF and then closes its end, at which point the transfer is
    /// complete.
    /// 
    /// This request may happen multiple times for different mime types,
    /// both before and after wl_data_device.drop. Drag-and-drop destination
    /// clients may preemptively fetch data or examine it more closely to
    /// determine acceptance.
    pub fn receive(self: Self, mime_type: [:0]const u8, fd: FD) !void {
        const op = Self.opcode.request.receive;
        try self.global.sendRequest(self.id, op, .{ mime_type, fd, });
    }

    /// Destroy the data offer.
    pub fn destroy(self: Self) !void {
        const op = Self.opcode.request.destroy;
        try self.global.sendRequest(self.id, op, .{ });
    }

    /// Notifies the compositor that the drag destination successfully
    /// finished the drag-and-drop operation.
    /// 
    /// Upon receiving this request, the compositor will emit
    /// wl_data_source.dnd_finished on the drag source client.
    /// 
    /// It is a client error to perform other requests than
    /// wl_data_offer.destroy after this one. It is also an error to perform
    /// this request after a NULL mime type has been set in
    /// wl_data_offer.accept or no action was received through
    /// wl_data_offer.action.
    /// 
    /// If wl_data_offer.finish request is received for a non drag and drop
    /// operation, the invalid_finish protocol error is raised.
    pub fn finish(self: Self) !void {
        const op = Self.opcode.request.finish;
        try self.global.sendRequest(self.id, op, .{ });
    }

    /// Sets the actions that the destination side client supports for
    /// this operation. This request may trigger the emission of
    /// wl_data_source.action and wl_data_offer.action events if the compositor
    /// needs to change the selected action.
    /// 
    /// This request can be called multiple times throughout the
    /// drag-and-drop operation, typically in response to wl_data_device.enter
    /// or wl_data_device.motion events.
    /// 
    /// This request determines the final result of the drag-and-drop
    /// operation. If the end result is that no action is accepted,
    /// the drag source will receive wl_data_source.cancelled.
    /// 
    /// The dnd_actions argument must contain only values expressed in the
    /// wl_data_device_manager.dnd_actions enum, and the preferred_action
    /// argument must only contain one of those values set, otherwise it
    /// will result in a protocol error.
    /// 
    /// While managing an "ask" action, the destination drag-and-drop client
    /// may perform further wl_data_offer.receive requests, and is expected
    /// to perform one last wl_data_offer.set_actions request with a preferred
    /// action other than "ask" (and optionally wl_data_offer.accept) before
    /// requesting wl_data_offer.finish, in order to convey the action selected
    /// by the user. If the preferred action is not in the
    /// wl_data_offer.source_actions mask, an error will be raised.
    /// 
    /// If the "ask" action is dismissed (e.g. user cancellation), the client
    /// is expected to perform wl_data_offer.destroy right away.
    /// 
    /// This request can only be made on drag-and-drop offers, a protocol error
    /// will be raised otherwise.
    pub fn setActions(self: Self, dnd_actions: ints.wl_data_device_manager.DndAction, preferred_action: ints.wl_data_device_manager.DndAction) !void {
        const op = Self.opcode.request.set_actions;
        try self.global.sendRequest(self.id, op, .{ dnd_actions, preferred_action, });
    }

};

/// The wl_data_source object is the source side of a wl_data_offer.
/// It is created by the source client in a data transfer and
/// provides a way to describe the offered data and a way to respond
/// to requests to transfer the data.
pub const wl_data_source = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

    pub const opcode = struct {
        pub const request = struct {
            pub const offer: u16 = 0;
            pub const destroy: u16 = 1;
            pub const set_actions: u16 = 2;
        };
        pub const event = struct {
            pub const target: u16 = 0;
            pub const send: u16 = 1;
            pub const cancelled: u16 = 2;
            pub const dnd_drop_performed: u16 = 3;
            pub const dnd_finished: u16 = 4;
            pub const action: u16 = 5;
        };
    };

    pub const Error = enum(u32) {
        invalid_action_mask = 0, // action mask contains invalid values
        invalid_source = 1, // source doesn't accept this request
    };

    /// This request adds a mime type to the set of mime types
    /// advertised to targets.  Can be called several times to offer
    /// multiple types.
    pub fn offer(self: Self, mime_type: [:0]const u8) !void {
        const op = Self.opcode.request.offer;
        try self.global.sendRequest(self.id, op, .{ mime_type, });
    }

    /// Destroy the data source.
    pub fn destroy(self: Self) !void {
        const op = Self.opcode.request.destroy;
        try self.global.sendRequest(self.id, op, .{ });
    }

    /// Sets the actions that the source side client supports for this
    /// operation. This request may trigger wl_data_source.action and
    /// wl_data_offer.action events if the compositor needs to change the
    /// selected action.
    /// 
    /// The dnd_actions argument must contain only values expressed in the
    /// wl_data_device_manager.dnd_actions enum, otherwise it will result
    /// in a protocol error.
    /// 
    /// This request must be made once only, and can only be made on sources
    /// used in drag-and-drop, so it must be performed before
    /// wl_data_device.start_drag. Attempting to use the source other than
    /// for drag-and-drop will raise a protocol error.
    pub fn setActions(self: Self, dnd_actions: ints.wl_data_device_manager.DndAction) !void {
        const op = Self.opcode.request.set_actions;
        try self.global.sendRequest(self.id, op, .{ dnd_actions, });
    }

};

/// There is one wl_data_device per seat which can be obtained
/// from the global wl_data_device_manager singleton.
/// 
/// A wl_data_device provides access to inter-client data transfer
/// mechanisms such as copy-and-paste and drag-and-drop.
pub const wl_data_device = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

    pub const opcode = struct {
        pub const request = struct {
            pub const start_drag: u16 = 0;
            pub const set_selection: u16 = 1;
            pub const release: u16 = 2;
        };
        pub const event = struct {
            pub const data_offer: u16 = 0;
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

    /// This request asks the compositor to start a drag-and-drop
    /// operation on behalf of the client.
    /// 
    /// The source argument is the data source that provides the data
    /// for the eventual data transfer. If source is NULL, enter, leave
    /// and motion events are sent only to the client that initiated the
    /// drag and the client is expected to handle the data passing
    /// internally. If source is destroyed, the drag-and-drop session will be
    /// cancelled.
    /// 
    /// The origin surface is the surface where the drag originates and
    /// the client must have an active implicit grab that matches the
    /// serial.
    /// 
    /// The icon surface is an optional (can be NULL) surface that
    /// provides an icon to be moved around with the cursor.  Initially,
    /// the top-left corner of the icon surface is placed at the cursor
    /// hotspot, but subsequent wl_surface.offset requests can move the
    /// relative position. Attach requests must be confirmed with
    /// wl_surface.commit as usual. The icon surface is given the role of
    /// a drag-and-drop icon. If the icon surface already has another role,
    /// it raises a protocol error.
    /// 
    /// The input region is ignored for wl_surfaces with the role of a
    /// drag-and-drop icon.
    /// 
    /// The given source may not be used in any further set_selection or
    /// start_drag requests. Attempting to reuse a previously-used source
    /// may send a used_source error.
    pub fn startDrag(self: Self, source: ?ints.wl_data_source, origin: ints.wl_surface, icon: ?ints.wl_surface, serial: u32) !void {
        const op = Self.opcode.request.start_drag;
        try self.global.sendRequest(self.id, op, .{ source, origin, icon, serial, });
    }

    /// This request asks the compositor to set the selection
    /// to the data from the source on behalf of the client.
    /// 
    /// To unset the selection, set the source to NULL.
    /// 
    /// The given source may not be used in any further set_selection or
    /// start_drag requests. Attempting to reuse a previously-used source
    /// may send a used_source error.
    pub fn setSelection(self: Self, source: ?ints.wl_data_source, serial: u32) !void {
        const op = Self.opcode.request.set_selection;
        try self.global.sendRequest(self.id, op, .{ source, serial, });
    }

    /// This request destroys the data device.
    pub fn release(self: Self) !void {
        const op = Self.opcode.request.release;
        try self.global.sendRequest(self.id, op, .{ });
    }

};

/// The wl_data_device_manager is a singleton global object that
/// provides access to inter-client data transfer mechanisms such as
/// copy-and-paste and drag-and-drop.  These mechanisms are tied to
/// a wl_seat and this interface lets a client get a wl_data_device
/// corresponding to a wl_seat.
/// 
/// Depending on the version bound, the objects created from the bound
/// wl_data_device_manager object will have different requirements for
/// functioning properly. See wl_data_source.set_actions,
/// wl_data_offer.accept and wl_data_offer.finish for details.
pub const wl_data_device_manager = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

    pub const opcode = struct {
        pub const request = struct {
            pub const create_data_source: u16 = 0;
            pub const get_data_device: u16 = 1;
        };
    };

    /// This is a bitmask of the available/preferred actions in a
    /// drag-and-drop operation.
    /// 
    /// In the compositor, the selected action is a result of matching the
    /// actions offered by the source and destination sides.  "action" events
    /// with a "none" action will be sent to both source and destination if
    /// there is no match. All further checks will effectively happen on
    /// (source actions ∩ destination actions).
    /// 
    /// In addition, compositors may also pick different actions in
    /// reaction to key modifiers being pressed. One common design that
    /// is used in major toolkits (and the behavior recommended for
    /// compositors) is:
    /// 
    /// - If no modifiers are pressed, the first match (in bit order)
    /// will be used.
    /// - Pressing Shift selects "move", if enabled in the mask.
    /// - Pressing Control selects "copy", if enabled in the mask.
    /// 
    /// Behavior beyond that is considered implementation-dependent.
    /// Compositors may for example bind other modifiers (like Alt/Meta)
    /// or drags initiated with other buttons than BTN_LEFT to specific
    /// actions (e.g. "ask").
    pub const DndAction = enum(u32) {
        none = 0, // no action
        copy = 1, // copy action
        move = 2, // move action
        ask = 4, // ask action
    };

    /// Create a new data source.
    pub fn createDataSource(self: Self) !ints.wl_data_source {
        const new_id = self.global.nextObjectId();
        const new_obj = ints.wl_data_source {
            .id = new_id,
            .global = self.global,
        };

        const op = Self.opcode.request.create_data_source;
        try self.global.sendRequest(self.id, op, .{ new_id, });
        return new_obj;
    }

    /// Create a new data device for a given seat.
    pub fn getDataDevice(self: Self, seat: ints.wl_seat) !ints.wl_data_device {
        const new_id = self.global.nextObjectId();
        const new_obj = ints.wl_data_device {
            .id = new_id,
            .global = self.global,
        };

        const op = Self.opcode.request.get_data_device;
        try self.global.sendRequest(self.id, op, .{ new_id, seat, });
        return new_obj;
    }

};

/// This interface is implemented by servers that provide
/// desktop-style user interfaces.
/// 
/// It allows clients to associate a wl_shell_surface with
/// a basic surface.
/// 
/// Note! This protocol is deprecated and not intended for production use.
/// For desktop-style user interfaces, use xdg_shell. Compositors and clients
/// should not implement this interface.
pub const wl_shell = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

    pub const opcode = struct {
        pub const request = struct {
            pub const get_shell_surface: u16 = 0;
        };
    };

    pub const Error = enum(u32) {
        role = 0, // given wl_surface has another role
    };

    /// Create a shell surface for an existing surface. This gives
    /// the wl_surface the role of a shell surface. If the wl_surface
    /// already has another role, it raises a protocol error.
    /// 
    /// Only one shell surface can be associated with a given surface.
    pub fn getShellSurface(self: Self, surface: ints.wl_surface) !ints.wl_shell_surface {
        const new_id = self.global.nextObjectId();
        const new_obj = ints.wl_shell_surface {
            .id = new_id,
            .global = self.global,
        };

        const op = Self.opcode.request.get_shell_surface;
        try self.global.sendRequest(self.id, op, .{ new_id, surface, });
        return new_obj;
    }

};

/// An interface that may be implemented by a wl_surface, for
/// implementations that provide a desktop-style user interface.
/// 
/// It provides requests to treat surfaces like toplevel, fullscreen
/// or popup windows, move, resize or maximize them, associate
/// metadata like title and class, etc.
/// 
/// On the server side the object is automatically destroyed when
/// the related wl_surface is destroyed. On the client side,
/// wl_shell_surface_destroy() must be called before destroying
/// the wl_surface object.
pub const wl_shell_surface = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

    pub const opcode = struct {
        pub const request = struct {
            pub const pong: u16 = 0;
            pub const move: u16 = 1;
            pub const resize: u16 = 2;
            pub const set_toplevel: u16 = 3;
            pub const set_transient: u16 = 4;
            pub const set_fullscreen: u16 = 5;
            pub const set_popup: u16 = 6;
            pub const set_maximized: u16 = 7;
            pub const set_title: u16 = 8;
            pub const set_class: u16 = 9;
        };
        pub const event = struct {
            pub const ping: u16 = 0;
            pub const configure: u16 = 1;
            pub const popup_done: u16 = 2;
        };
    };

    /// These values are used to indicate which edge of a surface
    /// is being dragged in a resize operation. The server may
    /// use this information to adapt its behavior, e.g. choose
    /// an appropriate cursor image.
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

    /// These flags specify details of the expected behaviour
    /// of transient surfaces. Used in the set_transient request.
    pub const Transient = enum(u32) {
        inactive = 1, // do not set keyboard focus
    };

    /// Hints to indicate to the compositor how to deal with a conflict
    /// between the dimensions of the surface and the dimensions of the
    /// output. The compositor is free to ignore this parameter.
    pub const FullscreenMethod = enum(u32) {
        default = 0, // no preference, apply default policy
        scale = 1, // scale, preserve the surface's aspect ratio and center on output
        driver = 2, // switch output mode to the smallest mode that can fit the surface, add black borders to compensate size mismatch
        fill = 3, // no upscaling, center on output and add black borders to compensate size mismatch
    };

    /// A client must respond to a ping event with a pong request or
    /// the client may be deemed unresponsive.
    pub fn pong(self: Self, serial: u32) !void {
        const op = Self.opcode.request.pong;
        try self.global.sendRequest(self.id, op, .{ serial, });
    }

    /// Start a pointer-driven move of the surface.
    /// 
    /// This request must be used in response to a button press event.
    /// The server may ignore move requests depending on the state of
    /// the surface (e.g. fullscreen or maximized).
    pub fn move(self: Self, seat: ints.wl_seat, serial: u32) !void {
        const op = Self.opcode.request.move;
        try self.global.sendRequest(self.id, op, .{ seat, serial, });
    }

    /// Start a pointer-driven resizing of the surface.
    /// 
    /// This request must be used in response to a button press event.
    /// The server may ignore resize requests depending on the state of
    /// the surface (e.g. fullscreen or maximized).
    pub fn resize(self: Self, seat: ints.wl_seat, serial: u32, edges: Resize) !void {
        const op = Self.opcode.request.resize;
        try self.global.sendRequest(self.id, op, .{ seat, serial, edges, });
    }

    /// Map the surface as a toplevel surface.
    /// 
    /// A toplevel surface is not fullscreen, maximized or transient.
    pub fn setToplevel(self: Self) !void {
        const op = Self.opcode.request.set_toplevel;
        try self.global.sendRequest(self.id, op, .{ });
    }

    /// Map the surface relative to an existing surface.
    /// 
    /// The x and y arguments specify the location of the upper left
    /// corner of the surface relative to the upper left corner of the
    /// parent surface, in surface-local coordinates.
    /// 
    /// The flags argument controls details of the transient behaviour.
    pub fn setTransient(self: Self, parent: ints.wl_surface, x: i32, y: i32, flags: Transient) !void {
        const op = Self.opcode.request.set_transient;
        try self.global.sendRequest(self.id, op, .{ parent, x, y, flags, });
    }

    /// Map the surface as a fullscreen surface.
    /// 
    /// If an output parameter is given then the surface will be made
    /// fullscreen on that output. If the client does not specify the
    /// output then the compositor will apply its policy - usually
    /// choosing the output on which the surface has the biggest surface
    /// area.
    /// 
    /// The client may specify a method to resolve a size conflict
    /// between the output size and the surface size - this is provided
    /// through the method parameter.
    /// 
    /// The framerate parameter is used only when the method is set
    /// to "driver", to indicate the preferred framerate. A value of 0
    /// indicates that the client does not care about framerate.  The
    /// framerate is specified in mHz, that is framerate of 60000 is 60Hz.
    /// 
    /// A method of "scale" or "driver" implies a scaling operation of
    /// the surface, either via a direct scaling operation or a change of
    /// the output mode. This will override any kind of output scaling, so
    /// that mapping a surface with a buffer size equal to the mode can
    /// fill the screen independent of buffer_scale.
    /// 
    /// A method of "fill" means we don't scale up the buffer, however
    /// any output scale is applied. This means that you may run into
    /// an edge case where the application maps a buffer with the same
    /// size of the output mode but buffer_scale 1 (thus making a
    /// surface larger than the output). In this case it is allowed to
    /// downscale the results to fit the screen.
    /// 
    /// The compositor must reply to this request with a configure event
    /// with the dimensions for the output on which the surface will
    /// be made fullscreen.
    pub fn setFullscreen(self: Self, method: FullscreenMethod, framerate: u32, output: ?ints.wl_output) !void {
        const op = Self.opcode.request.set_fullscreen;
        try self.global.sendRequest(self.id, op, .{ method, framerate, output, });
    }

    /// Map the surface as a popup.
    /// 
    /// A popup surface is a transient surface with an added pointer
    /// grab.
    /// 
    /// An existing implicit grab will be changed to owner-events mode,
    /// and the popup grab will continue after the implicit grab ends
    /// (i.e. releasing the mouse button does not cause the popup to
    /// be unmapped).
    /// 
    /// The popup grab continues until the window is destroyed or a
    /// mouse button is pressed in any other client's window. A click
    /// in any of the client's surfaces is reported as normal, however,
    /// clicks in other clients' surfaces will be discarded and trigger
    /// the callback.
    /// 
    /// The x and y arguments specify the location of the upper left
    /// corner of the surface relative to the upper left corner of the
    /// parent surface, in surface-local coordinates.
    pub fn setPopup(self: Self, seat: ints.wl_seat, serial: u32, parent: ints.wl_surface, x: i32, y: i32, flags: Transient) !void {
        const op = Self.opcode.request.set_popup;
        try self.global.sendRequest(self.id, op, .{ seat, serial, parent, x, y, flags, });
    }

    /// Map the surface as a maximized surface.
    /// 
    /// If an output parameter is given then the surface will be
    /// maximized on that output. If the client does not specify the
    /// output then the compositor will apply its policy - usually
    /// choosing the output on which the surface has the biggest surface
    /// area.
    /// 
    /// The compositor will reply with a configure event telling
    /// the expected new surface size. The operation is completed
    /// on the next buffer attach to this surface.
    /// 
    /// A maximized surface typically fills the entire output it is
    /// bound to, except for desktop elements such as panels. This is
    /// the main difference between a maximized shell surface and a
    /// fullscreen shell surface.
    /// 
    /// The details depend on the compositor implementation.
    pub fn setMaximized(self: Self, output: ?ints.wl_output) !void {
        const op = Self.opcode.request.set_maximized;
        try self.global.sendRequest(self.id, op, .{ output, });
    }

    /// Set a short title for the surface.
    /// 
    /// This string may be used to identify the surface in a task bar,
    /// window list, or other user interface elements provided by the
    /// compositor.
    /// 
    /// The string must be encoded in UTF-8.
    pub fn setTitle(self: Self, title: [:0]const u8) !void {
        const op = Self.opcode.request.set_title;
        try self.global.sendRequest(self.id, op, .{ title, });
    }

    /// Set a class for the surface.
    /// 
    /// The surface class identifies the general class of applications
    /// to which the surface belongs. A common convention is to use the
    /// file name (or the full path if it is a non-standard location) of
    /// the application's .desktop file as the class.
    pub fn setClass(self: Self, class_: [:0]const u8) !void {
        const op = Self.opcode.request.set_class;
        try self.global.sendRequest(self.id, op, .{ class_, });
    }

};

/// A surface is a rectangular area that may be displayed on zero
/// or more outputs, and shown any number of times at the compositor's
/// discretion. They can present wl_buffers, receive user input, and
/// define a local coordinate system.
/// 
/// The size of a surface (and relative positions on it) is described
/// in surface-local coordinates, which may differ from the buffer
/// coordinates of the pixel content, in case a buffer_transform
/// or a buffer_scale is used.
/// 
/// A surface without a "role" is fairly useless: a compositor does
/// not know where, when or how to present it. The role is the
/// purpose of a wl_surface. Examples of roles are a cursor for a
/// pointer (as set by wl_pointer.set_cursor), a drag icon
/// (wl_data_device.start_drag), a sub-surface
/// (wl_subcompositor.get_subsurface), and a window as defined by a
/// shell protocol (e.g. wl_shell.get_shell_surface).
/// 
/// A surface can have only one role at a time. Initially a
/// wl_surface does not have a role. Once a wl_surface is given a
/// role, it is set permanently for the whole lifetime of the
/// wl_surface object. Giving the current role again is allowed,
/// unless explicitly forbidden by the relevant interface
/// specification.
/// 
/// Surface roles are given by requests in other interfaces such as
/// wl_pointer.set_cursor. The request should explicitly mention
/// that this request gives a role to a wl_surface. Often, this
/// request also creates a new protocol object that represents the
/// role and adds additional functionality to wl_surface. When a
/// client wants to destroy a wl_surface, they must destroy this role
/// object before the wl_surface, otherwise a defunct_role_object error is
/// sent.
/// 
/// Destroying the role object does not remove the role from the
/// wl_surface, but it may stop the wl_surface from "playing the role".
/// For instance, if a wl_subsurface object is destroyed, the wl_surface
/// it was created for will be unmapped and forget its position and
/// z-order. It is allowed to create a wl_subsurface for the same
/// wl_surface again, but it is not allowed to use the wl_surface as
/// a cursor (cursor is a different role than sub-surface, and role
/// switching is not allowed).
pub const wl_surface = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

    pub const opcode = struct {
        pub const request = struct {
            pub const destroy: u16 = 0;
            pub const attach: u16 = 1;
            pub const damage: u16 = 2;
            pub const frame: u16 = 3;
            pub const set_opaque_region: u16 = 4;
            pub const set_input_region: u16 = 5;
            pub const commit: u16 = 6;
            pub const set_buffer_transform: u16 = 7;
            pub const set_buffer_scale: u16 = 8;
            pub const damage_buffer: u16 = 9;
            pub const offset: u16 = 10;
        };
        pub const event = struct {
            pub const enter: u16 = 0;
            pub const leave: u16 = 1;
            pub const preferred_buffer_scale: u16 = 2;
            pub const preferred_buffer_transform: u16 = 3;
        };
    };

    /// These errors can be emitted in response to wl_surface requests.
    pub const Error = enum(u32) {
        invalid_scale = 0, // buffer scale value is invalid
        invalid_transform = 1, // buffer transform value is invalid
        invalid_size = 2, // buffer size is invalid
        invalid_offset = 3, // buffer offset is invalid
        defunct_role_object = 4, // surface was destroyed before its role object
    };

    /// Deletes the surface and invalidates its object ID.
    pub fn destroy(self: Self) !void {
        const op = Self.opcode.request.destroy;
        try self.global.sendRequest(self.id, op, .{ });
    }

    /// Set a buffer as the content of this surface.
    /// 
    /// The new size of the surface is calculated based on the buffer
    /// size transformed by the inverse buffer_transform and the
    /// inverse buffer_scale. This means that at commit time the supplied
    /// buffer size must be an integer multiple of the buffer_scale. If
    /// that's not the case, an invalid_size error is sent.
    /// 
    /// The x and y arguments specify the location of the new pending
    /// buffer's upper left corner, relative to the current buffer's upper
    /// left corner, in surface-local coordinates. In other words, the
    /// x and y, combined with the new surface size define in which
    /// directions the surface's size changes. Setting anything other than 0
    /// as x and y arguments is discouraged, and should instead be replaced
    /// with using the separate wl_surface.offset request.
    /// 
    /// When the bound wl_surface version is 5 or higher, passing any
    /// non-zero x or y is a protocol violation, and will result in an
    /// 'invalid_offset' error being raised. The x and y arguments are ignored
    /// and do not change the pending state. To achieve equivalent semantics,
    /// use wl_surface.offset.
    /// 
    /// Surface contents are double-buffered state, see wl_surface.commit.
    /// 
    /// The initial surface contents are void; there is no content.
    /// wl_surface.attach assigns the given wl_buffer as the pending
    /// wl_buffer. wl_surface.commit makes the pending wl_buffer the new
    /// surface contents, and the size of the surface becomes the size
    /// calculated from the wl_buffer, as described above. After commit,
    /// there is no pending buffer until the next attach.
    /// 
    /// Committing a pending wl_buffer allows the compositor to read the
    /// pixels in the wl_buffer. The compositor may access the pixels at
    /// any time after the wl_surface.commit request. When the compositor
    /// will not access the pixels anymore, it will send the
    /// wl_buffer.release event. Only after receiving wl_buffer.release,
    /// the client may reuse the wl_buffer. A wl_buffer that has been
    /// attached and then replaced by another attach instead of committed
    /// will not receive a release event, and is not used by the
    /// compositor.
    /// 
    /// If a pending wl_buffer has been committed to more than one wl_surface,
    /// the delivery of wl_buffer.release events becomes undefined. A well
    /// behaved client should not rely on wl_buffer.release events in this
    /// case. Alternatively, a client could create multiple wl_buffer objects
    /// from the same backing storage or use wp_linux_buffer_release.
    /// 
    /// Destroying the wl_buffer after wl_buffer.release does not change
    /// the surface contents. Destroying the wl_buffer before wl_buffer.release
    /// is allowed as long as the underlying buffer storage isn't re-used (this
    /// can happen e.g. on client process termination). However, if the client
    /// destroys the wl_buffer before receiving the wl_buffer.release event and
    /// mutates the underlying buffer storage, the surface contents become
    /// undefined immediately.
    /// 
    /// If wl_surface.attach is sent with a NULL wl_buffer, the
    /// following wl_surface.commit will remove the surface content.
    /// 
    /// If a pending wl_buffer has been destroyed, the result is not specified.
    /// Many compositors are known to remove the surface content on the following
    /// wl_surface.commit, but this behaviour is not universal. Clients seeking to
    /// maximise compatibility should not destroy pending buffers and should
    /// ensure that they explicitly remove content from surfaces, even after
    /// destroying buffers.
    pub fn attach(self: Self, buffer: ?ints.wl_buffer, x: i32, y: i32) !void {
        const op = Self.opcode.request.attach;
        try self.global.sendRequest(self.id, op, .{ buffer, x, y, });
    }

    /// This request is used to describe the regions where the pending
    /// buffer is different from the current surface contents, and where
    /// the surface therefore needs to be repainted. The compositor
    /// ignores the parts of the damage that fall outside of the surface.
    /// 
    /// Damage is double-buffered state, see wl_surface.commit.
    /// 
    /// The damage rectangle is specified in surface-local coordinates,
    /// where x and y specify the upper left corner of the damage rectangle.
    /// 
    /// The initial value for pending damage is empty: no damage.
    /// wl_surface.damage adds pending damage: the new pending damage
    /// is the union of old pending damage and the given rectangle.
    /// 
    /// wl_surface.commit assigns pending damage as the current damage,
    /// and clears pending damage. The server will clear the current
    /// damage as it repaints the surface.
    /// 
    /// Note! New clients should not use this request. Instead damage can be
    /// posted with wl_surface.damage_buffer which uses buffer coordinates
    /// instead of surface coordinates.
    pub fn damage(self: Self, x: i32, y: i32, width: i32, height: i32) !void {
        const op = Self.opcode.request.damage;
        try self.global.sendRequest(self.id, op, .{ x, y, width, height, });
    }

    /// Request a notification when it is a good time to start drawing a new
    /// frame, by creating a frame callback. This is useful for throttling
    /// redrawing operations, and driving animations.
    /// 
    /// When a client is animating on a wl_surface, it can use the 'frame'
    /// request to get notified when it is a good time to draw and commit the
    /// next frame of animation. If the client commits an update earlier than
    /// that, it is likely that some updates will not make it to the display,
    /// and the client is wasting resources by drawing too often.
    /// 
    /// The frame request will take effect on the next wl_surface.commit.
    /// The notification will only be posted for one frame unless
    /// requested again. For a wl_surface, the notifications are posted in
    /// the order the frame requests were committed.
    /// 
    /// The server must send the notifications so that a client
    /// will not send excessive updates, while still allowing
    /// the highest possible update rate for clients that wait for the reply
    /// before drawing again. The server should give some time for the client
    /// to draw and commit after sending the frame callback events to let it
    /// hit the next output refresh.
    /// 
    /// A server should avoid signaling the frame callbacks if the
    /// surface is not visible in any way, e.g. the surface is off-screen,
    /// or completely obscured by other opaque surfaces.
    /// 
    /// The object returned by this request will be destroyed by the
    /// compositor after the callback is fired and as such the client must not
    /// attempt to use it after that point.
    /// 
    /// The callback_data passed in the callback is the current time, in
    /// milliseconds, with an undefined base.
    pub fn frame(self: Self) !ints.wl_callback {
        const new_id = self.global.nextObjectId();
        const new_obj = ints.wl_callback {
            .id = new_id,
            .global = self.global,
        };

        const op = Self.opcode.request.frame;
        try self.global.sendRequest(self.id, op, .{ new_id, });
        return new_obj;
    }

    /// This request sets the region of the surface that contains
    /// opaque content.
    /// 
    /// The opaque region is an optimization hint for the compositor
    /// that lets it optimize the redrawing of content behind opaque
    /// regions.  Setting an opaque region is not required for correct
    /// behaviour, but marking transparent content as opaque will result
    /// in repaint artifacts.
    /// 
    /// The opaque region is specified in surface-local coordinates.
    /// 
    /// The compositor ignores the parts of the opaque region that fall
    /// outside of the surface.
    /// 
    /// Opaque region is double-buffered state, see wl_surface.commit.
    /// 
    /// wl_surface.set_opaque_region changes the pending opaque region.
    /// wl_surface.commit copies the pending region to the current region.
    /// Otherwise, the pending and current regions are never changed.
    /// 
    /// The initial value for an opaque region is empty. Setting the pending
    /// opaque region has copy semantics, and the wl_region object can be
    /// destroyed immediately. A NULL wl_region causes the pending opaque
    /// region to be set to empty.
    pub fn setOpaqueRegion(self: Self, region: ?ints.wl_region) !void {
        const op = Self.opcode.request.set_opaque_region;
        try self.global.sendRequest(self.id, op, .{ region, });
    }

    /// This request sets the region of the surface that can receive
    /// pointer and touch events.
    /// 
    /// Input events happening outside of this region will try the next
    /// surface in the server surface stack. The compositor ignores the
    /// parts of the input region that fall outside of the surface.
    /// 
    /// The input region is specified in surface-local coordinates.
    /// 
    /// Input region is double-buffered state, see wl_surface.commit.
    /// 
    /// wl_surface.set_input_region changes the pending input region.
    /// wl_surface.commit copies the pending region to the current region.
    /// Otherwise the pending and current regions are never changed,
    /// except cursor and icon surfaces are special cases, see
    /// wl_pointer.set_cursor and wl_data_device.start_drag.
    /// 
    /// The initial value for an input region is infinite. That means the
    /// whole surface will accept input. Setting the pending input region
    /// has copy semantics, and the wl_region object can be destroyed
    /// immediately. A NULL wl_region causes the input region to be set
    /// to infinite.
    pub fn setInputRegion(self: Self, region: ?ints.wl_region) !void {
        const op = Self.opcode.request.set_input_region;
        try self.global.sendRequest(self.id, op, .{ region, });
    }

    /// Surface state (input, opaque, and damage regions, attached buffers,
    /// etc.) is double-buffered. Protocol requests modify the pending state,
    /// as opposed to the active state in use by the compositor.
    /// 
    /// A commit request atomically creates a content update from the pending
    /// state, even if the pending state has not been touched. The content
    /// update is placed in a queue until it becomes active. After commit, the
    /// new pending state is as documented for each related request.
    /// 
    /// When the content update is applied, the wl_buffer is applied before all
    /// other state. This means that all coordinates in double-buffered state
    /// are relative to the newly attached wl_buffers, except for
    /// wl_surface.attach itself. If there is no newly attached wl_buffer, the
    /// coordinates are relative to the previous content update.
    /// 
    /// All requests that need a commit to become effective are documented
    /// to affect double-buffered state.
    /// 
    /// Other interfaces may add further double-buffered surface state.
    pub fn commit(self: Self) !void {
        const op = Self.opcode.request.commit;
        try self.global.sendRequest(self.id, op, .{ });
    }

    /// This request sets the transformation that the client has already applied
    /// to the content of the buffer. The accepted values for the transform
    /// parameter are the values for wl_output.transform.
    /// 
    /// The compositor applies the inverse of this transformation whenever it
    /// uses the buffer contents.
    /// 
    /// Buffer transform is double-buffered state, see wl_surface.commit.
    /// 
    /// A newly created surface has its buffer transformation set to normal.
    /// 
    /// wl_surface.set_buffer_transform changes the pending buffer
    /// transformation. wl_surface.commit copies the pending buffer
    /// transformation to the current one. Otherwise, the pending and current
    /// values are never changed.
    /// 
    /// The purpose of this request is to allow clients to render content
    /// according to the output transform, thus permitting the compositor to
    /// use certain optimizations even if the display is rotated. Using
    /// hardware overlays and scanning out a client buffer for fullscreen
    /// surfaces are examples of such optimizations. Those optimizations are
    /// highly dependent on the compositor implementation, so the use of this
    /// request should be considered on a case-by-case basis.
    /// 
    /// Note that if the transform value includes 90 or 270 degree rotation,
    /// the width of the buffer will become the surface height and the height
    /// of the buffer will become the surface width.
    /// 
    /// If transform is not one of the values from the
    /// wl_output.transform enum the invalid_transform protocol error
    /// is raised.
    pub fn setBufferTransform(self: Self, transform: ints.wl_output.Transform) !void {
        const op = Self.opcode.request.set_buffer_transform;
        try self.global.sendRequest(self.id, op, .{ transform, });
    }

    /// This request sets an optional scaling factor on how the compositor
    /// interprets the contents of the buffer attached to the window.
    /// 
    /// Buffer scale is double-buffered state, see wl_surface.commit.
    /// 
    /// A newly created surface has its buffer scale set to 1.
    /// 
    /// wl_surface.set_buffer_scale changes the pending buffer scale.
    /// wl_surface.commit copies the pending buffer scale to the current one.
    /// Otherwise, the pending and current values are never changed.
    /// 
    /// The purpose of this request is to allow clients to supply higher
    /// resolution buffer data for use on high resolution outputs. It is
    /// intended that you pick the same buffer scale as the scale of the
    /// output that the surface is displayed on. This means the compositor
    /// can avoid scaling when rendering the surface on that output.
    /// 
    /// Note that if the scale is larger than 1, then you have to attach
    /// a buffer that is larger (by a factor of scale in each dimension)
    /// than the desired surface size.
    /// 
    /// If scale is not greater than 0 the invalid_scale protocol error is
    /// raised.
    pub fn setBufferScale(self: Self, scale: i32) !void {
        const op = Self.opcode.request.set_buffer_scale;
        try self.global.sendRequest(self.id, op, .{ scale, });
    }

    /// This request is used to describe the regions where the pending
    /// buffer is different from the current surface contents, and where
    /// the surface therefore needs to be repainted. The compositor
    /// ignores the parts of the damage that fall outside of the surface.
    /// 
    /// Damage is double-buffered state, see wl_surface.commit.
    /// 
    /// The damage rectangle is specified in buffer coordinates,
    /// where x and y specify the upper left corner of the damage rectangle.
    /// 
    /// The initial value for pending damage is empty: no damage.
    /// wl_surface.damage_buffer adds pending damage: the new pending
    /// damage is the union of old pending damage and the given rectangle.
    /// 
    /// wl_surface.commit assigns pending damage as the current damage,
    /// and clears pending damage. The server will clear the current
    /// damage as it repaints the surface.
    /// 
    /// This request differs from wl_surface.damage in only one way - it
    /// takes damage in buffer coordinates instead of surface-local
    /// coordinates. While this generally is more intuitive than surface
    /// coordinates, it is especially desirable when using wp_viewport
    /// or when a drawing library (like EGL) is unaware of buffer scale
    /// and buffer transform.
    /// 
    /// Note: Because buffer transformation changes and damage requests may
    /// be interleaved in the protocol stream, it is impossible to determine
    /// the actual mapping between surface and buffer damage until
    /// wl_surface.commit time. Therefore, compositors wishing to take both
    /// kinds of damage into account will have to accumulate damage from the
    /// two requests separately and only transform from one to the other
    /// after receiving the wl_surface.commit.
    pub fn damageBuffer(self: Self, x: i32, y: i32, width: i32, height: i32) !void {
        const op = Self.opcode.request.damage_buffer;
        try self.global.sendRequest(self.id, op, .{ x, y, width, height, });
    }

    /// The x and y arguments specify the location of the new pending
    /// buffer's upper left corner, relative to the current buffer's upper
    /// left corner, in surface-local coordinates. In other words, the
    /// x and y, combined with the new surface size define in which
    /// directions the surface's size changes.
    /// 
    /// Surface location offset is double-buffered state, see
    /// wl_surface.commit.
    /// 
    /// This request is semantically equivalent to and the replaces the x and y
    /// arguments in the wl_surface.attach request in wl_surface versions prior
    /// to 5. See wl_surface.attach for details.
    pub fn offset(self: Self, x: i32, y: i32) !void {
        const op = Self.opcode.request.offset;
        try self.global.sendRequest(self.id, op, .{ x, y, });
    }

};

/// A seat is a group of keyboards, pointer and touch devices. This
/// object is published as a global during start up, or when such a
/// device is hot plugged.  A seat typically has a pointer and
/// maintains a keyboard focus and a pointer focus.
pub const wl_seat = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

    pub const opcode = struct {
        pub const request = struct {
            pub const get_pointer: u16 = 0;
            pub const get_keyboard: u16 = 1;
            pub const get_touch: u16 = 2;
            pub const release: u16 = 3;
        };
        pub const event = struct {
            pub const capabilities: u16 = 0;
            pub const name: u16 = 1;
        };
    };

    /// This is a bitmask of capabilities this seat has; if a member is
    /// set, then it is present on the seat.
    pub const Capability = enum(u32) {
        pointer = 1, // the seat has pointer devices
        keyboard = 2, // the seat has one or more keyboards
        touch = 4, // the seat has touch devices
    };

    /// These errors can be emitted in response to wl_seat requests.
    pub const Error = enum(u32) {
        missing_capability = 0, // get_pointer, get_keyboard or get_touch called on seat without the matching capability
    };

    /// The ID provided will be initialized to the wl_pointer interface
    /// for this seat.
    /// 
    /// This request only takes effect if the seat has the pointer
    /// capability, or has had the pointer capability in the past.
    /// It is a protocol violation to issue this request on a seat that has
    /// never had the pointer capability. The missing_capability error will
    /// be sent in this case.
    pub fn getPointer(self: Self) !ints.wl_pointer {
        const new_id = self.global.nextObjectId();
        const new_obj = ints.wl_pointer {
            .id = new_id,
            .global = self.global,
        };

        const op = Self.opcode.request.get_pointer;
        try self.global.sendRequest(self.id, op, .{ new_id, });
        return new_obj;
    }

    /// The ID provided will be initialized to the wl_keyboard interface
    /// for this seat.
    /// 
    /// This request only takes effect if the seat has the keyboard
    /// capability, or has had the keyboard capability in the past.
    /// It is a protocol violation to issue this request on a seat that has
    /// never had the keyboard capability. The missing_capability error will
    /// be sent in this case.
    pub fn getKeyboard(self: Self) !ints.wl_keyboard {
        const new_id = self.global.nextObjectId();
        const new_obj = ints.wl_keyboard {
            .id = new_id,
            .global = self.global,
        };

        const op = Self.opcode.request.get_keyboard;
        try self.global.sendRequest(self.id, op, .{ new_id, });
        return new_obj;
    }

    /// The ID provided will be initialized to the wl_touch interface
    /// for this seat.
    /// 
    /// This request only takes effect if the seat has the touch
    /// capability, or has had the touch capability in the past.
    /// It is a protocol violation to issue this request on a seat that has
    /// never had the touch capability. The missing_capability error will
    /// be sent in this case.
    pub fn getTouch(self: Self) !ints.wl_touch {
        const new_id = self.global.nextObjectId();
        const new_obj = ints.wl_touch {
            .id = new_id,
            .global = self.global,
        };

        const op = Self.opcode.request.get_touch;
        try self.global.sendRequest(self.id, op, .{ new_id, });
        return new_obj;
    }

    /// Using this request a client can tell the server that it is not going to
    /// use the seat object anymore.
    pub fn release(self: Self) !void {
        const op = Self.opcode.request.release;
        try self.global.sendRequest(self.id, op, .{ });
    }

};

/// The wl_pointer interface represents one or more input devices,
/// such as mice, which control the pointer location and pointer_focus
/// of a seat.
/// 
/// The wl_pointer interface generates motion, enter and leave
/// events for the surfaces that the pointer is located over,
/// and button and axis events for button presses, button releases
/// and scrolling.
pub const wl_pointer = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

    pub const opcode = struct {
        pub const request = struct {
            pub const set_cursor: u16 = 0;
            pub const release: u16 = 1;
        };
        pub const event = struct {
            pub const enter: u16 = 0;
            pub const leave: u16 = 1;
            pub const motion: u16 = 2;
            pub const button: u16 = 3;
            pub const axis: u16 = 4;
            pub const frame: u16 = 5;
            pub const axis_source: u16 = 6;
            pub const axis_stop: u16 = 7;
            pub const axis_discrete: u16 = 8;
            pub const axis_value120: u16 = 9;
            pub const axis_relative_direction: u16 = 10;
        };
    };

    pub const Error = enum(u32) {
        role = 0, // given wl_surface has another role
    };

    /// Describes the physical state of a button that produced the button
    /// event.
    pub const ButtonState = enum(u32) {
        released = 0, // the button is not pressed
        pressed = 1, // the button is pressed
    };

    /// Describes the axis types of scroll events.
    pub const Axis = enum(u32) {
        vertical_scroll = 0, // vertical axis
        horizontal_scroll = 1, // horizontal axis
    };

    /// Describes the source types for axis events. This indicates to the
    /// client how an axis event was physically generated; a client may
    /// adjust the user interface accordingly. For example, scroll events
    /// from a "finger" source may be in a smooth coordinate space with
    /// kinetic scrolling whereas a "wheel" source may be in discrete steps
    /// of a number of lines.
    /// 
    /// The "continuous" axis source is a device generating events in a
    /// continuous coordinate space, but using something other than a
    /// finger. One example for this source is button-based scrolling where
    /// the vertical motion of a device is converted to scroll events while
    /// a button is held down.
    /// 
    /// The "wheel tilt" axis source indicates that the actual device is a
    /// wheel but the scroll event is not caused by a rotation but a
    /// (usually sideways) tilt of the wheel.
    pub const AxisSource = enum(u32) {
        wheel = 0, // a physical wheel rotation
        finger = 1, // finger on a touch surface
        continuous = 2, // continuous coordinate space
        wheel_tilt = 3, // a physical wheel tilt
    };

    /// This specifies the direction of the physical motion that caused a
    /// wl_pointer.axis event, relative to the wl_pointer.axis direction.
    pub const AxisRelativeDirection = enum(u32) {
        identical = 0, // physical motion matches axis direction
        inverted = 1, // physical motion is the inverse of the axis direction
    };

    /// Set the pointer surface, i.e., the surface that contains the
    /// pointer image (cursor). This request gives the surface the role
    /// of a cursor. If the surface already has another role, it raises
    /// a protocol error.
    /// 
    /// The cursor actually changes only if the pointer
    /// focus for this device is one of the requesting client's surfaces
    /// or the surface parameter is the current pointer surface. If
    /// there was a previous surface set with this request it is
    /// replaced. If surface is NULL, the pointer image is hidden.
    /// 
    /// The parameters hotspot_x and hotspot_y define the position of
    /// the pointer surface relative to the pointer location. Its
    /// top-left corner is always at (x, y) - (hotspot_x, hotspot_y),
    /// where (x, y) are the coordinates of the pointer location, in
    /// surface-local coordinates.
    /// 
    /// On wl_surface.offset requests to the pointer surface, hotspot_x
    /// and hotspot_y are decremented by the x and y parameters
    /// passed to the request. The offset must be applied by
    /// wl_surface.commit as usual.
    /// 
    /// The hotspot can also be updated by passing the currently set
    /// pointer surface to this request with new values for hotspot_x
    /// and hotspot_y.
    /// 
    /// The input region is ignored for wl_surfaces with the role of
    /// a cursor. When the use as a cursor ends, the wl_surface is
    /// unmapped.
    /// 
    /// The serial parameter must match the latest wl_pointer.enter
    /// serial number sent to the client. Otherwise the request will be
    /// ignored.
    pub fn setCursor(self: Self, serial: u32, surface: ?ints.wl_surface, hotspot_x: i32, hotspot_y: i32) !void {
        const op = Self.opcode.request.set_cursor;
        try self.global.sendRequest(self.id, op, .{ serial, surface, hotspot_x, hotspot_y, });
    }

    /// Using this request a client can tell the server that it is not going to
    /// use the pointer object anymore.
    /// 
    /// This request destroys the pointer proxy object, so clients must not call
    /// wl_pointer_destroy() after using this request.
    pub fn release(self: Self) !void {
        const op = Self.opcode.request.release;
        try self.global.sendRequest(self.id, op, .{ });
    }

};

/// The wl_keyboard interface represents one or more keyboards
/// associated with a seat.
/// 
/// Each wl_keyboard has the following logical state:
/// 
/// - an active surface (possibly null),
/// - the keys currently logically down,
/// - the active modifiers,
/// - the active group.
/// 
/// By default, the active surface is null, the keys currently logically down
/// are empty, the active modifiers and the active group are 0.
pub const wl_keyboard = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

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
            pub const repeat_info: u16 = 5;
        };
    };

    /// This specifies the format of the keymap provided to the
    /// client with the wl_keyboard.keymap event.
    pub const KeymapFormat = enum(u32) {
        no_keymap = 0, // no keymap; client must understand how to interpret the raw keycode
        xkb_v1 = 1, // libxkbcommon compatible, null-terminated string; to determine the xkb keycode, clients must add 8 to the key event keycode
    };

    /// Describes the physical state of a key that produced the key event.
    pub const KeyState = enum(u32) {
        released = 0, // key is not pressed
        pressed = 1, // key is pressed
    };

    pub fn release(self: Self) !void {
        const op = Self.opcode.request.release;
        try self.global.sendRequest(self.id, op, .{ });
    }

};

/// The wl_touch interface represents a touchscreen
/// associated with a seat.
/// 
/// Touch interactions can consist of one or more contacts.
/// For each contact, a series of events is generated, starting
/// with a down event, followed by zero or more motion events,
/// and ending with an up event. Events relating to the same
/// contact point can be identified by the ID of the sequence.
pub const wl_touch = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

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

    pub fn release(self: Self) !void {
        const op = Self.opcode.request.release;
        try self.global.sendRequest(self.id, op, .{ });
    }

};

/// An output describes part of the compositor geometry.  The
/// compositor works in the 'compositor coordinate system' and an
/// output corresponds to a rectangular area in that space that is
/// actually visible.  This typically corresponds to a monitor that
/// displays part of the compositor space.  This object is published
/// as global during start up, or when a monitor is hotplugged.
pub const wl_output = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

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

    /// This enumeration describes how the physical
    /// pixels on an output are laid out.
    pub const Subpixel = enum(u32) {
        unknown = 0, // unknown geometry
        none = 1, // no geometry
        horizontal_rgb = 2, // horizontal RGB
        horizontal_bgr = 3, // horizontal BGR
        vertical_rgb = 4, // vertical RGB
        vertical_bgr = 5, // vertical BGR
    };

    /// This describes transformations that clients and compositors apply to
    /// buffer contents.
    /// 
    /// The flipped values correspond to an initial flip around a
    /// vertical axis followed by rotation.
    /// 
    /// The purpose is mainly to allow clients to render accordingly and
    /// tell the compositor, so that for fullscreen surfaces, the
    /// compositor will still be able to scan out directly from client
    /// surfaces.
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

    /// These flags describe properties of an output mode.
    /// They are used in the flags bitfield of the mode event.
    pub const Mode = enum(u32) {
        current = 1, // indicates this is the current mode
        preferred = 2, // indicates this is the preferred mode
    };

    /// Using this request a client can tell the server that it is not going to
    /// use the output object anymore.
    pub fn release(self: Self) !void {
        const op = Self.opcode.request.release;
        try self.global.sendRequest(self.id, op, .{ });
    }

};

/// A region object describes an area.
/// 
/// Region objects are used to describe the opaque and input
/// regions of a surface.
pub const wl_region = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

    pub const opcode = struct {
        pub const request = struct {
            pub const destroy: u16 = 0;
            pub const add: u16 = 1;
            pub const subtract: u16 = 2;
        };
    };

    /// Destroy the region.  This will invalidate the object ID.
    pub fn destroy(self: Self) !void {
        const op = Self.opcode.request.destroy;
        try self.global.sendRequest(self.id, op, .{ });
    }

    /// Add the specified rectangle to the region.
    pub fn add(self: Self, x: i32, y: i32, width: i32, height: i32) !void {
        const op = Self.opcode.request.add;
        try self.global.sendRequest(self.id, op, .{ x, y, width, height, });
    }

    /// Subtract the specified rectangle from the region.
    pub fn subtract(self: Self, x: i32, y: i32, width: i32, height: i32) !void {
        const op = Self.opcode.request.subtract;
        try self.global.sendRequest(self.id, op, .{ x, y, width, height, });
    }

};

/// The global interface exposing sub-surface compositing capabilities.
/// A wl_surface, that has sub-surfaces associated, is called the
/// parent surface. Sub-surfaces can be arbitrarily nested and create
/// a tree of sub-surfaces.
/// 
/// The root surface in a tree of sub-surfaces is the main
/// surface. The main surface cannot be a sub-surface, because
/// sub-surfaces must always have a parent.
/// 
/// A main surface with its sub-surfaces forms a (compound) window.
/// For window management purposes, this set of wl_surface objects is
/// to be considered as a single window, and it should also behave as
/// such.
/// 
/// The aim of sub-surfaces is to offload some of the compositing work
/// within a window from clients to the compositor. A prime example is
/// a video player with decorations and video in separate wl_surface
/// objects. This should allow the compositor to pass YUV video buffer
/// processing to dedicated overlay hardware when possible.
pub const wl_subcompositor = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

    pub const opcode = struct {
        pub const request = struct {
            pub const destroy: u16 = 0;
            pub const get_subsurface: u16 = 1;
        };
    };

    pub const Error = enum(u32) {
        bad_surface = 0, // the to-be sub-surface is invalid
        bad_parent = 1, // the to-be sub-surface parent is invalid
    };

    /// Informs the server that the client will not be using this
    /// protocol object anymore. This does not affect any other
    /// objects, wl_subsurface objects included.
    pub fn destroy(self: Self) !void {
        const op = Self.opcode.request.destroy;
        try self.global.sendRequest(self.id, op, .{ });
    }

    /// Create a sub-surface interface for the given surface, and
    /// associate it with the given parent surface. This turns a
    /// plain wl_surface into a sub-surface.
    /// 
    /// The to-be sub-surface must not already have another role, and it
    /// must not have an existing wl_subsurface object. Otherwise the
    /// bad_surface protocol error is raised.
    /// 
    /// Adding sub-surfaces to a parent is a double-buffered operation on the
    /// parent (see wl_surface.commit). The effect of adding a sub-surface
    /// becomes visible on the next time the state of the parent surface is
    /// applied.
    /// 
    /// The parent surface must not be one of the child surface's descendants,
    /// and the parent must be different from the child surface, otherwise the
    /// bad_parent protocol error is raised.
    /// 
    /// This request modifies the behaviour of wl_surface.commit request on
    /// the sub-surface, see the documentation on wl_subsurface interface.
    pub fn getSubsurface(self: Self, surface: ints.wl_surface, parent: ints.wl_surface) !ints.wl_subsurface {
        const new_id = self.global.nextObjectId();
        const new_obj = ints.wl_subsurface {
            .id = new_id,
            .global = self.global,
        };

        const op = Self.opcode.request.get_subsurface;
        try self.global.sendRequest(self.id, op, .{ new_id, surface, parent, });
        return new_obj;
    }

};

/// An additional interface to a wl_surface object, which has been
/// made a sub-surface. A sub-surface has one parent surface. A
/// sub-surface's size and position are not limited to that of the parent.
/// Particularly, a sub-surface is not automatically clipped to its
/// parent's area.
/// 
/// A sub-surface becomes mapped, when a non-NULL wl_buffer is applied
/// and the parent surface is mapped. The order of which one happens
/// first is irrelevant. A sub-surface is hidden if the parent becomes
/// hidden, or if a NULL wl_buffer is applied. These rules apply
/// recursively through the tree of surfaces.
/// 
/// The behaviour of a wl_surface.commit request on a sub-surface
/// depends on the sub-surface's mode. The possible modes are
/// synchronized and desynchronized, see methods
/// wl_subsurface.set_sync and wl_subsurface.set_desync. Synchronized
/// mode caches the wl_surface state to be applied when the parent's
/// state gets applied, and desynchronized mode applies the pending
/// wl_surface state directly. A sub-surface is initially in the
/// synchronized mode.
/// 
/// Sub-surfaces also have another kind of state, which is managed by
/// wl_subsurface requests, as opposed to wl_surface requests. This
/// state includes the sub-surface position relative to the parent
/// surface (wl_subsurface.set_position), and the stacking order of
/// the parent and its sub-surfaces (wl_subsurface.place_above and
/// .place_below). This state is applied when the parent surface's
/// wl_surface state is applied, regardless of the sub-surface's mode.
/// As the exception, set_sync and set_desync are effective immediately.
/// 
/// The main surface can be thought to be always in desynchronized mode,
/// since it does not have a parent in the sub-surfaces sense.
/// 
/// Even if a sub-surface is in desynchronized mode, it will behave as
/// in synchronized mode, if its parent surface behaves as in
/// synchronized mode. This rule is applied recursively throughout the
/// tree of surfaces. This means, that one can set a sub-surface into
/// synchronized mode, and then assume that all its child and grand-child
/// sub-surfaces are synchronized, too, without explicitly setting them.
/// 
/// Destroying a sub-surface takes effect immediately. If you need to
/// synchronize the removal of a sub-surface to the parent surface update,
/// unmap the sub-surface first by attaching a NULL wl_buffer, update parent,
/// and then destroy the sub-surface.
/// 
/// If the parent wl_surface object is destroyed, the sub-surface is
/// unmapped.
/// 
/// A sub-surface never has the keyboard focus of any seat.
/// 
/// The wl_surface.offset request is ignored: clients must use set_position
/// instead to move the sub-surface.
pub const wl_subsurface = struct {
    id: u32,
    global: *WaylandState,

    const Self = @This();

    pub const opcode = struct {
        pub const request = struct {
            pub const destroy: u16 = 0;
            pub const set_position: u16 = 1;
            pub const place_above: u16 = 2;
            pub const place_below: u16 = 3;
            pub const set_sync: u16 = 4;
            pub const set_desync: u16 = 5;
        };
    };

    pub const Error = enum(u32) {
        bad_surface = 0, // wl_surface is not a sibling or the parent
    };

    /// The sub-surface interface is removed from the wl_surface object
    /// that was turned into a sub-surface with a
    /// wl_subcompositor.get_subsurface request. The wl_surface's association
    /// to the parent is deleted. The wl_surface is unmapped immediately.
    pub fn destroy(self: Self) !void {
        const op = Self.opcode.request.destroy;
        try self.global.sendRequest(self.id, op, .{ });
    }

    /// This schedules a sub-surface position change.
    /// The sub-surface will be moved so that its origin (top left
    /// corner pixel) will be at the location x, y of the parent surface
    /// coordinate system. The coordinates are not restricted to the parent
    /// surface area. Negative values are allowed.
    /// 
    /// The scheduled coordinates will take effect whenever the state of the
    /// parent surface is applied.
    /// 
    /// If more than one set_position request is invoked by the client before
    /// the commit of the parent surface, the position of a new request always
    /// replaces the scheduled position from any previous request.
    /// 
    /// The initial position is 0, 0.
    pub fn setPosition(self: Self, x: i32, y: i32) !void {
        const op = Self.opcode.request.set_position;
        try self.global.sendRequest(self.id, op, .{ x, y, });
    }

    /// This sub-surface is taken from the stack, and put back just
    /// above the reference surface, changing the z-order of the sub-surfaces.
    /// The reference surface must be one of the sibling surfaces, or the
    /// parent surface. Using any other surface, including this sub-surface,
    /// will cause a protocol error.
    /// 
    /// The z-order is double-buffered. Requests are handled in order and
    /// applied immediately to a pending state. The final pending state is
    /// copied to the active state the next time the state of the parent
    /// surface is applied.
    /// 
    /// A new sub-surface is initially added as the top-most in the stack
    /// of its siblings and parent.
    pub fn placeAbove(self: Self, sibling: ints.wl_surface) !void {
        const op = Self.opcode.request.place_above;
        try self.global.sendRequest(self.id, op, .{ sibling, });
    }

    /// The sub-surface is placed just below the reference surface.
    /// See wl_subsurface.place_above.
    pub fn placeBelow(self: Self, sibling: ints.wl_surface) !void {
        const op = Self.opcode.request.place_below;
        try self.global.sendRequest(self.id, op, .{ sibling, });
    }

    /// Change the commit behaviour of the sub-surface to synchronized
    /// mode, also described as the parent dependent mode.
    /// 
    /// In synchronized mode, wl_surface.commit on a sub-surface will
    /// accumulate the committed state in a cache, but the state will
    /// not be applied and hence will not change the compositor output.
    /// The cached state is applied to the sub-surface immediately after
    /// the parent surface's state is applied. This ensures atomic
    /// updates of the parent and all its synchronized sub-surfaces.
    /// Applying the cached state will invalidate the cache, so further
    /// parent surface commits do not (re-)apply old state.
    /// 
    /// See wl_subsurface for the recursive effect of this mode.
    pub fn setSync(self: Self) !void {
        const op = Self.opcode.request.set_sync;
        try self.global.sendRequest(self.id, op, .{ });
    }

    /// Change the commit behaviour of the sub-surface to desynchronized
    /// mode, also described as independent or freely running mode.
    /// 
    /// In desynchronized mode, wl_surface.commit on a sub-surface will
    /// apply the pending state directly, without caching, as happens
    /// normally with a wl_surface. Calling wl_surface.commit on the
    /// parent surface has no effect on the sub-surface's wl_surface
    /// state. This mode allows a sub-surface to be updated on its own.
    /// 
    /// If cached state exists when wl_surface.commit is called in
    /// desynchronized mode, the pending state is added to the cached
    /// state, and applied as a whole. This invalidates the cache.
    /// 
    /// Note: even if a sub-surface is set to desynchronized, a parent
    /// sub-surface may override it to behave as synchronized. For details,
    /// see wl_subsurface.
    /// 
    /// If a surface's parent surface behaves as desynchronized, then
    /// the cached state is applied on set_desync.
    pub fn setDesync(self: Self) !void {
        const op = Self.opcode.request.set_desync;
        try self.global.sendRequest(self.id, op, .{ });
    }

};

