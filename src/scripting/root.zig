const std = @import("std");
const testing = std.testing;

const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lauxlib.h");
    @cInclude("lualib.h");
});

extern fn luaL_openselectedlibs(L: ?*c.lua_State, load: c_int, preload: c_int) void;

pub const ContractError = error{
    LuaInitFailed,
    ScriptLoadFailed,
    ScriptRuntimeFailed,
    MissingAccumulate,
    MissingFinalize,
    OutOfMemory,
};

/// Minimal example: validates only the script shape.
/// Required globals:
/// - accumulate(state, measure)
/// - finalize(state)
pub fn validateScriptContract(script_path: []const u8, allocator: std.mem.Allocator) ContractError!void {
    const L = c.luaL_newstate() orelse return error.LuaInitFailed;
    defer c.lua_close(L);

    luaL_openselectedlibs(L, ~@as(c_int, 0), 0);

    const script_path_z = allocator.dupeZ(u8, script_path) catch return error.OutOfMemory;
    defer allocator.free(script_path_z);

    if (c.luaL_loadfilex(L, script_path_z.ptr, null) != c.LUA_OK) {
        logLuaError(L, "loading script failed");
        return error.ScriptLoadFailed;
    }

    if (c.lua_pcallk(L, 0, 0, 0, 0, null) != c.LUA_OK) {
        logLuaError(L, "executing script failed");
        return error.ScriptRuntimeFailed;
    }

    try requireGlobalFunction(L, "accumulate", error.MissingAccumulate);
    try requireGlobalFunction(L, "finalize", error.MissingFinalize);
}

fn requireGlobalFunction(L: *c.lua_State, function_name: [:0]const u8, err: ContractError) ContractError!void {
    _ = c.lua_getglobal(L, function_name.ptr);
    defer c.lua_pop(L, 1);

    if (!c.lua_isfunction(L, -1)) {
        return err;
    }
}

fn logLuaError(L: *c.lua_State, context: []const u8) void {
    const msg_ptr = c.lua_tolstring(L, -1, null);
    if (msg_ptr != null) {
        const ptr = msg_ptr.?;
        const msg = std.mem.span(ptr);
        std.log.err("lua: {s}: {s}", .{ context, msg });
    } else {
        std.log.err("lua: {s}", .{context});
    }
    c.lua_pop(L, 1);
}

test "Script does not contains the required functions" {
    const allocator = std.heap.page_allocator;
    const err = validateScriptContract("src/scripting/fixtures/invalid_script.lua", allocator);
    try testing.expectEqual(ContractError.MissingAccumulate, err);
}

test "Script is valid" {
    const allocator = std.heap.page_allocator;
    try validateScriptContract("src/scripting/fixtures/valid_script.lua", allocator);
}
