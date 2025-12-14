const std = @import("std");
const lib = @import("libadvent");

const debug = std.debug;
const math = std.math;
const mem = std.mem;
const scan = lib.scan;
const sort = std.sort;

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const Reader = std.io.Reader;

const Face = enum(u1) { L, R };
const Axis = enum(u1) { X, Y };

const Point = struct {
    x: u64,
    y: u64,

    fn parse(r: *Reader) !Point {
        const x = try scan.unsigned(u64, r);
        try lib.scan.prefix(r, ",");
        const y = try scan.unsigned(u64, r);
        return .{ .x = x, .y = y };
    }

    fn dir(self: Point, other: Point) ?struct { Axis, Face } {
        return if (self.x == other.x)
            .{ .X, if (self.y < other.y) .R else .L }
        else if (self.y == other.y)
            .{ .Y, if (self.x < other.x) .R else .L }
        else
            null;
    }
};

const Rect = struct {
    xlo: u64,
    xhi: u64,
    ylo: u64,
    yhi: u64,

    fn area(self: Rect) u64 {
        const w = 1 + self.xhi - self.xlo;
        const h = 1 + self.yhi - self.ylo;
        return w * h;
    }

    fn initCorners(a: Point, b: Point) Rect {
        return .{
            .xlo = @min(a.x, b.x),
            .xhi = @max(a.x, b.x),
            .ylo = @min(a.y, b.y),
            .yhi = @max(a.y, b.y),
        };
    }

    fn split(self: Rect, axis: Axis, off: u64, inside: Face) struct { in: ?Rect, out: ?Rect } {
        var lo = self;
        var hi = self;

        const mhi, const mlo = switch (axis) {
            .X => .{ &lo.xhi, &hi.xlo },
            .Y => .{ &lo.yhi, &hi.ylo },
        };

        mhi.* = @min(mhi.*, switch (inside) {
            .L => off,
            .R => off - 1,
        });

        mlo.* = @max(mlo.*, switch (inside) {
            .L => off + 1,
            .R => off,
        });

        const lo_ = if (lo.xlo <= lo.xhi and lo.ylo <= lo.yhi) lo else null;
        const hi_ = if (hi.xlo <= hi.xhi and hi.ylo <= hi.yhi) hi else null;

        return switch (inside) {
            .L => .{ .in = lo_, .out = hi_ },
            .R => .{ .in = hi_, .out = lo_ },
        };
    }
};

const Edge = struct {
    /// The face that is considered "inside" the edge.
    face: Face,

    /// The constant coordinate along the axis.
    off: u64,

    /// The inclusive lowerbound of the line along its varying axis.
    lo: u64,

    /// The exclusive upperbound of the line along its varying axis.
    hi: u64,

    /// Initialise an axis-aligned edge between two points.
    ///
    /// Returns `null` if the edge is invalid (not axis-aligned or zero-length)
    /// otherwise returns a description of the line.
    fn init(src: Point, inside: Face, dst: Point) ?struct { Axis, Edge } {
        if (src.x == dst.x) {
            const lo = @min(src.y, dst.y);
            const hi = @max(src.y, dst.y) + 1;
            if (lo + 1 == hi) return null;

            const face = switch (inside) {
                .L => if (src.y < dst.y) Face.L else Face.R,
                .R => if (src.y < dst.y) Face.R else Face.L,
            };

            return .{ .X, .{ .face = face, .off = src.x, .lo = lo, .hi = hi } };
        } else if (src.y == dst.y) {
            const lo = @min(src.x, dst.x);
            const hi = @max(src.x, dst.x) + 1;
            if (lo + 1 == hi) return null;

            const face = switch (inside) {
                .L => if (src.x < dst.x) Face.R else Face.L,
                .R => if (src.x < dst.x) Face.L else Face.R,
            };

            return .{ .Y, .{ .face = face, .off = src.y, .lo = lo, .hi = hi } };
        } else {
            return null;
        }
    }

    fn len(self: Edge) u64 {
        return self.hi - @min(self.lo, self.hi);
    }

    /// Splits `self` by a half-space described by `off` and `inside`.
    ///
    /// The half-space is described by its coordinate in the orthogonal axis to
    /// `self`, and the face that points "inside" the half-space. If the inside
    /// face points left, then the half-space includes all coordinates less
    /// than or equal to `off`, whereas if it points right, it includes all
    /// coordinates greater than or equal to `off` (the boundary is always
    /// inclusive).
    ///
    /// Returns a struct containing the `in`side portion of `self` and the
    /// `out`side portion of `self`. Both sides are optional, and may be `null`
    /// if the resulting portion is zero-length.
    fn split(self: Edge, inside: Face, off: u64) struct { in: ?Edge, out: ?Edge } {
        const m = switch (inside) {
            .L => off + 1,
            .R => off,
        };

        var lo = self;
        var hi = self;

        lo.hi = @min(lo.hi, m);
        hi.lo = @max(hi.lo, m);

        // Only preserve a side of the split if it has non-zero length, and in
        // case it has unit length, it is not entirely overlapped by the
        // inclusive boundary at offset.
        const lo_ = if (lo.len() > 0 and !(lo.len() == 1 and lo.lo == off)) lo else null;
        const hi_ = if (hi.len() > 0 and !(hi.len() == 1 and hi.lo == off)) hi else null;

        return switch (inside) {
            .L => .{ .in = lo_, .out = hi_ },
            .R => .{ .in = hi_, .out = lo_ },
        };
    }

    fn axisLessThan(ctx: void, self: Edge, other: Edge) bool {
        _ = ctx;
        return self.off < other.off;
    }

    fn axisCompare(off: u64, e: Edge) math.Order {
        return math.order(off, e.off);
    }
};

