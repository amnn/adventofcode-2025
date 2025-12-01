const std = @import("std");
const lib = @import("libadvent");

const scan = lib.scan;

const File = std.fs.File;
const Reader = std.io.Reader;

const CLICKS: u8 = 100;

const Dir = enum { L, R };

const Step = struct {
    dir: Dir,
    clicks: u32,

    fn parse(r: *Reader) !Step {
        return Step{
            .dir = try scan.@"enum"(Dir, r),
            .clicks = try scan.unsigned(u32, r),
        };
    }

    fn crossings(self: Step, dial: u32) u32 {
        var times: u32 = @divFloor(self.clicks, CLICKS);
        const delta = self.clicks % CLICKS;

        switch (self.dir) {
            // When the dial rests on 0 we shouldn't double count it as a
            // crossing -- only count it if we arrive at 0, not if we are
            // leaving zero.
            .L => if (delta >= dial and dial > 0) {
                times += 1;
            },

            .R => if (dial + delta >= CLICKS) {
                times += 1;
            },
        }

        return times;
    }

    fn apply(self: Step, dial: u32) u32 {
        const delta = self.clicks % CLICKS;
        const new = dial + switch (self.dir) {
            .L => CLICKS - delta,
            .R => delta,
        };
        return new % CLICKS;
    }
};

pub fn main() !void {
    var input: [4096]u8 = undefined;
    var reader = File.stdin().reader(&input);
    const stdin = &reader.interface;

    var dial: u32 = 50;
    var part1: u32 = 0;
    var part2: u32 = 0;
    while (Step.parse(stdin)) |step| {
        part2 += step.crossings(dial);
        dial = step.apply(dial);
        part1 += @intFromBool(dial == 0);

        scan.prefix(stdin, "\n") catch break;
    } else |_| {}

    std.debug.print("Part 1: {d}\n", .{part1});
    std.debug.print("Part 2: {d}\n", .{part2});
}
