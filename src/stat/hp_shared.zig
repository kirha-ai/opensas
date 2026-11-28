//! Shared single-machine contract of the SAS/STAT high-performance procedures,
//! SAS/STAT 15.4 Chapter 21 physical pp.555-558 (STAT-HP-001).
//!
//! - Single-machine mode (p.555): every HP procedure runs multithreaded on the
//!   client. opensas computes on ONE thread, so "Number of Threads" is the
//!   truthful 1, never the reference machine's CPU count.
//! - Single-machine data access (p.556): input is read through Base SAS, which
//!   the Data Access Information table reports as engine V9, path On Client.
//! - PERFORMANCE (pp.557-558): NTHREADS=1 (alias THREADS=1) requests exactly
//!   what opensas does and is accepted. Every other thread count, BPC= and
//!   DETAILS belong to STAT-HP-002; distributed / alongside-the-database
//!   execution options (SAS High-Performance Analytics grid) are an execution
//!   mode opensas does not have. All of those are D-009 gaps (rc 2) raised
//!   before any listing text, never silently ignored.
//! - Output data sets (p.556) and formatted levels / FMTLIBXML= (pp.556-557)
//!   are enforced by each procedure: until its OUTPUT / FORMAT ticket lands
//!   the procedure gaps them, so no partially-formatted level or full-copy
//!   output data set can be produced.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;

/// The PERFORMANCE settings opensas honours.
pub const Performance = struct {
    nthreads: ?u32 = null,
};

/// PERFORMANCE options of the SAS High-Performance Analytics distributed and
/// alongside-the-database modes (SAS 9.4 HPA documentation). Valid SAS, but an
/// execution mode opensas does not provide.
const distributed_options = [_][]const u8{
    "nodes",       "host",      "gridhost",      "install", "installloc", "gridmode", "mode",
    "timeout",     "gridtimeout", "commit",     "dataserver", "griddataserver", "lasrserver", "lasr",
};

fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}

fn lineOf(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else 0;
}

/// Parse one PERFORMANCE statement. `t[start]` is the PERFORMANCE keyword and
/// `t[end]` its semicolon. Repeated statements are parsed independently by the
/// caller; the last NTHREADS= wins as for other procedure options.
pub fn parsePerformance(diags: *diag.Diagnostics, comptime proc_name: []const u8, t: []const lex.Token, start: usize, end: usize, perf: *Performance) diag.Error!void {
    var i = start + 1;
    while (i < end) {
        if (t[i].tag != .name) return diags.fail(error.ParseError, lineOf(t, i), "PROC " ++ proc_name ++ ": invalid PERFORMANCE option {s}", .{t[i].text});
        const word = t[i].text;
        if (eq(word, "nthreads") or eq(word, "threads")) {
            if (i + 2 > end or t[i + 1].tag != .eq or t[i + 2].tag != .number)
                return diags.fail(error.ParseError, lineOf(t, i), "PROC " ++ proc_name ++ ": PERFORMANCE {s}= requires a number", .{word});
            const v = std.fmt.parseFloat(f64, t[i + 2].text) catch
                return diags.fail(error.ParseError, t[i + 2].line, "PROC " ++ proc_name ++ ": invalid PERFORMANCE {s}= value {s}", .{ word, t[i + 2].text });
            // p.558: n is at most 256; opensas runs one thread, so only the
            // single-thread request is honoured truthfully.
            if (v != 1) return proc.failGap(diags, t[i + 2].line, "PROC " ++ proc_name ++ ": PERFORMANCE {s}={s} is not implemented (opensas computes on one thread; thread-count settings: STAT-HP-002)", .{ word, t[i + 2].text });
            perf.nthreads = 1;
            i += 3;
        } else if (eq(word, "details")) {
            return proc.failGap(diags, t[i].line, "PROC " ++ proc_name ++ ": PERFORMANCE DETAILS (procedure task timing) is not implemented (STAT-HP-002)", .{});
        } else if (eq(word, "bpc")) {
            return proc.failGap(diags, t[i].line, "PROC " ++ proc_name ++ ": PERFORMANCE BPC= is not implemented (STAT-HP-002)", .{});
        } else if (oneOf(word, &distributed_options)) {
            return proc.failGap(diags, t[i].line, "PROC " ++ proc_name ++ ": PERFORMANCE {s}= requests a distributed execution mode; opensas runs only in single-machine mode", .{word});
        } else return diags.fail(error.ParseError, t[i].line, "PROC " ++ proc_name ++ ": invalid PERFORMANCE option {s}", .{word});
    }
}

