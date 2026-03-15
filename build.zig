const std = @import("std");

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

    const sensors_mod = b.addModule("sensors", .{
        .root_source_file = b.path("src/sensors/root.zig"),
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

    // Import the modules into the executable's root module so they can be used in src/main.zig.
    exe.root_module.addImport("COTILLA", cotilla_mod);
    exe.root_module.addImport("coap", coap_mod);
    exe.root_module.addImport("sensors", sensors_mod);

    b.installArtifact(exe);

    // Test artifact
    const all_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/all_tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "COTILLA", .module = cotilla_mod },
                .{ .name = "sensors", .module = coap_mod },
            },
        }),
    });

    const run_all_tests = b.addRunArtifact(all_tests);
    const test_step = b.step("test", "Run centralized tests");
    test_step.dependOn(&run_all_tests.step);
}