const Shape = struct {
    arena: ArenaAllocator,
    root: ?*Node,

    fn init(points: []Point, alloc: Allocator) !Shape {
        var arena: ArenaAllocator = .init(alloc);
        errdefer arena.deinit();

        var in = points[points.len - 1].dir(points[0]) orelse
            return error.InvalidShape;

        var winding: i8 = 0;
        for (points, 0..) |src, i| {
            const dst = points[(i + 1) % points.len];
            const out = src.dir(dst) orelse return error.InvalidShape;

            const iax, const i_face = in;
            const oax, const o_face = out;

            if (iax == oax) return error.InvalidShape;
            const turn = switch (iax) {
                .X => if (i_face == o_face) Face.R else Face.L,
                .Y => if (i_face == o_face) Face.L else Face.R,
            };

            in = out;
            switch (turn) {
                .L => winding -= 1,
                .R => winding += 1,
            }
        }

        // The normal to the shape edges that point into the shape.
        // Counter-clockwise (winding=-4) means interior is to the LEFT of travel.
        // Clockwise (winding=+4) means interior is to the RIGHT of travel.
        const inside = if (winding == -4)
            Face.L
        else if (winding == 4)
            Face.R
        else if (@mod(winding, 4) == 0)
            return error.SelfIntersecting
        else
            return error.Open;

        var xs: ArrayList(Edge) = .{};
        defer xs.deinit(alloc);

        var ys: ArrayList(Edge) = .{};
        defer ys.deinit(alloc);

        for (points, 0..) |src, i| {
            const dst = points[(i + 1) % points.len];
            const axis, const edge = Edge.init(src, inside, dst) orelse
                return error.InvalidShape;

            switch (axis) {
                .X => try xs.append(alloc, edge),
                .Y => try ys.append(alloc, edge),
            }
        }

        const root = try Node.init(&xs, &ys, .X, &arena, alloc);
        return .{ .arena = arena, .root = root };
    }

    fn deinit(self: *Shape) void {
        self.arena.deinit();
    }

    /// Area of the shape overlapping the given rectangle.
    fn overlap(self: Shape, rect: Rect) u64 {
        return if (self.root) |node| nodeOverlap(node, false, rect) else 0;
    }
};

