const std = @import("std");
const testing = std.testing;

const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lauxlib.h");
    @cInclude("lualib.h");
});

extern fn luaL_openselectedlibs(L: ?*c.lua_State, load: c_int, preload: c_int) void;

/// Errors that can occur during Lua script loading, validation, and execution.
pub const BaseScriptError = error{
    LuaInitFailed,
    ScriptLoadFailed,
    ScriptRuntimeFailed,
    OutOfMemory,
};

/// Errors related to validating the Lua script contract (checking for required functions and their arity).
pub const ContractError = BaseScriptError || error{
    MissingAccumulate,
    MissingFinalize,
    InvalidAccumulateArity,
    InvalidFinalizeArity,
};

/// Errors that can occur during script function execution, including missing functions and runtime errors.
pub const ExecuteError = BaseScriptError || error{
    MissingFunction,
};

/// Represents a reference to a Lua value stored in the registry, allowing it to be accessed across multiple function calls.
pub const LuaReference = struct {
    registry_index: c_int,
};

/// Represents an argument that can be passed to a Lua function, supporting various Lua types
/// including nil, boolean, integer, number, string, and references to Lua values.
pub const LuaArgument = union(enum) {
    nil,
    boolean: bool,
    integer: i64,
    number: f64,
    string: []const u8,
    reference: LuaReference,
};

/// Represents the result of a Lua function call, supporting various Lua types
/// including nil, boolean, integer, number, string, and references to Lua values.
pub const LuaResult = union(enum) {
    nil,
    boolean: bool,
    integer: i64,
    number: f64,
    string: []u8,
    reference: LuaReference,

    /// Deinitializes the LuaResult by freeing any allocated resources, such as strings.
    pub fn deinit(self: LuaResult, allocator: std.mem.Allocator) void {
        switch (self) {
            .string => |value| allocator.free(value),
            else => {},
        }
    }
};

/// A wrapper around the Lua state that provides methods for loading scripts, calling functions, and managing references.
pub const ScriptEngine = struct {
    /// The allocator used for managing memory for strings and other resources.
    allocator: std.mem.Allocator,
    /// The Lua state pointer, representing the execution context of the Lua interpreter.
    L: *c.lua_State,

    /// Initializes the ScriptEngine by creating a new Lua state and loading the specified script.
    pub fn init(script_path: []const u8, allocator: std.mem.Allocator) ExecuteError!ScriptEngine {
        return .{
            .allocator = allocator,
            .L = try createLuaState(script_path, allocator),
        };
    }

    /// Deinitializes the ScriptEngine by closing the Lua state and freeing any associated resources.
    pub fn deinit(self: *ScriptEngine) void {
        c.lua_close(self.L);
    }

    /// Calls a Lua function with the specified name and arguments, returning the result or an error if the function is missing or if execution fails.
    pub fn callFunction(self: *ScriptEngine, function_name: []const u8, args: []const LuaArgument) ExecuteError!LuaResult {
        const function_name_z = self.allocator.dupeZ(u8, function_name) catch return error.OutOfMemory;
        defer self.allocator.free(function_name_z);

        _ = c.lua_getglobal(self.L, function_name_z.ptr);
        if (!c.lua_isfunction(self.L, -1)) {
            c.lua_pop(self.L, 1);
            return error.MissingFunction;
        }

        for (args) |arg| {
            self.pushArgument(arg);
        }

        if (c.lua_pcallk(self.L, @intCast(args.len), 1, 0, 0, null) != c.LUA_OK) {
            logLuaError(self.L, "executing function failed");
            return error.ScriptRuntimeFailed;
        }

        return try self.readResult();
    }

    /// Releases a Lua reference by unreferencing it from the Lua registry, allowing the Lua garbage collector to reclaim the associated value if there are no other references to it.
    pub fn releaseReference(self: *ScriptEngine, reference: LuaReference) void {
        if (reference.registry_index == c.LUA_NOREF or reference.registry_index == c.LUA_REFNIL) {
            return;
        }

        c.luaL_unref(self.L, c.LUA_REGISTRYINDEX, reference.registry_index);
    }

    /// Pushes a LuaArgument onto the Lua stack, converting it to the appropriate Lua type based on its variant.
    fn pushArgument(self: *ScriptEngine, arg: LuaArgument) void {
        switch (arg) {
            .nil => c.lua_pushnil(self.L),
            .boolean => |value| c.lua_pushboolean(self.L, if (value) 1 else 0),
            .integer => |value| c.lua_pushinteger(self.L, @intCast(value)),
            .number => |value| c.lua_pushnumber(self.L, @floatCast(value)),
            .string => |value| _ = c.lua_pushlstring(self.L, value.ptr, value.len),
            .reference => |reference| _ = c.lua_rawgeti(self.L, c.LUA_REGISTRYINDEX, reference.registry_index),
        }
    }

    /// Reads the result of a Lua function call from the top of the Lua stack, converting it to a LuaResult based on its type and popping it from the stack.
    fn readResult(self: *ScriptEngine) ExecuteError!LuaResult {
        switch (c.lua_type(self.L, -1)) {
            c.LUA_TNIL => {
                c.lua_pop(self.L, 1);
                return .nil;
            },
            c.LUA_TBOOLEAN => {
                const value = c.lua_toboolean(self.L, -1) != 0;
                c.lua_pop(self.L, 1);
                return .{ .boolean = value };
            },
            c.LUA_TNUMBER => {
                if (c.lua_isinteger(self.L, -1) != 0) {
                    const value: i64 = @intCast(c.lua_tointegerx(self.L, -1, null));
                    c.lua_pop(self.L, 1);
                    return .{ .integer = value };
                }

                const value: f64 = @floatCast(c.lua_tonumberx(self.L, -1, null));
                c.lua_pop(self.L, 1);
                return .{ .number = value };
            },
            c.LUA_TSTRING => {
                var len: usize = 0;
                const ptr = c.lua_tolstring(self.L, -1, &len) orelse unreachable;
                defer c.lua_pop(self.L, 1);
                const value = self.allocator.dupe(u8, ptr[0..len]) catch return error.OutOfMemory;
                return .{ .string = value };
            },
            else => {
                const registry_index = c.luaL_ref(self.L, c.LUA_REGISTRYINDEX);
                return .{ .reference = .{ .registry_index = registry_index } };
            },
        }
    }
};

