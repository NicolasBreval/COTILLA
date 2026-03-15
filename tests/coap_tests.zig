const std = @import("std");
const testing = std.testing;
const coap = @import("coap");

test "CoapHeader decodes version, type, and token length" {
    const header = coap.CoapHeader{
        .first_byte = 0b01010010, // version=1, type=1 (NON), token_length=2
        .code = 1,
        .message_id = 42,
    };

    try testing.expectEqual(@as(u2, 1), header.getVersion());
    try testing.expectEqual(@as(u2, 1), header.getType());
    try testing.expectEqual(@as(u4, 2), header.getTokenLength());
}

test "CoapHeader maps request codes to names" {
    const base = coap.CoapHeader{
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
    const confirmable = coap.CoapHeader{ .first_byte = 0b01000000, .code = 0, .message_id = 0 };
    const non_confirmable = coap.CoapHeader{ .first_byte = 0b01010000, .code = 0, .message_id = 0 };
    const acknowledgement = coap.CoapHeader{ .first_byte = 0b01100000, .code = 0, .message_id = 0 };
    const reset = coap.CoapHeader{ .first_byte = 0b01110000, .code = 0, .message_id = 0 };

    try testing.expectEqualStrings("Confirmable", confirmable.getTypeName());
    try testing.expectEqualStrings("Non-confirmable", non_confirmable.getTypeName());
    try testing.expectEqualStrings("Acknowledgement", acknowledgement.getTypeName());
    try testing.expectEqualStrings("Reset", reset.getTypeName());
}
