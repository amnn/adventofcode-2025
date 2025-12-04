const std = @import("std");
const lib = @import("libadvent");

const heap = std.heap;
const math = std.math;
const scan = lib.scan;

const Allocator = std.mem.Allocator;
const File = std.fs.File;
const PriorityQueue = std.PriorityQueue;
const Reader = std.io.Reader;

const IDs = struct {
    lo: u64,
    hi: u64,
    pat: u64,

    const empty: IDs = .{ .lo = 0, .hi = 0, .pat = 0 };

    fn init(lo: u64, hi: u64, pat: u64) IDs {
        return .{ .lo = lo, .hi = hi, .pat = pat };
    }

    fn next(self: *IDs) ?u64 {
        if (self.lo >= self.hi) {
            return null;
        }

        const val = self.lo;
        self.lo += self.pat;
        return val;
    }

    fn lessThan(ctx: void, a: IDs, b: IDs) math.Order {
        _ = ctx;
        return math.order(a.lo, b.lo);
    }
};

const Range = struct {
    lo: u64,
    hi: u64,

    fn parse(r: *Reader) !Range {
        var range: Range = undefined;

        range.lo = try scan.unsigned(u64, r);
        try scan.prefix(r, "-");
        range.hi = try scan.unsigned(u64, r);

        return range;
    }

    fn twiceIDs(self: Range) !u64 {
        var lo = @max(self.lo, 1);
        const hi = self.hi + 1;
        var twice: u64 = 0;

        while (lo < hi) {
            const width = digits(lo);
            const next = @min(hi, try math.powi(u64, 10, width));
            var ids = try repeatingIDs(lo, next, width, 2);
            while (ids.next()) |id| twice += id;
            lo = next;
        }

        return twice;
    }

    fn invalidIDs(self: Range, alloc: Allocator) !u64 {
        var lo = @max(self.lo, 1);
        const hi = self.hi + 1;
        var invalid: u64 = 0;

        while (lo < hi) {
            const width = digits(lo);
            const next = @min(hi, try math.powi(u64, 10, width));

            var queue: PriorityQueue(IDs, void, IDs.lessThan) = .init(alloc, {});
            defer queue.deinit();

            for (2..width + 1) |i| {
                if (width % i != 0) continue;
                const parts: u8 = @intCast(i);
                const ids = try repeatingIDs(lo, next, width, parts);
                try queue.add(ids);
            }

            lo = next;
            var seen: u64 = 0;
            while (queue.removeOrNull()) |ids| {
                var ids_ = ids;
                if (ids_.next()) |id| {
                    try queue.add(ids_);
                    if (seen < id) {
                        invalid += id;
                        seen = id;
                    }
                }
            }
        }

        return invalid;
    }
};

pub fn main() !void {
    var input: [4096]u8 = undefined;
    var reader = File.stdin().reader(&input);
    const stdin = &reader.interface;

    var buf: [8192]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&buf);

    var part1: u64 = 0;
    var part2: u64 = 0;
    while (Range.parse(stdin)) |range| {
        part1 += try range.twiceIDs();
        part2 += try range.invalidIDs(fba.allocator());
        scan.prefix(stdin, ",") catch break;
    } else |_| {}

    std.debug.print("Part 1: {d}\n", .{part1});
    std.debug.print("Part 2: {d}\n", .{part2});
}

/// Return the number of IDs of width `width` that repeat with period `parts`
/// in the prefix of range `[lo, hi)` with the same number of digits as `lo`.
///
/// Returns the next lower bound to continue processing, and the number of
/// repeated IDs with period `parts` in the processed range.
fn repeatingIDs(lo: u64, hi: u64, width: u8, parts: u8) !IDs {
    // If this width is not divisible by `parts`, there are no numbers
    // with this width that can be split into `parts` repeating sections.
    if (width % parts != 0) {
        return .empty;
    }

    // Increase `lo` until it is at or after the first potential repeating
    // number with this number of digits.
    const pat = try factor(width, parts);
    const fst = pat * try math.powi(u64, 10, width / parts - 1);

    const idx = ((@max(lo, fst) - 1) / pat + 1) * pat;
    return .init(idx, hi, pat);
}

/// Return the factor of a `width`-digit decimal number that can be split into
/// `parts` repeating sections.
fn factor(width: u8, parts: u8) !u64 {
    const stride = width / parts;
    var pattern: u64 = 1;
    var i = stride;
    while (i < width) : (i += stride) {
        pattern += try math.powi(u64, 10, i);
    }

    return pattern;
}

/// Number of decimal digits in number `n`.
fn digits(n: u64) u8 {
    return if (n == 0) 1 else @as(u8, @intCast(math.log10(n))) + 1;
}

test "factor" {
    try std.testing.expectEqual(11, factor(2, 2));
    try std.testing.expectEqual(101, factor(4, 2));
    try std.testing.expectEqual(1001, factor(6, 2));
    try std.testing.expectEqual(10001, factor(8, 2));
    try std.testing.expectEqual(1010101, factor(8, 4));

    try std.testing.expectEqual(111, factor(3, 3));
    try std.testing.expectEqual(10101, factor(6, 3));
    try std.testing.expectEqual(1001001, factor(9, 3));
}

test "digits" {
    try std.testing.expectEqual(1, digits(0));
    try std.testing.expectEqual(1, digits(5));
    try std.testing.expectEqual(2, digits(10));
    try std.testing.expectEqual(3, digits(999));
    try std.testing.expectEqual(4, digits(1000));
}
