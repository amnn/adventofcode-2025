const std = @import("std");
const lib = @import("libadvent");

const math = std.math;
const heap = std.heap;
const scan = lib.scan;
const sort = std.sort;

const ArrayList = std.array_list.Managed;
const File = std.fs.File;
const Reader = std.io.Reader;

const Range = struct {
    lo: u64,
    hi: u64,

    fn parse(r: *Reader) !Range {
        var range: Range = undefined;

        range.lo = try scan.unsigned(u64, r);
        try scan.prefix(r, "-");
        range.hi = 1 + try scan.unsigned(u64, r);

        return range;
    }

    fn len(self: Range) u64 {
        return self.hi - self.lo;
    }

    fn merge(self: *Range, other: Range) bool {
        if (self.hi < other.lo) {
            return false;
        } else {
            self.hi = @max(self.hi, other.hi);
            return true;
        }
    }

    fn lessThan(ctx: void, a: Range, b: Range) bool {
        _ = ctx;
        return a.lo < b.lo;
    }
};

pub fn main() !void {
    var input: [4096]u8 = undefined;
    var reader = File.stdin().reader(&input);
    const stdin = &reader.interface;

    var buf: [8192]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&buf);

    // Read the ranges.
    var ranges: ArrayList(Range) = .init(fba.allocator());
    while (Range.parse(stdin)) |r| {
        try ranges.append(r);
        try scan.prefix(stdin, "\n");
    } else |_| {
        try scan.prefix(stdin, "\n");
    }

    // Sort them by lowerbound.
    sort.pdq(Range, ranges.items, {}, Range.lessThan);

    // Merge overlapping ranges.
    var i: usize = 1;
    var m: usize = 0;
    while (i + m < ranges.items.len) {
        if (ranges.items[i - 1].merge(ranges.items[i + m])) {
            m += 1;
        } else {
            ranges.items[i] = ranges.items[i + m];
            i += 1;
        }
    }

    // Trim the ranges after merging
    ranges.shrinkAndFree(ranges.items.len - m);

    // Check for fresh ingredients from the list supplied.
    var part1: usize = 0;
    while (scan.unsigned(u64, stdin)) |num| {
        if (isFresh(ranges.items, num)) {
            part1 += 1;
        }

        scan.prefix(stdin, "\n") catch break;
    } else |_| {}

    var part2: u64 = 0;
    for (ranges.items) |r| {
        part2 += r.len();
    }

    std.debug.print("Part 1: {d}\n", .{part1});
    std.debug.print("Part 2: {d}\n", .{part2});
}

fn isFresh(ranges: []const Range, ingredient: u64) bool {
    const idx = sort.upperBound(Range, ranges, ingredient, struct {
        fn compare(ctx: u64, r: Range) math.Order {
            return math.order(ctx, r.hi);
        }
    }.compare);

    return idx < ranges.len and ranges[idx].lo <= ingredient;
}
