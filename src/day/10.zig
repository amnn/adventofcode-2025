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

        const bounds = try a.alloc(Bound, m.width() - 1);
        defer a.free(bounds);
        for (bounds) |*b| b.* = .{};

        // Discover bounds for each variable by tightening them until a fixed
        // point is reached. Do this before performing gaussian elimination
        // because at this stage, we know that all coefficients are positive
        // (after gaussian elimination if every row contains a mix of positive
        // and negative coefficients, we will not be able to make a first step
        // towards tightening bounds).
        while (try Bound.tighten(bounds, m)) {}

        const free = try m.gaussianElimination(a);
        defer a.free(free);

        // Tighten bounds again after gaussian elimination, as it could have
        // surfaced some more constraints.
        while (try Bound.tighten(bounds, m)) {}

        // Now, enumerate all possible assignments of free variables within their
        // bounds, and solve the remaining variables accordingly.
        const presses = try a.alloc(i64, free.len);
        defer a.free(presses);

        const Enumeration = struct {
            free: []usize,
            presses: []i64,
            bounds: []const Bound,
            system: Matrix,
            min: i64 = math.maxInt(i64),

            const Self = @This();

            fn enumerate(self_: *Self, i: usize) void {
                if (i >= self_.free.len) {
                    self_.min = @min(self_.min, self_.solve());
                    return;
                }

                const v = self_.free[i];
                const b = self_.bounds[v];
                var p = b.lo;
                while (p <= b.hi) : (p += 1) {
                    self_.presses[i] = p;
                    self_.enumerate(i + 1);
                }
            }

            fn solve(self_: *const Self) i64 {
                const b = self_.system.width() - 1;
                const lim = @min(b, self_.system.height());

                var total: i64 = 0;
                for (self_.presses) |p| total += p;

                for (0..lim) |v| {
                    const denom = self_.system.get(v, v).?;

                    var soln = self_.system.get(b, v).?;
                    for (self_.free, self_.presses) |f, p| {
                        const coeff = self_.system.get(f, v).?;
                        soln -= coeff * p;
                    }

                    // If the denominator is zero, this row consistents only of
                    // free variables, so the difference after substituting all
                    // free variables should be zero.
                    if (denom == 0) if (soln != 0) {
                        return math.maxInt(i64);
                    } else {
                        continue;
                    };

                    // If the solution is not integral, then this is not a
                    // valid solution.
                    soln = math.divExact(i64, soln, denom) catch {
                        return math.maxInt(i64);
                    };

                    // If the current assignment of free variables results in a
                    // negative number of button presses for any other
                    // variable, then we know this solution is not valid.
                    if (soln < 0) {
                        return math.maxInt(i64);
                    }

                    total += soln;
                }

                return total;
            }
        };

        var enum_: Enumeration = .{
            .free = free,
            .presses = presses,
            .bounds = bounds,
            .system = m,
        };

        enum_.enumerate(0);
        return @intCast(enum_.min);
    }
};

const Bound = struct {
    lo: i64 = 0,
    hi: i64 = math.maxInt(i64),

    const Self = @This();

    fn tighten(bounds: []Bound, m: Matrix) !bool {
        var tighter = false;

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
                    if (i == v) continue;
                    const coeff = -m.get(i, r).?;
                    if (coeff == 0) continue;

                    if (coeff > 0) {
                        lo = satAdd(lo, coeff *| bounds[i].lo);
                        hi = satAdd(hi, coeff *| bounds[i].hi);
                    } else {
                        lo = satAdd(lo, coeff *| bounds[i].hi);
                        hi = satAdd(hi, coeff *| bounds[i].lo);
                    }
                }

                if (denom < 0) {
                    std.mem.swap(i64, &lo, &hi);
                }

                lo = math.clamp(try satDivFloor(lo, denom), bounds[v].lo, bounds[v].hi);
                hi = math.clamp(try satDivCeil(hi, denom), bounds[v].lo, bounds[v].hi);

                tighter |= bounds[v].lo < lo;
                tighter |= hi < bounds[v].hi;

                bounds[v].lo = lo;
                bounds[v].hi = hi;
            }
        }

        return tighter;
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

/// Saturated addition -- like `+|`, but treats values greater than or equal to
/// `math.maxInt(i64)` as positive infinity, and values less than or equal to
/// `math.minInt(i64) + 1` as negative infinity.
///
/// Biases towards positive infinity (e.g. inf + -inf = inf).
fn satAdd(x: i64, y: i64) i64 {
    const MIN = math.minInt(i64) + 1;
    const MAX = math.maxInt(i64);

    if (x >= MAX or y >= MAX) return MAX;
    if (x <= MIN or y <= MIN) return MIN;

    return x +| y;
}

/// Saturated floored division -- like `math.divFloor`, but treats values
/// greater than or equal to `math.maxInt(i64)` as positive infinity and values
/// less than or equal to `math.minInt(i64) + 1` as negative infinity.
fn satDivFloor(numer: i64, denom: i64) !i64 {
    const MIN = math.minInt(i64) + 1;
    const MAX = math.maxInt(i64);

    if (numer >= MAX and denom > 0) return MAX;
    if (numer <= MIN and denom < 0) return MAX;
    if (numer >= MAX and denom < 0) return MIN;
    if (numer <= MIN and denom > 0) return MIN;
    return math.divFloor(i64, numer, denom);
}

/// Saturated ceiled division -- like `math.divCeil`, but treats values
/// greater than or equal to `math.maxInt(i64)` as positive infinity and values
/// less than or equal to `math.minInt(i64) + 1` as negative infinity.
fn satDivCeil(numer: i64, denom: i64) !i64 {
    const MIN = math.minInt(i64) + 1;
    const MAX = math.maxInt(i64);

    if (numer >= MAX and denom > 0) return MAX;
    if (numer <= MIN and denom < 0) return MAX;
    if (numer >= MAX and denom < 0) return MIN;
    if (numer <= MIN and denom > 0) return MIN;
    return math.divCeil(i64, numer, denom);
}