const Node = struct {
    axis: Axis,
    side: Face,
    boundary: u64,
    inside: ?*Node = null,
    outside: ?*Node = null,

    fn init(
        xs: *ArrayList(Edge),
        ys: *ArrayList(Edge),
        axis: Axis,
        arena: *ArenaAllocator,
        alloc: Allocator,
    ) !?*Node {
        const as, const bs = switch (axis) {
            .X => .{ xs, ys },
            .Y => .{ ys, xs },
        };

        if (as.items.len == 0) {
            if (bs.items.len == 0) {
                return null;
            } else {
                // No edges on the current axis, but have edges on the other.
                // Continue partitioning with the other axis instead.
                const next_axis: Axis = switch (axis) {
                    .X => .Y,
                    .Y => .X,
                };
                return Node.init(xs, ys, next_axis, arena, alloc);
            }
        }

        // Pick the true median edge for the current axis.
        sort.pdq(Edge, as.items, {}, Edge.axisLessThan);
        const m = as.items.len / 2;
        const e = as.items[m];

        // Swap the true median edge to the end or beginning of the range of
        // edges that share its axis coordinate.
        const m_ = if (e.face == .L)
            sort.upperBound(Edge, as.items, e.off, Edge.axisCompare) - 1
        else
            sort.lowerBound(Edge, as.items, e.off, Edge.axisCompare);

        mem.swap(Edge, &as.items[m], &as.items[m_]);

        var ai: ArrayList(Edge) = .{};
        defer ai.deinit(alloc);

        var ao: ArrayList(Edge) = .{};
        defer ao.deinit(alloc);

        var bi: ArrayList(Edge) = .{};
        defer bi.deinit(alloc);

        var bo: ArrayList(Edge) = .{};
        defer bo.deinit(alloc);

        if (e.face == .L) {
            try ai.appendSlice(alloc, as.items[0..m_]);
            try ao.appendSlice(alloc, as.items[m_ + 1 ..]);
        } else {
            try ao.appendSlice(alloc, as.items[0..m_]);
            try ai.appendSlice(alloc, as.items[m_ + 1 ..]);
        }

        for (bs.items) |b| {
            const split = b.split(e.face, e.off);
            if (split.in) |in| try bi.append(alloc, in);
            if (split.out) |out| try bo.append(alloc, out);
        }

        as.clearAndFree(alloc);
        bs.clearAndFree(alloc);

        const ax, const xi, const xo, const yi, const yo = switch (axis) {
            .X => .{ Axis.Y, &ai, &ao, &bi, &bo },
            .Y => .{ Axis.X, &bi, &bo, &ai, &ao },
        };

        const n = try arena.allocator().create(Node);

        n.axis = axis;
        n.side = e.face;
        n.boundary = e.off;
        n.inside = try Node.init(xi, yi, ax, arena, alloc);
        n.outside = try Node.init(xo, yo, ax, arena, alloc);

        return n;
    }
};

pub fn main() !void {
    var input: [4096]u8 = undefined;
    var reader = std.fs.File.stdin().reader(&input);
    const stdin = &reader.interface;

    var buf: [4 * 1024 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    var pts: ArrayList(Point) = .{};
    defer pts.deinit(alloc);

    while (Point.parse(stdin)) |pt| {
        try pts.append(alloc, pt);
        scan.prefix(stdin, "\n") catch break;
    } else |_| {}

    var shape: Shape = try .init(pts.items, alloc);
    defer shape.deinit();

    var part1: u64 = 0;
    var part2: u64 = 0;
    for (pts.items, 0..) |a, i| {
        for (pts.items[i + 1 ..]) |b| {
            const rect: Rect = .initCorners(a, b);
            part1 = @max(part1, rect.area());

            if (rect.area() > part2 and shape.overlap(rect) == rect.area()) {
                part2 = rect.area();
            }
        }
    }

    std.debug.print("Part 1: {d}\n", .{part1});
    std.debug.print("Part 2: {d}\n", .{part2});
}

fn nodeOverlap(node: ?*const Node, inside: bool, rect: Rect) u64 {
    const n = node orelse return if (inside) rect.area() else 0;

    var area: u64 = 0;
    const split = rect.split(n.axis, n.boundary, n.side);
    if (split.in) |in| area += nodeOverlap(n.inside, true, in);
    if (split.out) |out| area += nodeOverlap(n.outside, false, out);
    return area;
}
