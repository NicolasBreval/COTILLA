const std = @import("std");
const net = std.net;
const log = std.log.scoped(.coap);
const testing = std.testing;

/// Represents the content of a header in a CoAP message, which is 4 bytes long.
/// To ensure the correct reading of the header, we use `extern struct` to prevent Zig from reordering the fields.
/// This is because net procotols use big-endian byte order, and we want to ensure that the fields are read in the correct order without any padding or reordering by the compiler.
pub const CoapHeader = extern struct {
    first_byte: u8,
    code: u8,
    message_id: u16,

    pub fn getVersion(self: CoapHeader) u2 {
        return @intCast((self.first_byte >> 6) & 0x03);
    }
    pub fn getType(self: CoapHeader) u2 {
        return @intCast((self.first_byte >> 4) & 0x03);
    }
    pub fn getTokenLength(self: CoapHeader) u4 {
        return @intCast(self.first_byte & 0x0F);
    }
    pub fn getCode(self: CoapHeader) []const u8 {
        switch (self.code) {
            0 => return "PING/RST",
            1 => return "GET",
            2 => return "POST",
            3 => return "PUT",
            4 => return "DELETE",
            else => return "Unknown",
        }
    }
    pub fn getTypeName(self: CoapHeader) []const u8 {
        return switch (self.getType()) {
            0 => "Confirmable",
            1 => "Non-confirmable",
            2 => "Acknowledgement",
            3 => "Reset",
        };
    }
};

pub const MessageHandler = *const fn (header: CoapHeader, uri_path: []const u8, payload: []const u8) anyerror!void;

pub const ParseError = error{
    InvalidTokenLength,
    TruncatedMessage,
    InvalidOptionField,
    EmptyPayloadMarker,
    UriPathTooLong,
};

pub const ParsedMessage = struct {
    uri_path: []const u8,
    payload: []const u8,
};

fn readExtendedField(nibble: u4, packet: []const u8, cursor: *usize) ParseError!u16 {
    return switch (nibble) {
        13 => blk: {
            if (cursor.* >= packet.len) return error.TruncatedMessage;
            const value = @as(u16, packet[cursor.*]) + 13;
            cursor.* += 1;
            break :blk value;
        },
        14 => blk: {
            if (cursor.* + 2 > packet.len) return error.TruncatedMessage;
            const ext = std.mem.readInt(u16, packet[cursor.*..][0..2], .big);
            cursor.* += 2;
            break :blk ext + 269;
        },
        15 => error.InvalidOptionField,
        else => @as(u16, nibble),
    };
}

fn parseOptionsAndPayload(
    packet: []const u8,
    header: CoapHeader,
    uri_buf: []u8,
) ParseError!ParsedMessage {
    const token_len: usize = header.getTokenLength();
    if (token_len > 8) return error.InvalidTokenLength;
    if (packet.len < 4 + token_len) return error.TruncatedMessage;

    var cursor: usize = 4 + token_len;
    var current_option_number: u16 = 0;
    var uri_len: usize = 0;

    while (cursor < packet.len) {
        if (packet[cursor] == 0xFF) {
            cursor += 1;
            if (cursor == packet.len) return error.EmptyPayloadMarker;

            return .{
                .uri_path = uri_buf[0..uri_len],
                .payload = packet[cursor..],
            };
        }

        const first = packet[cursor];
        cursor += 1;

        const delta_nibble: u4 = @intCast((first >> 4) & 0x0F);
        const length_nibble: u4 = @intCast(first & 0x0F);

        const delta = try readExtendedField(delta_nibble, packet, &cursor);
        const length = try readExtendedField(length_nibble, packet, &cursor);

        current_option_number += delta;

        const option_len: usize = @intCast(length);
        if (cursor + option_len > packet.len) return error.TruncatedMessage;

        const value = packet[cursor .. cursor + option_len];
        cursor += option_len;

        // Uri-Path = opción número 11
        if (current_option_number == 11) {
            if (uri_len != 0) {
                if (uri_len >= uri_buf.len) return error.UriPathTooLong;
                uri_buf[uri_len] = '/';
                uri_len += 1;
            }

            if (uri_len + value.len > uri_buf.len) return error.UriPathTooLong;
            @memcpy(uri_buf[uri_len .. uri_len + value.len], value);
            uri_len += value.len;
        }
    }

    return .{
        .uri_path = uri_buf[0..uri_len],
        .payload = "",
    };
}

