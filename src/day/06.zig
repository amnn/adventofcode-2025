const std = @import("std");
const lib = @import("libadvent");

const assert = std.debug.assert;
const mem = std.mem;
const scan = lib.scan;

const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const File = std.fs.File;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const Reader = std.io.Reader;

const Op = enum {
    @"+",
    @"*",
};

pub fn main() !void {
    var input: [4096]u8 = undefined;
    var reader = File.stdin().reader(&input);
    const stdin = &reader.interface;

    var buf: [4 * 1024 * 1024]u8 = undefined;
    var fba: FixedBufferAllocator = .init(&buf);
    const alloc: Allocator = fba.allocator();

    var args = std.process.args();
    _ = args.next(); // skip program name

    const part = args.next() orelse "-1";

    if (std.mem.eql(u8, part, "-1")) {
        try part1(stdin, alloc);
    } else if (std.mem.eql(u8, part, "-2")) {
        try part2(stdin, alloc);
    } else {
        std.debug.print("Unknown argument: {s}\n", .{part});
        return error.InvalidArgument;
    }
}

fn part1(r: *Reader, alloc: Allocator) !void {
    var rands: ArrayList([]u64) = try .initCapacity(alloc, 0);
    defer rands.deinit();
    defer for (rands.items) |item| alloc.free(item);

    while (true) {
        const rand = parseOperand(r, alloc) catch break;
        if (rand.len == 0) break;
        try rands.append(rand);

        scan.spaces(r);
        try scan.prefix(r, "\n");
    }

    const ops = try parseOperator(r, alloc);

    var grand_total: u64 = 0;
    for (ops, 0..) |op, i| {
        switch (op) {
            .@"+" => {
                var total: u64 = 0;
                for (rands.items) |rand| {
                    total += rand[i];
                }
                grand_total += total;
            },

            .@"*" => {
                var total: u64 = 1;
                for (rands.items) |rand| {
                    total *= rand[i];
                }
                grand_total += total;
            },
        }
    }

    std.debug.print("Part 1: {d}\n", .{grand_total});
}

fn part2(r: *Reader, alloc: Allocator) !void {
    var lines: ArrayList([]u8) = try .initCapacity(alloc, 0);
    defer lines.deinit();
    defer for (lines.items) |item| alloc.free(item);

    // Read all lines, retaining them in reverse order so that we can process
    // all operands, before we see their relevant operator.
    while (try lib.readLineExclusive(r)) |line| {
        const rev = try alloc.dupe(u8, line);
        mem.reverse(u8, rev);
        try lines.append(rev);
    }

    var grand_total: u64 = 0;

    var rands: ArrayList(u64) = try .initCapacity(alloc, 0);
    defer rands.deinit();
    defer assert(rands.items.len == 0);

    const ops = lines.items[lines.items.len - 1];
    const depth = lines.items.len - 1;
    for (ops, 0..) |op, i| {
        // If this position is all spaces, skip it.
        for (lines.items) |line| {
            const c = line[i];
            if (c != ' ') break;
        } else {
            continue;
        }

        // Process the operand at this position, into the operand stack.
        {
            var rand: u64 = 0;
            for (lines.items[0..depth]) |line| {
                const c = line[i];
                if (c == ' ') continue;
                rand *= 10;
                rand += @intCast(c - '0');
            }
            try rands.append(rand);
        }

        // Check if there is an operation at this position, and if so, unwind
        // the operand stack.
        switch (op) {
            ' ' => continue,

            '+' => {
                var total: u64 = 0;
                while (rands.pop()) |rand| {
                    total += rand;
                }
                grand_total += total;
            },

            '*' => {
                var total: u64 = 1;
                while (rands.pop()) |rand| {
                    total *= rand;
                }
                grand_total += total;
            },

            else => return error.InvalidOperator,
        }
    }

    std.debug.print("Part 2: {d}\n", .{grand_total});
}

fn parseOperand(r: *Reader, alloc: Allocator) ![]u64 {
    var digits: ArrayList(u64) = try .initCapacity(alloc, 0);
    defer digits.deinit();

    while (true) {
        scan.spaces(r);
        const rand = scan.unsigned(u64, r) catch break;
        try digits.append(rand);
    }

    return digits.toOwnedSlice();
}

fn parseOperator(r: *Reader, alloc: Allocator) ![]Op {
    var ops: ArrayList(Op) = try .initCapacity(alloc, 0);
    defer ops.deinit();

    while (true) {
        scan.spaces(r);
        const op = scan.@"enum"(Op, r) catch break;
        try ops.append(op);
    }

    return ops.toOwnedSlice();
}