/// The single-machine log note every HP procedure writes (p.555).
pub fn noteSingleMachine(diags: *diag.Diagnostics, comptime proc_name: []const u8) !void {
    try diags.note(0, "The " ++ proc_name ++ " procedure is executing in single-machine mode.", .{});
}

/// The Performance Information table as PROC HPREG, HPGENSELECT, HPLMIXED and
/// HPNLMOD print it (verified against their SAS reference listings), followed
/// by the two blank lines before the next table.
pub fn performanceInfo(a: A, out: *Out) !void {
    try out.appendSlice(a, "      Performance Information\n\nExecution Mode       Single-Machine\nNumber of Threads    1             \n\n\n");
}

/// The Data Access Information table for one input data set read through Base
/// SAS on the client (p.556). `data` is the upper-cased two-level name.
pub fn dataAccessInfo(a: A, out: *Out, data: []const u8) !void {
    const dw = @max(4, data.len);
    const width = dw + 32;
    const head = "Data Access Information";
    if (width > head.len) try out.appendNTimes(a, ' ', (width - head.len) / 2);
    try out.appendSlice(a, head ++ "\n \n");
    try out.appendSlice(a, "Data");
    try out.appendNTimes(a, ' ', dw - 4);
    try out.appendSlice(a, "    Engine    Role     Path\n\n");
    try out.appendSlice(a, data);
    try out.appendNTimes(a, ' ', dw - data.len);
    try out.appendSlice(a, "    V9        Input    On Client\n");
}

test "STAT-HP-001 PERFORMANCE NTHREADS=1 accepted, other modes gap" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const ar = arena.allocator();
    const cases = [_]struct { src: []const u8, ok: bool, gap: bool }{
        .{ .src = "performance nthreads=1;", .ok = true, .gap = false },
        .{ .src = "performance threads=1;", .ok = true, .gap = false },
        .{ .src = "performance;", .ok = true, .gap = false },
        .{ .src = "performance nthreads=4;", .ok = false, .gap = true },
        .{ .src = "performance details;", .ok = false, .gap = true },
        .{ .src = "performance bpc=1;", .ok = false, .gap = true },
        .{ .src = "performance nodes=4;", .ok = false, .gap = true },
        .{ .src = "performance host='grid';", .ok = false, .gap = true },
        .{ .src = "performance bogus;", .ok = false, .gap = false },
        .{ .src = "performance nthreads;", .ok = false, .gap = false },
    };
    for (cases) |c| {
        var diags = diag.Diagnostics.init(ar);
        const toks = try lex.tokenize(ar, c.src, &diags);
        var end: usize = 0;
        while (toks[end].tag != .semicolon) end += 1;
        var perf: Performance = .{};
        diag.resetGap();
        const r = parsePerformance(&diags, "HPREG", toks, 0, end, &perf);
        if (c.ok) {
            try r;
        } else {
            try std.testing.expectError(error.ParseError, r);
            try std.testing.expectEqual(c.gap, diag.gapHit());
        }
    }
    diag.resetGap();
}

test "STAT-HP-001 shared tables match the verified HPREG layout" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const ar = arena.allocator();
    var out: Out = .empty;
    try performanceInfo(ar, &out);
    try dataAccessInfo(ar, &out, "WORK.SAMPLE");
    try std.testing.expectEqualStrings(
        "      Performance Information\n\nExecution Mode       Single-Machine\nNumber of Threads    1             \n\n\n" ++
            "          Data Access Information\n \nData           Engine    Role     Path\n\nWORK.SAMPLE    V9        Input    On Client\n",
        out.items,
    );
}
