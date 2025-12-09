const std = @import("std");
const lib = @import("libadvent");

const scan = lib.scan;
const sort = std.sort;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const File = std.fs.File;
const DebugAllocator = std.heap.DebugAllocator;
const Point2D = lib.grid.Point;
const Reader = std.io.Reader;
const SegmentedList = std.SegmentedList;

const Point3D = struct {
    x: u64,
    y: u64,
    z: u64,

    fn parse(r: *Reader) !Point3D {
        const x = try scan.unsigned(u64, r);
        try lib.scan.prefix(r, ",");
        const y = try scan.unsigned(u64, r);
        try lib.scan.prefix(r, ",");
        const z = try scan.unsigned(u64, r);

        return .{ .x = x, .y = y, .z = z };
    }

    fn distSq(this: Point3D, that: Point3D) u64 {
        const dx = @max(this.x, that.x) - @min(this.x, that.x);
        const dy = @max(this.y, that.y) - @min(this.y, that.y);
        const dz = @max(this.z, that.z) - @min(this.z, that.z);
        return dx * dx + dy * dy + dz * dz;
    }
};

const Set = struct {
    parent: *Set,
    size: u64,

    fn init(self: *Set) void {
        self.parent = self;
        self.size = 1;
    }

    fn find(self: *Set) *Set {
        if (self.parent != self) {
            self.parent = self.parent.find();
        }
        return self.parent;
    }

    fn merge(this: *Set, that: *Set) *Set {
        const rthis = this.find();
        const rthat = that.find();
        if (rthis == rthat) return rthis;

        if (rthis.size < rthat.size) {
            rthis.parent = rthat;
            rthat.size += rthis.size;
            return rthat;
        } else {
            rthat.parent = rthis;
            rthis.size += rthat.size;
            return rthis;
        }
    }
};

const Node = struct {
    point: Point3D,
    set: Set,

    fn parse(self: *Node, r: *Reader) !void {
        self.point = try Point3D.parse(r);
        self.set.init();
    }
};

pub fn main() !void {
    var input: [4096]u8 = undefined;
    var reader = File.stdin().reader(&input);
    const stdin = &reader.interface;

    var gpa: DebugAllocator(.{}) = .init;
    const alloc = gpa.allocator();

    // Read points as inputs, and associate each with its own disjoint set.
    var nodes: SegmentedList(Node, 0) = .{};
    defer nodes.deinit(alloc);

    while (true) {
        const node = try nodes.addOne(alloc);
        node.parse(stdin) catch {
            _ = nodes.pop();
            break;
        };

        scan.prefix(stdin, "\n") catch break;
    }

    // Generate all edges between points, sorted by distance.
    const side = nodes.count();
    var edges: ArrayList(Point2D) = try .initCapacity(alloc, side * side);
    defer edges.deinit(alloc);

    for (0..side) |i| {
        for (i + 1..side) |j| {
            try edges.append(alloc, .pt(i, j));
        }
    }

    const Ordering = struct {
        fn lessThan(ns: SegmentedList(Node, 0), a: Point2D, b: Point2D) bool {
            const da = ns.at(a.x).point.distSq(ns.at(a.y).point);
            const db = ns.at(b.x).point.distSq(ns.at(b.y).point);
            return da < db;
        }
    };

    sort.pdq(Point2D, edges.items, nodes, Ordering.lessThan);

    var args = std.process.args();
    _ = args.next(); // skip program name

    const part = args.next() orelse "-1";

    if (std.mem.eql(u8, part, "-1")) {
        try part1(&nodes, edges, alloc);
    } else if (std.mem.eql(u8, part, "-2")) {
        part2(&nodes, edges);
    } else {
        std.debug.print("Unknown argument: {s}\n", .{part});
        return error.InvalidArgument;
    }
}

fn part1(
    nodes: *SegmentedList(Node, 0),
    edges: ArrayList(Point2D),
    alloc: Allocator,
) !void {

    // Merge together the first 1000 edges in increasing order of distance.
    for (edges.items[0..@min(1000, edges.items.len)]) |edge| {
        const a = nodes.at(edge.x);
        const b = nodes.at(edge.y);
        _ = a.set.merge(&b.set);
    }

    // Pick out circuit sizes, and sort them in descending order of size.
    var iter = nodes.iterator(0);
    var circuits: ArrayList(u64) = .{};
    defer circuits.deinit(alloc);

    while (iter.next()) |node| {
        const root = node.set.find();
        if (root.size == 0) continue;
        try circuits.append(alloc, root.size);
        root.size = 0;
    }

    sort.pdq(u64, circuits.items, {}, sort.desc(u64));

    // Multiply together the sizes of the three largest circuits.
    var product: u64 = 1;
    for (circuits.items[0..@min(3, circuits.items.len)]) |size| {
        product *= size;
    }

    std.debug.print("Part 1: {d}\n", .{product});
}

fn part2(
    nodes: *SegmentedList(Node, 0),
    edges: ArrayList(Point2D),
) void {
    for (edges.items) |edge| {
        const a = nodes.at(edge.x);
        const b = nodes.at(edge.y);
        const root = a.set.merge(&b.set);

        if (root.size >= nodes.count()) {
            std.debug.print("Part 2: {d}\n", .{a.point.x * b.point.x});
            break;
        }
    }
}
