const std = @import("std");
const lib = @import("libadvent");

const grid = lib.grid;

const File = std.fs.File;
const Grid = grid.Grid;

const DELTAS = [_][2]isize{
    .{ -1, -1 },
    .{ -1, 0 },
    .{ -1, 1 },
    .{ 0, 1 },
    .{ 1, 1 },
    .{ 1, 0 },
    .{ 1, -1 },
    .{ 0, -1 },
};

pub fn main() !void {
    var input: [4096]u8 = undefined;
    var reader = File.stdin().reader(&input);
    const stdin = &reader.interface;

    var buf: [4 * 1024 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);

    var g = try grid.read(stdin, fba.allocator());
    var removed: usize = 0;
    while (true) {
        const round = try removeRolls(&g);
        removed += round;

        std.debug.print("Removed {d} rolls\n", .{round});
        if (round == 0) break;
    }

    std.debug.print("Total Removed: {d}\n", .{removed});
}

fn removeRolls(g: *Grid(u8)) !usize {
    var removed: usize = 0;

    // Mark eligible rolls for removal, don't remove them yet because they may
    // be considered a neighbour of some other roll that shouldn't technically
    // be removed yet.
    var rolls = g.find('@');
    while (rolls.next()) |pt| {
        var nbrs: usize = 0;
        for (DELTAS) |d| {
            const dx, const dy = d;
            const nbr = g.get(pt.move(dx, dy) orelse continue) orelse continue;
            if (nbr != '.') {
                nbrs += 1;
            }
        }

        if (nbrs < 4) {
            try g.put(pt, 'x');
            removed += 1;
        }
    }

    // Actually remove the marked rolls.
    var marks = g.find('x');
    while (marks.next()) |pt| {
        try g.put(pt, '.');
    }

    return removed;
}
