//Imports
const std = @import("std");
const random = std.Random;

//Constants
pub const STARTING_ADDRESS = 0x200;
pub const CHIP8_WIDTH = 64;
pub const CHIP8_HEIGHT = 32;
pub const FONT_SET = [_]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};
const Self = @This();

//Declarations
var prng: std.Random.Xoshiro256 = undefined;
var rand: std.Random = undefined;

memory: [1024 * 4]u8 = [_]u8{0} ** (1024 * 4),
registers: [16]u8 = [_]u8{0} ** 16,
I: u16 = 0,
delay_timer: u8 = 0,
sound_timer: u8 = 0,
pc: u16 = STARTING_ADDRESS,
sp: u8 = 0,
stack: [16]u16 = [_]u16{0} ** 16,
keys: [16]u4 = [_]u4{0} ** 16,
opcode: u16 = 0,
display: [CHIP8_WIDTH * CHIP8_HEIGHT]u8 = [_]u8{0} ** (CHIP8_WIDTH * CHIP8_HEIGHT),

inline fn println(comptime fmt: []const u8, args: anytype) void {
    const stdout = std.io.getStdOut().writer();
    stdout.print(fmt ++ "\n", args) catch unreachable;
}

pub fn init(self: *Self) void {
    prng = random.DefaultPrng.init(@truncate(@as(u128, @intCast(std.time.nanoTimestamp()))));
    rand = prng.random();
    @memcpy(self.memory[0..FONT_SET.len], &FONT_SET);
    @memset(self.memory[FONT_SET.len..], 0);
    @memset(&self.registers, 0);
    @memset(&self.stack, 0);
    @memset(&self.keys, 0);
    @memset(&self.display, 0);
}

pub fn cycle(self: *Self) void {
    var should_increment = true;

    self.opcode = (@as(u16, self.memory[self.pc]) << 0x8) | self.memory[self.pc + 1];

    const first: u4 = @intCast(self.opcode >> 0xC);
    const nnn: u12 = @intCast(self.opcode & 0x0FFF);
    const n: u4 = @intCast(self.opcode & 0x000F);
    const x: u4 = @intCast((self.opcode & 0x0F00) >> 0x8);
    const y: u4 = @intCast((self.opcode & 0x00F0) >> 0x4);
    const kk: u8 = @intCast(self.opcode & 0x00FF);

    switch (first) {
        0x0 => {
            if (self.opcode == 0x00E0) {
                for (&self.display) |*byte| {
                    byte.* = 0;
                }
            } else if (self.opcode == 0x00EE) {
                self.sp -|= 1;
                self.pc = self.stack[self.sp];
            }
        },
        0x1 => {
            self.pc = nnn;
            should_increment = false;
        },
        0x2 => {
            self.stack[self.sp] = self.pc;
            self.sp += 1;
            self.pc = nnn;
            should_increment = false;
        },
        0x3 => {
            if (self.registers[x] == kk)
                self.pc += 2;
        },
        0x4 => {
            if (self.registers[x] != kk)
                self.pc += 2;
        },
        0x5 => {
            if (self.registers[x] == self.registers[y])
                self.pc += 2;
        },
        0x6 => self.registers[x] = kk,
        0x7 => self.registers[x] +%= kk,
        0x8 => switch (n) {
            0x0 => self.registers[x] = self.registers[y],
            0x1 => self.registers[x] |= self.registers[y],
            0x2 => self.registers[x] &= self.registers[y],
            0x3 => self.registers[x] ^= self.registers[y],
            0x4 => {
                const sum: u16 = @as(u16, self.registers[x]) + self.registers[y];
                self.registers[0xF] = if (sum > 255) 1 else 0;
                self.registers[x] = @intCast(sum & 0x00FF);
            },
            0x5 => {
                self.registers[0xF] = if (self.registers[x] > self.registers[y]) 1 else 0;
                self.registers[x] -%= self.registers[y];
            },
            0x6 => {
                self.registers[0xF] = self.registers[x] & 0x1;
                self.registers[x] >>= 1;
            },
            0x7 => {
                self.registers[0xF] = if (self.registers[y] > self.registers[x]) 1 else 0;
                self.registers[x] = self.registers[y] -% self.registers[x];
            },
            0xE => {
                self.registers[0xF] = (self.registers[x] & 0x80) >> 0x7;
                self.registers[x] <<= 1;
            },
            else => {
                std.debug.print("CURRENT ALU OP: {X}\n", .{self.opcode});
            },
        },
        0x9 => if (self.registers[x] != self.registers[y]) {
            self.pc += 2;
        },
        0xA => self.I = nnn,
        0xB => {
            self.pc = nnn +% self.registers[0];
            should_increment = false;
        },
        0xC => self.registers[x] = rand.int(u8) & kk,
        0xD => {
            self.registers[0xF] = 0;
            const regx = self.registers[x];
            const regy = self.registers[y];
            const msb: u8 = 0x80;
            for (self.memory[self.I .. self.I + n], 0..) |pixel, row| {
                for (0..8) |col| {
                    if (pixel & (msb >> @intCast(col)) != 0) {
                        const tx = (regx + col) % CHIP8_WIDTH;
                        const ty = (regy + row) % CHIP8_HEIGHT;
                        const idx = tx + ty * CHIP8_WIDTH;
                        self.display[idx] ^= 1;
                        if (self.display[idx] == 0)
                            self.registers[0xF] = 1;
                    }
                }
            }
        },
        0xE => switch (kk) {
            0x9E => {
                const key_x = self.registers[x];
                if (self.keys[key_x] == 1)
                    self.pc += 2;
            },
            0xA1 => {
                const key_x = self.registers[x];
                if (self.keys[key_x] != 1)
                    self.pc += 2;
            },
            else => {},
        },
        0xF => switch (kk) {
            0x07 => self.registers[x] = self.delay_timer,
            0x0A => {
                var key_pressed = false;
                for (self.keys, 0..) |key, i| {
                    if (key != 0) {
                        self.registers[x] = @intCast(i);
                        key_pressed = true;
                        break;
                    }
                }
                if (!key_pressed)
                    return;
            },
            0x15 => self.delay_timer = self.registers[x],
            0x18 => self.sound_timer = self.registers[x],
            0x1E => self.I +%= self.registers[x],
            0x29 => self.I = self.registers[x] * 0x5,
            0x33 => {
                const num = self.registers[x];
                self.memory[self.I] = num / 100;
                self.memory[self.I + 1] = (num / 10) % 10;
                self.memory[self.I + 2] = num % 10;
            },
            0x55 => for (self.memory[self.I .. self.I + @as(u5, x) + 1], 0..) |*byte, i| {
                byte.* = self.registers[i];
            },
            0x65 => for (self.registers[0 .. @as(u5, x) + 1], 0..) |*register, i| {
                register.* = self.memory[self.I + i];
            },
            else => {
                std.debug.print("CURRENT OP: {X}\n", .{self.opcode});
            },
        },
    }
    if (should_increment)
        self.pc += 2;
    self.delay_timer -|= 1;
    self.sound_timer -|= 1;
}
