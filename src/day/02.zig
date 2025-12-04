const std = @import("std");
const lib = @import("libadvent");

const math = std.math;
const scan = lib.scan;

const File = std.fs.File;
const Reader = std.io.Reader;

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
            // Only process numbers with the same number of digits, each
            // iteration.
            const width = digits(lo);
            const next = @min(hi, try math.powi(u64, 10, width));

            // If the current chunk of numbers has an odd number of digits, it
            // cannot contain a twice-repeated ID.
            if (width % 2 != 0) {
                lo = next;
                continue;
            }

            // Increase `lo` until it is at or after the first potential twice
            // repeating number with this number of digits.
            const pat = try factor(width, 2);
            const fst = pat * try math.powi(u64, 10, width / 2 - 1);
            lo = ((@max(lo, fst) - 1) / pat + 1) * pat;
            while (lo < next) : (lo += pat) {
                twice += lo;
            }

            lo = next;
        }

        return twice;
    }
};

pub fn main() !void {
    var input: [4096]u8 = undefined;
    var reader = File.stdin().reader(&input);
    const stdin = &reader.interface;

    var invalid: u64 = 0;
    while (Range.parse(stdin)) |range| {
        invalid += try range.twiceIDs();
        scan.prefix(stdin, ",") catch break;
    } else |_| {}

    std.debug.print("Part 1: {d}\n", .{invalid});
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
}

test "digits" {
    try std.testing.expectEqual(1, digits(0));
    try std.testing.expectEqual(1, digits(5));
    try std.testing.expectEqual(2, digits(10));
    try std.testing.expectEqual(3, digits(999));
    try std.testing.expectEqual(4, digits(1000));
}
