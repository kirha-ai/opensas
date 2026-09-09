//! WASM entry — the web-demo build (`zig build wasm`). A reactor module (no
//! main): JS calls `alloc` to place the SAS source in linear memory, then `run`,
//! then reads program output via `outPtr`/`outLen` and rendered diagnostics via
//! `logPtr`/`logLen`. `run` returns the CLI exit-code contract (0/1/2, D-009) —
//! and, per D-009a, the rc an `ABORT ABEND n` / `ABORT RETURN n` chose, which is
//! deliberately outside {0,1,2}. That i32 return IS the exit-code channel on this
//! surface; there is no process to exit, so a caller must route on it exactly as
//! a shell routes on `$?` (see web/index.html's status line).
//!
//! Reuses main.zig's `interpret` with `io = null` — the pure in-memory path the
//! unit tests already exercise — so there is no filesystem to shim. The stray
//! `std.debug.print` fail-loud lines (UNSUPPORTED:/ERROR:) go to WASI fd 2,
//! which web/index.html's ~20-line shim captures into the log pane.
//!
//! ponytail: one global arena reset per run, no datasets persist across runs —
//! the demo is one program in, one listing out. Sessions if anyone asks.

const std = @import("std");
const cli = @import("main.zig");
const sas = @import("sas");

var arena_state = std.heap.ArenaAllocator.init(std.heap.wasm_allocator);
var g_out: []const u8 = "";
var g_log: []const u8 = "";

export fn alloc(len: usize) [*]u8 {
    const buf = arena_state.allocator().alloc(u8, len) catch @trap();
    return buf.ptr;
}

export fn run(src_ptr: [*]const u8, src_len: usize) i32 {
    const a = arena_state.allocator();
    // dupe the source out before reset? No — the source was alloc'd in this
    // arena by JS; run() must not reset first. Reset happens at the END, after
    // copying results out... but results live in the arena too. Keep it lazy:
    // never reset, let the arena grow. A demo tab runs a handful of programs.
    const src = src_ptr[0..src_len];

    // BUG-fmterrorneverreset: the per-run reset of every process-global lives in
    // `cli.interpret` — including `cli.g_failed`, which this function used to clear
    // itself. That private copy of main's reset list is exactly how `g_fmt_error`
    // and `g_nofmterr` came to leak across programs here: one list, one place.
    var diags = sas.diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    cli.interpret(a, &out, &diags, src, null) catch |e| {
        if (!diags.hasErrors()) {
            g_out = out.items;
            g_log = std.fmt.allocPrint(a, "ERROR: {t}\n", .{e}) catch "ERROR\n";
            return 2;
        }
    };
    g_out = out.items;
    g_log = diags.render() catch "";
    // BUG-wasmignoresabortrc: this used to open-code `diag.exitCode` over the two
    // D-009 signals, which silently DROPPED the D-009a line that sits above them
    // in `main` — so `abort return 3` came back 1 here and 3 on the CLI. The rc is
    // now the single shared `processExitCode`, abort override included, so the two
    // surfaces cannot disagree again. The channel carries it: `run`'s i32 return
    // holds every u8 an ABORT can name, no widening or clamping needed.
    return cli.processExitCode(&diags);
}

export fn outPtr() [*]const u8 {
    return g_out.ptr;
}
export fn outLen() usize {
    return g_out.len;
}
export fn logPtr() [*]const u8 {
    return g_log.ptr;
}
export fn logLen() usize {
    return g_log.len;
}
