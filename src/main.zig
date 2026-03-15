const std = @import("std");
const coap = @import("coap");

fn tempHandler(header: coap.CoapHeader, uri_path: []const u8, payload: []const u8) !void {
    _ = header;
    _ = uri_path;
    _ = payload;
}

const routes = std.StaticStringMap(coap.MessageHandler).initComptime(.{.{ "00001", tempHandler }});

pub fn main() !void {
    try coap.startServer(5683, &routes);
}
