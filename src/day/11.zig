const std = @import("std");
const lib = @import("libadvent");

const scan = lib.scan;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMapUnmanaged = std.AutoHashMapUnmanaged;
const File = std.fs.File;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const Reader = std.io.Reader;

const ID = struct {
    id: u16,

    const OUT: ID = .str("out");
    const YOU: ID = .str("you");

    fn str(s: *const [3]u8) ID {
        var id: u16 = 0;
        for (s) |b| id = id * 26 + @as(u16, b - 'a');
        return ID{ .id = id };
    }

    fn parse(r: *Reader) !ID {
        var buf: [3]u8 = undefined;
        try r.readSliceAll(&buf);
        return .str(&buf);
    }
};

const Nodes = AutoHashMapUnmanaged(ID, ArrayList(ID));
const Paths = AutoHashMapUnmanaged(ID, usize);

const Graph = struct {
    nodes: Nodes,

    fn parse(r: *Reader, a: Allocator) !Graph {
        var nodes: Nodes = .empty;
        errdefer nodes.deinit(a);

        while (ID.parse(r)) |from| {
            var to: ArrayList(ID) = .{};
            errdefer to.deinit(a);

            try scan.prefix(r, ":");
            while (scan.prefix(r, " ")) {
                const nbr: ID = try .parse(r);
                try to.append(a, nbr);
            } else |_| {}

            try nodes.put(a, from, to);
            scan.prefix(r, "\n") catch break;
        } else |_| {}

        return Graph{ .nodes = nodes };
    }

    fn neighbours(self: *const Graph, id: ID) ?[]ID {
        const node = self.nodes.get(id) orelse return null;
        return node.items;
    }

    fn topological(self: *const Graph, a: Allocator) ![]ID {
        const State = enum { doing, done };

        var visit: AutoHashMapUnmanaged(ID, State) = .empty;
        defer visit.deinit(a);

        var order: ArrayList(ID) = .{};
        errdefer order.deinit(a);

        const Traversal = struct {
            visit: *AutoHashMapUnmanaged(ID, State),
            order: *ArrayList(ID),
            graph: *const Graph,

            const Self = @This();

            fn traverse(t: *Self, a_: Allocator, node: ID) !void {
                const res = try t.visit.getOrPut(a_, node);
                if (res.found_existing) {
                    return if (res.value_ptr.* == .doing) error.Cyclic else {};
                }

                res.value_ptr.* = .doing;
                if (t.graph.nodes.get(node)) |nbrs| for (nbrs.items) |nbr| {
                    try t.traverse(a_, nbr);
                };

                try t.order.append(a_, node);
                t.visit.putAssumeCapacity(node, .done);
            }
        };

        var t: Traversal = .{
            .visit = &visit,
            .order = &order,
            .graph = self,
        };

        try t.traverse(a, ID.YOU);
        return order.toOwnedSlice(a);
    }

    fn deinit(self: *Graph, a: Allocator) void {
        var it = self.nodes.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(a);
        }
        self.nodes.deinit(a);
    }
};

pub fn main() !void {
    var input: [4096]u8 = undefined;
    var reader = File.stdin().reader(&input);
    const stdin = &reader.interface;

    var buf: [4 * 1024 * 1024]u8 = undefined;
    var fba: FixedBufferAllocator = .init(&buf);
    const alloc = fba.allocator();

    var graph: Graph = try .parse(stdin, alloc);
    defer graph.deinit(alloc);

    const order = try graph.topological(alloc);
    defer alloc.free(order);

    var paths: Paths = .empty;
    defer paths.deinit(alloc);

    var found: bool = false;
    for (order) |id| {
        if (id.id == ID.OUT.id) {
            found = true;
            try paths.put(alloc, id, 1);
        } else if (!found) {
            try paths.put(alloc, id, 0);
        } else {
            var total: usize = 0;
            if (graph.neighbours(id)) |nbrs| for (nbrs) |nbr| {
                total += paths.get(nbr) orelse continue;
            };
            try paths.put(alloc, id, total);
        }
    }

    std.debug.print("Part 1: {}\n", .{paths.get(ID.YOU) orelse 0});
}
