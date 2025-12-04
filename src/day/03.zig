const std = @import("std");
const lib = @import("libadvent");

const mem = std.mem;

const File = std.fs.File;

pub fn main() !void {
    var input: [4096]u8 = undefined;
    var reader = File.stdin().reader(&input);
    const stdin = &reader.interface;

    var part1: u64 = 0;
    var part2: u64 = 0;
    while (try lib.readLineExclusive(stdin)) |line| {
        shiftDigits(line);
        part1 += @intCast(try maxJoltage(line, 2));
        part2 += @intCast(try maxJoltage(line, 12));
    }

    std.debug.print("Part 1: {d}\n", .{part1});
    std.debug.print("Part 2: {d}\n", .{part2});
}

fn shiftDigits(line: []u8) void {
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        line[i] -= '0';
    }
}

fn maxJoltage(bank: []u8, size: u8) !u64 {
    if (size > bank.len) {
        return error.BankTooSmall;
    }

    var bank_ = bank;
    var size_: usize = @intCast(size);
    var joltage: u64 = 0;

    while (size_ > 0) : (size_ -= 1) {
        const i = mem.indexOfMax(u8, bank_[0 .. bank_.len + 1 - size_]);
        joltage *= 10;
        joltage += @intCast(bank_[i]);
        bank_ = bank_[i + 1 ..];
    }

    return joltage;
}
