const std = @import("std");
const lib = @import("libadvent");

const grid = lib.grid;
const scan = lib.scan;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const Grid = lib.grid.Grid;
const Reader = std.io.Reader;

const SHAPES: usize = 6;

const Shape = struct {
    rect: usize,
    area: usize,

    fn parse(r: *Reader, a: Allocator) !Shape {
        var g = try grid.read(r, a);
        defer g.deinit(a);

        var area: usize = 0;
        var cells = g.find('#');
        while (cells.next()) |_| {
            area += 1;
        }

        return .{
            .rect = g.width * g.height,
            .area = area,
        };
    }
};

const Region = struct {
    area: usize,
    shapes: [SHAPES]usize,

    fn parse(r: *Reader) !Region {
        const width = try scan.unsigned(usize, r);
        try scan.prefix(r, "x");
        const height = try scan.unsigned(usize, r);
        try scan.prefix(r, ":");

        var shapes: [SHAPES]usize = undefined;
        for (0..SHAPES) |i| {
            try scan.prefix(r, " ");
            shapes[i] = try scan.unsigned(usize, r);
        }

        return .{
            .area = width * height,
            .shapes = shapes,
        };
    }
};

pub fn main() !void {
    var input: [4096]u8 = undefined;
    var reader = std.fs.File.stdin().reader(&input);
    const stdin = &reader.interface;

    var buf: [8 * 1024]u8 = undefined;
    var fba: FixedBufferAllocator = .init(&buf);
    const alloc = fba.allocator();

    var shapes: ArrayList(Shape) = .{};
    defer shapes.deinit(alloc);

    for (0..SHAPES) |_| {
        // Ignore the index
        _ = try scan.until(stdin, '\n');

        const shape: Shape = try .parse(stdin, alloc);
        try shapes.append(alloc, shape);
    }

    var fits: usize = 0;
    var uncertain: usize = 0;
    var too_tight: usize = 0;
    while (Region.parse(stdin)) |region| {
        var total_shape_rect: usize = 0;
        var total_shape_area: usize = 0;

        for (region.shapes, shapes.items) |count, shape| {
            total_shape_rect += shape.rect * count;
            total_shape_area += shape.area * count;
        }

        if (total_shape_rect <= region.area) {
            // This is not strictly true -- the region could have enough space
            // for to fit the space around each shape, but not arranged in a
            // usable way (imagine a 1x8 region and two 2x2 shapes), but it
            // worked, so *shrug*.
            fits += 1;
        } else if (total_shape_area > region.area) {
            too_tight += 1;
        } else {
            uncertain += 1;
        }

        try scan.prefix(stdin, "\n");
    } else |_| {}

    std.debug.print("Fits: {}\n", .{fits});
    std.debug.print("Uncertain: {}\n", .{uncertain});
    std.debug.print("Too Tight: {}\n", .{too_tight});
}