/// Starts a CoAP server that listens for incoming messages on the specified port.
pub fn startServer(port: u16, routes: *const std.StaticStringMap(MessageHandler)) !void {
    const address = try net.Address.parseIp("0.0.0.0", port);
    const sock = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM, 0);
    defer std.posix.close(sock);

    try std.posix.bind(sock, &address.any, address.getOsSockLen());
    log.info("Server started on port {d}", .{port});

    var buffer: [1024]u8 = undefined;
    var src_addr: std.posix.sockaddr = undefined;
    var src_addr_len: std.posix.socklen_t = @intCast(@sizeOf(std.posix.sockaddr));

    while (true) {
        const bytes_read = try std.posix.recvfrom(sock, &buffer, 0, &src_addr, &src_addr_len);
        if (bytes_read < 4) continue;

        const header = @as(*align(1) const CoapHeader, @ptrCast(buffer[0..4])).*;

        if (std.mem.indexOfScalar(u8, buffer[0..bytes_read], 0xFF) != null) {
            const uri_buf = if (bytes_read >= 512)
                buffer[bytes_read - 512 .. bytes_read]
            else
                buffer[0..bytes_read];

            const parsed = parseOptionsAndPayload(buffer[0..bytes_read], header, uri_buf) catch |err| {
                log.err("Failed to parse message: {}", .{err});
                continue;
            };

            log.debug("=== New message received of {d} bytes ===", .{bytes_read});
            log.debug("Version: {d}", .{header.getVersion()});
            log.debug("Type: {s}", .{header.getTypeName()});
            log.debug("Code: {s}", .{header.getCode()});
            log.debug("Message ID: {d}", .{header.message_id});
            log.debug("URI path: {s}", .{parsed.uri_path});
            log.debug("Payload: {s}", .{parsed.payload});
            log.debug("======", .{});
            if (routes.get(parsed.uri_path)) |handler| {
                try handler(header, parsed.uri_path, parsed.payload);
            } else {
                log.warn("No handler for URI path: {s}", .{parsed.uri_path});
            }
        } else {
            log.warn("Received message without payload marker", .{});
        }
    }
}

test "CoapHeader decodes version, type, and token length" {
    const header = CoapHeader{
        .first_byte = 0b01010010, // version=1, type=1 (NON), token_length=2
        .code = 1,
        .message_id = 42,
    };

    try testing.expectEqual(@as(u2, 1), header.getVersion());
    try testing.expectEqual(@as(u2, 1), header.getType());
    try testing.expectEqual(@as(u4, 2), header.getTokenLength());
}

test "CoapHeader maps request codes to names" {
    const base = CoapHeader{
        .first_byte = 0,
        .code = 0,
        .message_id = 0,
    };

    var header = base;
    header.code = 0;
    try testing.expectEqualStrings("PING/RST", header.getCode());

    header.code = 1;
    try testing.expectEqualStrings("GET", header.getCode());

    header.code = 2;
    try testing.expectEqualStrings("POST", header.getCode());

    header.code = 3;
    try testing.expectEqualStrings("PUT", header.getCode());

    header.code = 4;
    try testing.expectEqualStrings("DELETE", header.getCode());

    header.code = 99;
    try testing.expectEqualStrings("Unknown", header.getCode());
}

test "CoapHeader maps message type to names" {
    const confirmable = CoapHeader{ .first_byte = 0b01000000, .code = 0, .message_id = 0 };
    const non_confirmable = CoapHeader{ .first_byte = 0b01010000, .code = 0, .message_id = 0 };
    const acknowledgement = CoapHeader{ .first_byte = 0b01100000, .code = 0, .message_id = 0 };
    const reset = CoapHeader{ .first_byte = 0b01110000, .code = 0, .message_id = 0 };

    try testing.expectEqualStrings("Confirmable", confirmable.getTypeName());
    try testing.expectEqualStrings("Non-confirmable", non_confirmable.getTypeName());
    try testing.expectEqualStrings("Acknowledgement", acknowledgement.getTypeName());
    try testing.expectEqualStrings("Reset", reset.getTypeName());
}
