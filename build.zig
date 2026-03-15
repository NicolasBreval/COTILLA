const std = @import("std");

fn addEmbeddedDeps(b: *std.Build, artifact: *std.Build.Step.Compile) void {
    artifact.linkLibC();
    artifact.addIncludePath(b.path("third_party/sqlite"));
    artifact.addCSourceFile(.{
        .file = b.path("third_party/sqlite/sqlite3.c"),
        .flags = &.{
            "-std=c11",
            "-DSQLITE_THREADSAFE=1",
            "-DSQLITE_OMIT_LOAD_EXTENSION",
        },
    });

    artifact.addIncludePath(b.path("third_party/lua"));
    artifact.addCSourceFiles(.{
        .root = b.path("third_party/lua"),
        .files = &.{
            "lapi.c",
            "lauxlib.c",
            "lbaselib.c",
            "lcode.c",
            "lcorolib.c",
            "lctype.c",
            "ldblib.c",
            "ldebug.c",
            "ldo.c",
            "ldump.c",
            "lfunc.c",
            "lgc.c",
            "linit.c",
            "liolib.c",
            "llex.c",
            "lmathlib.c",
            "lmem.c",
            "loadlib.c",
            "lobject.c",
            "lopcodes.c",
            "loslib.c",
            "lparser.c",
            "lstate.c",
            "lstring.c",
            "lstrlib.c",
            "ltable.c",
            "ltablib.c",
            "ltm.c",
            "lundump.c",
            "lutf8lib.c",
            "lvm.c",
            "lzio.c",
        },
        .flags = &.{"-std=c99"},
    });
}

pub fn build(b: *std.Build) void {
    // Standard target and optimization options are available for all modules and artifacts.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options are available for all modules and artifacts, but you can also specify them per-module or per-artifact.
    const optimize = b.standardOptimizeOption(.{});

    // Main module of application
    const cotilla_mod = b.addModule("COTILLA", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // Module with all logic for coap
    const coap_mod = b.addModule("coap", .{
        .root_source_file = b.path("src/coap/root.zig"),
        .target = target,
    });

    // Module with all logic for scripting
    const scripting_mod = b.addModule("scripting", .{
        .root_source_file = b.path("src/scripting/root.zig"),
        .target = target,
    });

    // Executable artifact
    const exe = b.addExecutable(.{
        .name = "COTILLA",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    addEmbeddedDeps(b, exe);

    // Import the modules into the executable's root module so they can be used in src/main.zig.
    exe.root_module.addImport("COTILLA", cotilla_mod);
    exe.root_module.addImport("coap", coap_mod);
    exe.root_module.addImport("scripting", scripting_mod);

    b.installArtifact(exe);

    // CoAP test artifact
    const coap_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/coap/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_coap_tests = b.addRunArtifact(coap_tests);
    run_coap_tests.setCwd(b.path("."));
    const coap_test_step = b.step("test-coap", "Run CoAP module tests");
    coap_test_step.dependOn(&run_coap_tests.step);

    const scripting_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/scripting/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    addEmbeddedDeps(b, scripting_tests);

    const run_scripting_tests = b.addRunArtifact(scripting_tests);
    run_scripting_tests.setCwd(b.path("."));
    const scripting_test_step = b.step("test-scripting", "Run scripting module tests");
    scripting_test_step.dependOn(&run_scripting_tests.step);

    const test_step = b.step("test", "Run centralized tests");
    test_step.dependOn(&run_coap_tests.step);
    test_step.dependOn(&run_scripting_tests.step);
}
