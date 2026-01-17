const std = @import("std");
const lib = @import("libadvent");

const math = std.math;
const scan = lib.scan;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const File = std.fs.File;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const Matrix = lib.Matrix;
const Reader = std.io.Reader;

const Machine = struct {
    lights: u16,
    buttons: []u16,
    joltage: []u64,

    fn parse(r: *Reader, alloc: Allocator) !Machine {
        var lights: u16 = 0;

        var buttons: ArrayList(u16) = .{};
        defer buttons.deinit(alloc);

        var joltage: ArrayList(u64) = .{};
        defer joltage.deinit(alloc);

        try scan.prefix(r, "[");
        var i: u16 = 1;
        while (true) : (i <<= 1) {
            switch (try scan.@"enum"(enum { @".", @"#", @"]" }, r)) {
                .@"." => {},
                .@"#" => lights |= i,
                .@"]" => break,
            }
        }

        scan.spaces(r);
        while (try parseButton(r)) |b| {
            try buttons.append(alloc, b);
            scan.spaces(r);
        }

        scan.spaces(r);
        try scan.prefix(r, "{");
        while (true) {
            const j = try scan.unsigned(u64, r);
            try joltage.append(alloc, j);
            scan.prefix(r, ",") catch break;
        }
        try scan.prefix(r, "}");

        const buttons_ = try buttons.toOwnedSlice(alloc);
        errdefer alloc.free(buttons_);

        const joltage_ = try joltage.toOwnedSlice(alloc);
        errdefer alloc.free(joltage_);

        return .{ .lights = lights, .buttons = buttons_, .joltage = joltage_ };
    }

    fn deinit(self: *Machine, alloc: Allocator) void {
        alloc.free(self.buttons);
        alloc.free(self.joltage);
    }

    fn parseButton(r: *Reader) !?u16 {
        var button: u16 = 0;
        scan.prefix(r, "(") catch return null;

        while (true) {
            button |= @as(u16, 1) << try scan.unsigned(u4, r);
            scan.prefix(r, ",") catch break;
        }

        try scan.prefix(r, ")");
        return button;
    }

    fn minPressesForLight(self: Machine) u64 {
        var min: u64 = math.maxInt(u64);
        const buttons: u6 = @intCast(self.buttons.len);
        for (0..@as(usize, 1) << buttons) |combo| {
            if (@popCount(combo) >= min) {
                continue;
            }

            var state: u16 = 0;
            for (self.buttons, 0..) |b, i| {
                const bit = @as(usize, 1) << @intCast(i);
                if ((combo & bit) != 0) {
                    state ^= b;
                }
            }

            if (state == self.lights) {
                min = @popCount(combo);
            }
        }

        return min;
    }

    fn minPressesForJoltage(self: Machine, a: Allocator) !u64 {
        var m: Matrix = try .zero(a, self.buttons.len + 1, self.joltage.len);
        defer m.deinit(a);

        for (self.buttons, 0..) |button, i| {
            for (0..m.height()) |j| {
                const b = button & @as(usize, 1) << @intCast(j);
                m.ptr(i, j).?.* = if (b > 0) 1 else 0;
            }
        }

        for (self.joltage, 0..) |jolt, j| {
            m.ptr(self.buttons.len, j).?.* = @intCast(jolt);
        }

        std.debug.print("Before:\n{f}\n", .{m});
        const free = try m.gaussianElimination(a);
        std.debug.print("{f}\nFree: {any}\n\n", .{ m, free });
        return 0;
    }
};

pub fn main() !void {
    var input: [4096]u8 = undefined;
    var reader = File.stdin().reader(&input);
    const stdin = &reader.interface;

    var buf: [4 * 1024 * 1024]u8 = undefined;
    var fba: FixedBufferAllocator = .init(&buf);
    const alloc = fba.allocator();

    var part1: u64 = 0;
    var part2: u64 = 0;
    while (true) {
        var m = Machine.parse(stdin, alloc) catch break;
        defer m.deinit(alloc);

        part1 += m.minPressesForLight();
        part2 += try m.minPressesForJoltage(alloc);

        scan.prefix(stdin, "\n") catch break;
    }

    std.debug.print("Part 1: {d}\n", .{part1});
    std.debug.print("Part 2: {d}\n", .{part2});
}
