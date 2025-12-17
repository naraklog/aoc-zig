const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) !void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const utils_mod = b.addModule("utils", .{
        .root_source_file = b.path("src/utils.zig"),
        .target = target,
    });

    const days = &[_][]const u8{
        "day01",
    };

    var buf: [50]u8 = undefined;
    const has_hyperfine = try findProgram(b.allocator, "hyperfine");
    const has_uv = try findProgram(b.allocator, "uv");

    for (days) |day| {
        const zig_file = try std.fmt.bufPrint(&buf, "src/{s}/main.zig", .{day});

        const exe = b.addExecutable(.{ .name = day, .root_module = b.createModule(.{ .root_source_file = b.path(zig_file), .target = target, .optimize = optimize, .imports = &.{
            .{ .name = "utils", .module = utils_mod },
        } }) });

        b.installArtifact(exe);

        // Create the run step
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        // Create the run step
        const run_step_name = try std.fmt.bufPrint(&buf, "run-{s}", .{day});
        const run_step = b.step(run_step_name, "Run the zig solution");
        run_step.dependOn(&run_cmd.step);

        // Create the bench step
        const bench_step_name = try std.fmt.bufPrint(&buf, "bench-{s}", .{day});
        const bench_step = b.step(bench_step_name, "Benchmark the zig solution against baseline");
        bench_step.dependOn(b.getInstallStep());
        if (has_hyperfine and has_uv) {
            var bin_buf: [50]u8 = undefined;
            const zig_bin_path = try std.fmt.bufPrint(&bin_buf, "zig-out/bin/{s}", .{day});
            var mod_buf: [50]u8 = undefined;
            const py_module = try std.fmt.bufPrint(&mod_buf, "src.{s}.main", .{day});
            var py_buf: [50]u8 = undefined;
            const py_cmd = try std.fmt.bufPrint(&py_buf, "uv run -m {s}", .{py_module});

            // Run hyperfine
            const bench_cmd = b.addSystemCommand(&.{
                "hyperfine",
                "--warmup",
                "3",
                "--shell",
                "none",
                zig_bin_path,
                py_cmd,
            });
            bench_step.dependOn(&bench_cmd.step);
        } else {
            const error_cmd = b.addSystemCommand(&.{
                "echo",
                "hyperfine or uv not found",
                "exit",
                "1",
            });
            bench_step.dependOn(&error_cmd.step);
        }

        // Create the test step
        const exe_tests = b.addTest(.{
            .root_module = exe.root_module,
        });

        const run_exe_tests = b.addRunArtifact(exe_tests);
        const test_step_name = try std.fmt.bufPrint(&buf, "test-{s}", .{day});
        const test_step = b.step(test_step_name, "Run the zig tests");
        test_step.dependOn(&run_exe_tests.step);
    }
}

fn findProgram(alloc: std.mem.Allocator, program: []const u8) !bool {
    const child = std.process.Child;
    const argv = [_][]const u8{ "which", program };

    const proc = try child.run(.{
        .argv = &argv,
        .allocator = alloc,
    });

    defer alloc.free(proc.stdout);
    defer alloc.free(proc.stderr);

    if (proc.term.Exited == 0) {
        return true;
    }
    return false;
}
