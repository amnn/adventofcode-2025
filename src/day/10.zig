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

        const free = try m.gaussianElimination(a);
        defer a.free(free);

        std.debug.print("{f}\nFree: {any}\n\n", .{ m, free });

        const Bound = struct { lo: i64, hi: i64 };
        const bounds = try a.alloc(Bound, m.width() - 1);
        defer a.free(bounds);

        for (bounds) |*b| b.* = .{ .lo = 0, .hi = math.maxInt(i64) };

        // Successively tighten each variable's bounds, relative to the current
        // bounds for other variables, until they all converge on a fixed point.
        var tighter = true;
        while (tighter) {
            tighter = false;
            const b = m.width() - 1;
            for (0..b) |v| {
                for (0..m.height()) |r| {
                    const denom = m.get(v, r).?;
                    if (denom == 0) continue;

                    // Substitute existing bounds into the equation for row r
                    // rearranged for variable v:
                    //
                    //   x[v] = (b[r] - Σ {i != v} m[i, r] * x[i]) / m[v, r]
                    //
                    // to find new bounds for x[v].
                    var lo = m.get(b, r).?;
                    var hi = m.get(b, r).?;
                    for (0..b) |i| {
                        if (i == r) continue;
                        const coeff = m.get(i, r).?;
                        if (coeff == 0) continue;

                        if ((coeff < 0) != (denom < 0)) {
                            lo = satAdd(lo, -coeff *| bounds[i].lo);
                            hi = satAdd(hi, -coeff *| bounds[i].hi);
                        } else {
                            lo = satAdd(lo, -coeff *| bounds[i].hi);
                            hi = satAdd(hi, -coeff *| bounds[i].lo);
                        }
                    }

                    lo = math.clamp(try satDivFloor(lo, denom), bounds[v].lo, bounds[v].hi);
                    hi = math.clamp(try satDivCeil(hi, denom), bounds[v].lo, bounds[v].hi);

                    tighter |= bounds[v].lo < lo;
                    tighter |= hi < bounds[v].hi;

                    bounds[v].lo = lo;
                    bounds[v].hi = hi;
                }
            }
        }

        std.debug.print("Bounds:\n", .{});
        for (bounds, 0..) |b, i| {
            std.debug.print("  {} <= v{} <= {}\n", .{ b.lo, i, b.hi });
        }
        std.debug.print("\n", .{});

        const presses = try a.alloc(u64, m.width() - 1);
        defer a.free(presses);
        for (presses) |*p| p.* = 0;

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

/// Saturated addition -- like `+|`, but treats `math.maxInt(i64)` and
/// `math.minInt(i64)` as infinities. Biases towards positive infinity (e.g.
/// inf + -inf = inf).
fn satAdd(x: i64, y: i64) i64 {
    const MAX = math.maxInt(i64);
    const MIN = math.minInt(i64);

    if (x == MAX or y == MAX) return MAX;
    if (x == MIN or y == MIN) return MIN;

    return x +| y;
}

/// Saturated floored division -- like `math.divFloor`, but treats
/// `math.maxInt(i64)` and `math.minInt(i64)` as infinities.
fn satDivFloor(numer: i64, denom: i64) !i64 {
    const MAX = math.maxInt(i64);
    const MIN = math.minInt(i64);

    if (numer == MAX and denom > 0) return MAX;
    if (numer == MIN and denom < 0) return MAX;
    if (numer == MAX and denom < 0) return MIN;
    if (numer == MIN and denom > 0) return MIN;
    return math.divFloor(i64, numer, denom);
}

/// Saturated ceilinged division -- like `math.divCeil`, but treats
/// `math.maxInt(i64)` and `math.minInt(i64)` as infinities.
fn satDivCeil(numer: i64, denom: i64) !i64 {
    const MAX = math.maxInt(i64);
    const MIN = math.minInt(i64);

    if (numer == MAX and denom > 0) return MAX;
    if (numer == MIN and denom < 0) return MIN;
    if (numer == MAX and denom < 0) return MIN;
    if (numer == MIN and denom > 0) return MAX;
    return math.divCeil(i64, numer, denom);
}
