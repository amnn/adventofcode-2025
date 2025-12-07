const std = @import("std");
const lib = @import("libadvent");

const assert = std.debug.assert;
const grid = lib.grid;
const mem = std.mem;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const File = std.fs.File;
const Grid = lib.grid.Grid;
const Point = lib.grid.Point;

pub fn main() !void {
    var input: [4096]u8 = undefined;
    var reader = File.stdin().reader(&input);
    const stdin = &reader.interface;

    var buf: [4 * 1024 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    var g = try grid.read(stdin, fba.allocator());
    defer g.deinit(fba.allocator());

    std.debug.print("Part 1: {d}\n", .{try part1(g, alloc)});
    std.debug.print("Part 2: {d}\n", .{try part2(g, alloc)});
}

fn part1(g: Grid(u8), alloc: Allocator) !u64 {
    const s = start(g) orelse return error.NoStart;

    var f: ArrayList(u64) = try .initCapacity(alloc, g.width);
    defer f.deinit(alloc);

    var b: ArrayList(u64) = try .initCapacity(alloc, g.width);
    defer b.deinit(alloc);

    var y: usize = 1;
    var splits: u64 = 0;
    f.appendAssumeCapacity(s.x);
    while (g.row(y)) |r| : (y += 1) {
        for (f.items) |x| {
            if (r[x] == '^') {
                splits += 1;
                if (x > 0) appendOffset(&b, x - 1);
                if (x + 1 < g.width) appendOffset(&b, x + 1);
            } else {
                appendOffset(&b, x);
            }
        }

        f.clearRetainingCapacity();
        mem.swap(ArrayList(u64), &f, &b);
    }

    return splits;
}

fn part2(g: Grid(u8), alloc: Allocator) !u64 {
    const s = start(g) orelse return error.NoStart;

    var f = try alloc.alloc(u64, g.width);
    defer alloc.free(f);

    var b = try alloc.alloc(u64, g.width);
    defer alloc.free(b);

    for (f) |*t| t.* = 1;

    var y = g.height;
    while (y > 0) : (y -= 1) {
        const row = g.row(y - 1).?;
        for (b, 0..) |*t, x| {
            if (row[x] == '^') {
                t.* = 0;
                if (x > 0) t.* += f[x - 1];
                if (x + 1 < g.width) t.* += f[x + 1];
            } else {
                t.* = f[x];
            }
        }

        mem.swap([]u64, &f, &b);
    }

    return f[s.x];
}

fn start(g: Grid(u8)) ?Point {
    var starts = g.find('S');
    const s = starts.next() orelse return null;
    assert(s.y == 0);
    assert(starts.next() == null);
    return s;
}

fn appendOffset(buf: *ArrayList(u64), idx: u64) void {
    if (buf.items.len == 0 or buf.items[buf.items.len - 1] != idx) {
        buf.appendAssumeCapacity(idx);
    }
}