/// Executes a specified function from a Lua script with the given arguments, returning the result or an error if the function is missing or if execution fails.
pub fn executeScriptFunction(
    script_path: []const u8,
    function_name: []const u8,
    args: []const LuaArgument,
    allocator: std.mem.Allocator,
) ExecuteError!LuaResult {
    var engine = try ScriptEngine.init(script_path, allocator);
    defer engine.deinit();

    return try engine.callFunction(function_name, args);
}

/// Checks if a Lua script at the given path satisfies the contract of having `accumulate` and `finalize` functions.
/// Returns an error if the script is invalid or if there was an issue loading or executing it.
pub fn validateScriptContract(script_path: []const u8, allocator: std.mem.Allocator) ContractError!void {
    const L = try createLuaState(script_path, allocator);
    defer c.lua_close(L);

    try requireGlobalFunctionWithArity(L, "accumulate", 2, error.MissingAccumulate, error.InvalidAccumulateArity);
    try requireGlobalFunctionWithArity(L, "finalize", 2, error.MissingFinalize, error.InvalidFinalizeArity);
}

/// Creates a new Lua state, loads the script from the specified path, and executes it to initialize the Lua environment.
fn createLuaState(script_path: []const u8, allocator: std.mem.Allocator) BaseScriptError!*c.lua_State {
    const L = c.luaL_newstate() orelse return error.LuaInitFailed;
    errdefer c.lua_close(L);

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

    return L;
}

// Helper function to check if a global function exists and has the expected number of parameters (arity).
fn requireGlobalFunctionWithArity(
    L: *c.lua_State,
    function_name: [:0]const u8,
    expected_params: c_int,
    missing_err: ContractError,
    invalid_arity_err: ContractError,
) ContractError!void {
    _ = c.lua_getglobal(L, function_name.ptr);

    if (!c.lua_isfunction(L, -1)) {
        c.lua_pop(L, 1);
        return missing_err;
    }

    var dbg_info: c.lua_Debug = undefined;
    if (c.lua_getinfo(L, ">u", &dbg_info) == 0) {
        return invalid_arity_err;
    }

    if (@as(c_int, @intCast(dbg_info.nparams)) != expected_params or dbg_info.isvararg != 0) {
        return invalid_arity_err;
    }
}

/// Logs the error message from the top of the Lua stack along with a custom context message.
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

test "Script has invalid finalize arity" {
    const allocator = std.heap.page_allocator;
    const err = validateScriptContract("src/scripting/fixtures/invalid_arity_script.lua", allocator);
    try testing.expectEqual(ContractError.InvalidFinalizeArity, err);
}

test "can execute a script function with parameters" {
    const allocator = std.testing.allocator;

    var engine = try ScriptEngine.init("src/scripting/fixtures/valid_script.lua", allocator);
    defer engine.deinit();

    const first_result = try engine.callFunction("accumulate", &.{ .nil, .{ .number = 1.5 } });
    const first_state = switch (first_result) {
        .reference => |reference| reference,
        else => return error.TestUnexpectedResult,
    };

    const second_result = try engine.callFunction("accumulate", &.{ .{ .reference = first_state }, .{ .number = 2.5 } });
    engine.releaseReference(first_state);
    const second_state = switch (second_result) {
        .reference => |reference| reference,
        else => return error.TestUnexpectedResult,
    };
    defer engine.releaseReference(second_state);

    const final_result = try engine.callFunction("finalize", &.{ .{ .reference = second_state }, .nil });
    defer final_result.deinit(allocator);

    switch (final_result) {
        .number => |value| try testing.expectApproxEqAbs(@as(f64, 2.0), value, 0.000_001),
        .integer => |value| try testing.expectEqual(@as(i64, 2), value),
        else => return error.TestUnexpectedResult,
    }
}

test "returns MissingFunction when the script function does not exist" {
    const allocator = std.testing.allocator;

    var engine = try ScriptEngine.init("src/scripting/fixtures/valid_script.lua", allocator);
    defer engine.deinit();

    try testing.expectError(error.MissingFunction, engine.callFunction("unknown_function", &.{}));
}
