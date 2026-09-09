const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
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
    // On macOS libSystem is always the syscall layer anyway; linking it gives
    // %SYSGET a real getenv (macro.zig envValue). Linux release binaries stay
    // libc-free (no glibc versioning) — they read /proc/self/environ instead.
    const native_libc: ?bool = if (target.result.os.tag == .macos) true else null;
    const mod = b.addModule("sas", .{
        .link_libc = native_libc,
        // The root source file is the "entry point" of this module. Users of
        // this module will only be able to access public declarations contained
        // in this file, which means that if you have declarations that you
        // intend to expose to consumers that were defined in other files part
        // of this module, you will have to make sure to re-export them from
        // the root file.
        .root_source_file = b.path("src/root.zig"),
        // Later on we'll use this module as the root module of a test executable
        // which requires us to specify a target.
        .target = target,
    });

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    const exe = b.addExecutable(.{
        .name = "sas",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (e.g. firmware for embedded devices).
            .target = target,
            .optimize = optimize,
            // List of modules available for import in source files part of the
            // root module.
            .imports = &.{
                // Here "sas" is the name you will use in your source code to
                // import this module (e.g. `@import("sas")`). The name is
                // repeated because you are allowed to rename your imports, which
                // can be extremely useful in case of collisions (which can happen
                // importing modules from different packages).
                .{ .name = "sas", .module = mod },
            },
        }),
    });

    // 2000-deep statement nesting (pe.Parser.max_depth) in a Debug build
    // overflows the default 8MB main stack BEFORE the parser's loud guard
    // trips (BUG-stmtnest-deepguard). Size the stack so the ceiling is always
    // the guard, never the guard page.
    const parser_stack: u64 = 64 << 20;
    exe.stack_size = parser_stack;

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    mod_tests.stack_size = parser_stack;

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    exe_tests.stack_size = parser_stack;

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Conformance corpus: `zig build corpus` runs the interpreter over every
    // tests/corpus/*.sas and prints P/Q passing (see manager.md §5), and a
    // fixture may pin the interpreter's exit code with `expect-rc: N`
    // (tests/fixture_rc.zig). It exits NON-ZERO when any fixture fails
    // (BUG-nofixturepinsrc): it used to always exit 0, so `zig build test &&
    // zig build corpus` chained straight past a red corpus.
    const corpus_runner = b.addExecutable(.{
        .name = "corpus_runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/corpus_runner.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_corpus = b.addRunArtifact(corpus_runner);
    run_corpus.addArtifactArg(exe); // argv[1] = built sas binary (also a build dep)
    run_corpus.addDirectoryArg(b.path("tests/corpus")); // argv[2] = corpus dir
    const corpus_step = b.step("corpus", "Run the conformance corpus");
    corpus_step.dependOn(&run_corpus.step);

    // The runner's own unit tests (the diff logic) ride the normal test gate.
    const corpus_tests = b.addTest(.{ .root_module = corpus_runner.root_module });
    const run_corpus_tests = b.addRunArtifact(corpus_tests);
    test_step.dependOn(&run_corpus_tests.step);

    // Program fixtures: `zig build programs` runs the interpreter over every
    // tests/programs/<name>/program.sas and structural-diffs its output CSVs
    // against expected/. Same gate rules as `corpus`: reports P/Q, honours
    // `expect-rc:`, exits non-zero on any failure.
    const programs_runner = b.addExecutable(.{
        .name = "programs_runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/programs_runner.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_programs = b.addRunArtifact(programs_runner);
    run_programs.addArtifactArg(exe); // argv[1] = built sas binary (also a build dep)
    run_programs.addDirectoryArg(b.path("tests/programs")); // argv[2] = programs dir
    const programs_step = b.step("programs", "Run the program fixtures");
    programs_step.dependOn(&run_programs.step);

    const programs_tests = b.addTest(.{ .root_module = programs_runner.root_module });
    const run_programs_tests = b.addRunArtifact(programs_tests);
    test_step.dependOn(&run_programs_tests.step);

    // Web demo: `zig build wasm` compiles the interpreter to wasm32-wasi (a
    // reactor — no main; wasm.zig exports alloc/run/outPtr/…) and drops
    // web/sas.wasm next to web/index.html. Serve `web/` statically to demo.
    // wasi (not freestanding) so the fail-loud std.debug.print paths keep
    // working — index.html shims fd_write in ~20 lines of JS.
    const wasm_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .wasi });
    const wasm = b.addExecutable(.{
        .name = "sas",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wasm.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
            .link_libc = true, // wasi-libc: clock_gettime for DATE()/TIME()
            .imports = &.{
                // `mod` above is pinned to the native target; the wasm build
                // needs its own instance of the sas module.
                .{ .name = "sas", .module = b.createModule(.{
                    .root_source_file = b.path("src/root.zig"),
                    .target = wasm_target,
                    .optimize = .ReleaseSmall,
                    .link_libc = true,
                }) },
            },
        }),
    });
    wasm.entry = .disabled;
    wasm.rdynamic = true; // keep the `export fn`s visible
    const wasm_step = b.step("wasm", "Build web/sas.wasm for the web demo");
    wasm_step.dependOn(&b.addInstallFile(wasm.getEmittedBin(), "../web/sas.wasm").step);
    // Merge gate: `zig build test` also COMPILES the wasm target (no install),
    // so a native-only-valid change (u6-shift on usize, threaded allocator)
    // can't land green and break the web demo.
    test_step.dependOn(&wasm.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
