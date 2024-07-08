//Imports
const std = @import("std");
const process = std.process;
const chip8 = @import("chip8.zig");

//Declarations
const sf = struct {
    usingnamespace @import("sfml");
    usingnamespace sf.graphics;
};
const keycode = sf.window.keyboard.KeyCode;

//Constants
const WINDOW_HEIGHT = 500.0;
const WINDOW_WIDTH = 500.0;
const pairs = [_]struct { key: keycode, value: u4 }{
    .{ .key = keycode.X, .value = 0x0 },
    .{ .key = keycode.Num1, .value = 0x1 },
    .{ .key = keycode.Num2, .value = 0x2 },
    .{ .key = keycode.Num3, .value = 0x3 },
    .{ .key = keycode.Q, .value = 0x4 },
    .{ .key = keycode.W, .value = 0x5 },
    .{ .key = keycode.E, .value = 0x6 },
    .{ .key = keycode.A, .value = 0x7 },
    .{ .key = keycode.S, .value = 0x8 },
    .{ .key = keycode.D, .value = 0x9 },
    .{ .key = keycode.Z, .value = 0xA },
    .{ .key = keycode.C, .value = 0xB },
    .{ .key = keycode.Num4, .value = 0xC },
    .{ .key = keycode.R, .value = 0xD },
    .{ .key = keycode.F, .value = 0xE },
    .{ .key = keycode.V, .value = 0xF },
};

//Globals
var ch8: chip8 = chip8{};
var keymap: std.AutoHashMap(keycode, u4) = undefined;

//Functions
fn updateTexture(texture: *sf.Texture) !void {
    var image = try sf.Image.create(.{ .x = chip8.CHIP8_WIDTH, .y = chip8.CHIP8_HEIGHT }, sf.Color.Black);
    for (0..chip8.CHIP8_WIDTH) |x| {
        for (0..chip8.CHIP8_HEIGHT) |y| {
            const idx = x + y * chip8.CHIP8_WIDTH;
            if (ch8.display[idx] != 0)
                image.setPixel(.{ .x = @intCast(x), .y = @intCast(y) }, sf.Color.White);
        }
    }
    texture.updateFromImage(image, null);
}

fn loadRom(filename: []const u8) !void {
    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    const reader = file.reader();
    _ = try reader.readAll(ch8.memory[chip8.STARTING_ADDRESS..]);
}

fn initKeys(allocator: std.mem.Allocator) !void {
    keymap = std.AutoHashMap(sf.window.keyboard.KeyCode, u4).init(allocator);
    for (pairs) |pair| {
        try keymap.put(pair.key, pair.value);
    }
}

pub fn main() !void {
    var window = try sf.RenderWindow.createDefault(.{ .x = WINDOW_WIDTH, .y = WINDOW_HEIGHT }, "Chip8");
    var texture = try sf.Texture.create(.{ .x = chip8.CHIP8_WIDTH, .y = chip8.CHIP8_HEIGHT });
    var sprite = try sf.graphics.Sprite.createFromTexture(texture);
    sprite.setScale(.{ .x = WINDOW_WIDTH / @as(f32, @floatFromInt(chip8.CHIP8_WIDTH)), .y = WINDOW_HEIGHT / @as(f32, @floatFromInt(chip8.CHIP8_HEIGHT)) });
    defer window.destroy();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    ch8.init();

    var args = try process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip();
    const filename = args.next() orelse {
        std.debug.print("No ROM Given\n", .{});
        return;
    };
    try loadRom(filename);
    try initKeys(allocator);

    var clock = try sf.system.Clock.create();
    while (window.isOpen()) {
        while (clock.getElapsedTime().asSeconds() > 1.0 / 250.0) {
            _ = clock.restart();
            ch8.cycle();
        }
        if (window.pollEvent()) |event| {
            switch (event) {
                .keyPressed => |key_event| {
                    if (key_event.code == .Escape) {
                        window.close();
                    }
                    if (keymap.contains(key_event.code)) {
                        const value = keymap.get(key_event.code).?;
                        ch8.keys[value] = 1;
                    }
                },
                .keyReleased => |key_event| {
                    if (keymap.contains(key_event.code)) {
                        const value = keymap.get(key_event.code).?;
                        ch8.keys[value] = 0;
                    }
                },
                .closed => window.close(),
                else => {},
            }
        }
        try updateTexture(&texture);
        window.clear(sf.Color.Black);
        window.draw(sprite, null);
        window.display();
    }
}
