//! STAT-REG-001: TYPE=CORR / TYPE=COV / TYPE=SSCP input for PROC REG
//! (S154 "Input Data Sets", PDF pp. 8588-8590).
//!
//! REG fits from the corrected crossproducts, the means and N only. Instead
//! of a second fitting path, each BY group of the summary set is expanded to N
//! synthetic observations whose means and crossproducts equal the stored ones
//! exactly (up to rounding): x_r = mean + sum_j H[r][j] * L[.][j], where L is
//! the Cholesky factor of the CSSCP matrix and H holds k Helmert columns that
//! are orthonormal and orthogonal to the constant (so the means are kept).
//! Every statistic REG prints from such a set is a function of those moments,
//! so the ordinary fit reproduces SAS. Statements and options that need the
//! original observations are stripped by the caller (reg_parse) as SAS does.
//! ponytail: only the moment layouts PROC CORR / a hand-written SSCP set use;
//! weighted sets (SUMWGT row), unequal per-variable N, and non-integer N gap.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const eq = std.ascii.eqlIgnoreCase;

pub const Kind = enum { corr, cov, sscp };

pub fn kindOf(ty: []const u8) ?Kind {
    if (eq(ty, "CORR")) return .corr;
    if (eq(ty, "COV")) return .cov;
    if (eq(ty, "SSCP")) return .sscp;
    return null;
}

/// SAS assumes this N when a TYPE=CORR/COV/SSCP set has no N observation
/// (SAS 9.4 run: Corrected Total DF 9999).
const default_n: f64 = 10000;

fn str(v: Value) []const u8 {
    return switch (v) {
        .str => |s| std.mem.trim(u8, s, " "),
        else => "",
    };
}

fn gapAt(d: *diag.Diagnostics, line: usize, comptime fmt: []const u8, args: anytype) diag.Error {
    return proc.failGap(d, line, "PROC REG: TYPE= input: " ++ fmt, args);
}

pub fn expand(a: std.mem.Allocator, d: *diag.Diagnostics, line: usize, ds: *const Dataset, kind: Kind) diag.Error!*Dataset {
    const ti = ds.indexOf("_TYPE_") orelse return proc.failGap(d, line, "PROC REG: TYPE={s} input data sets are not implemented without _TYPE_ and _NAME_ variables", .{ds.ds_type orelse ""});
    const ni = ds.indexOf("_NAME_") orelse return proc.failGap(d, line, "PROC REG: TYPE={s} input data sets are not implemented without _TYPE_ and _NAME_ variables", .{ds.ds_type orelse ""});
    // Matrix variables: numeric columns named by a matrix row's _NAME_.
    const matrix_tag: []const u8 = switch (kind) {
        .corr => "CORR",
        .cov => "COV",
        .sscp => "SSCP",
    };
    var vars: std.ArrayList(usize) = .empty;
    var keys: std.ArrayList(usize) = .empty;
    for (ds.columns.items, 0..) |col, c| {
        if (c == ti or c == ni) continue;
        if (col.type == .num) {
            if (kind == .sscp and eq(col.name, "Intercept")) continue;
            var named = false;
            for (ds.rows.items) |r| if (eq(str(r[ti]), matrix_tag) and eq(str(r[ni]), col.name)) {
                named = true;
                break;
            };
            if (named) {
                try vars.append(a, c);
                continue;
            }
        }
        try keys.append(a, c);
    }
    const k = vars.items.len;
    if (k == 0) return d.fail(error.ExecError, line, "PROC REG: the TYPE={s} data set has no {s} observations.", .{ @tagName(kind), matrix_tag });
    const icol: ?usize = if (kind == .sscp) (ds.indexOf("Intercept") orelse return gapAt(d, line, "a TYPE=SSCP set without an Intercept variable is not implemented", .{})) else null;

    const out = try a.create(Dataset);
    out.* = Dataset.init(a, ds.name);
    for (keys.items) |c| try out.columns.append(a, ds.columns.items[c]);
    for (vars.items) |c| try out.columns.append(a, ds.columns.items[c]);

    var start: usize = 0;
    const rows = ds.rows.items;
    while (start < rows.len) {
        var stop = start + 1;
        while (stop < rows.len and sameKeys(rows[start], rows[stop], keys.items)) stop += 1;
        try group(a, d, line, out, rows[start..stop], keys.items, vars.items, ti, ni, icol, kind, ds);
        start = stop;
    }
    return out;
}

fn sameKeys(x: []const Value, y: []const Value, keys: []const usize) bool {
    for (keys) |c| switch (x[c]) {
        .num => |v| {
            const w = y[c].num;
            if (std.math.isNan(v) != std.math.isNan(w)) return false;
            if (!std.math.isNan(v) and v != w) return false;
        },
        .str => |s| if (!std.mem.eql(u8, std.mem.trimEnd(u8, s, " "), std.mem.trimEnd(u8, str(y[c]), " "))) return false,
    };
    return true;
}

fn group(a: std.mem.Allocator, d: *diag.Diagnostics, line: usize, out: *Dataset, rows: []const []const Value, keys: []const usize, vars: []const usize, ti: usize, ni: usize, icol: ?usize, kind: Kind, ds: *const Dataset) diag.Error!void {
    const k = vars.len;
    const mean = try a.alloc(f64, k);
    const sd = try a.alloc(f64, k);
    const m = try a.alloc(f64, k * k); // matrix rows by variable
    var have_mean = false;
    var have_std = false;
    var have = try a.alloc(bool, k);
    @memset(have, false);
    var n: ?f64 = null;
    var sscp_n: ?f64 = null;
    const sums = try a.alloc(f64, k);
    var have_sums = false;
    const matrix_tag: []const u8 = switch (kind) {
        .corr => "CORR",
        .cov => "COV",
        .sscp => "SSCP",
    };
    for (rows) |r| {
        const ty = str(r[ti]);
        if (eq(ty, "MEAN")) {
            for (vars, 0..) |c, j| mean[j] = r[c].num;
            have_mean = true;
        } else if (eq(ty, "STD")) {
            for (vars, 0..) |c, j| sd[j] = r[c].num;
            have_std = true;
        } else if (eq(ty, "N")) {
            var value: ?f64 = null;
            for (vars) |c| {
                const v = r[c].num;
                if (value) |w| if (v != w) return gapAt(d, line, "unequal N for the matrix variables is not implemented", .{});
                value = v;
            }
            n = value;
        } else if (eq(ty, "SUMWGT")) {
            return gapAt(d, line, "a SUMWGT observation (weighted summary) is not implemented", .{});
        } else if (eq(ty, matrix_tag)) {
            const name = str(r[ni]);
            if (kind == .sscp and (eq(name, "Intercept") or eq(name, "Intercep"))) { // $8 _NAME_ truncates
                for (vars, 0..) |c, j| sums[j] = r[c].num;
                sscp_n = r[icol.?].num;
                have_sums = true;
                continue;
            }
            const row_index = for (vars, 0..) |c, j| {
                if (eq(ds.columns.items[c].name, name)) break j;
            } else continue;
            for (vars, 0..) |c, j| m[row_index * k + j] = r[c].num;
            have[row_index] = true;
        }
        // Other _TYPE_ values (CORR rows of a TYPE=COV set, CSSCP, ...) are not
        // used by REG for this TYPE.
    }
    for (have) |h| if (!h) return d.fail(error.ExecError, line, "PROC REG: the TYPE={s} data set lacks a {s} observation for a matrix variable.", .{ @tagName(kind), matrix_tag });
    const count = n orelse if (kind == .sscp and sscp_n != null) sscp_n.? else blk: {
        // SAS 9.4 run: TYPE=COV without an N observation (the same rule covers
        // CORR); a TYPE=SSCP set takes N from its Intercept total silently.
        const member = if (std.mem.indexOfScalar(u8, ds.name, '.') != null) ds.name else try std.fmt.allocPrint(a, "WORK.{s}", .{ds.name});
        try d.warnStatus(line, "The data set {s} does not indicate how many observations were used to compute the {s} matrix. The number of observations has been set to 10000. Statistics that depend on the number of observations (such as p-values) are not interpretable.", .{ try std.ascii.allocUpperString(a, member), matrix_tag });
        break :blk default_n;
    };
    if (!std.math.isFinite(count) or count != @trunc(count) or count < @as(f64, @floatFromInt(k + 1))) return gapAt(d, line, "N={d} (not an integer of at least the number of variables plus one) is not implemented", .{count});
    const nn: usize = @intFromFloat(count);
    if (nn > 10_000_000) return gapAt(d, line, "N above 10000000 is not implemented", .{});
    // Corrected crossproducts and means.
    const cssp = try a.alloc(f64, k * k);
    switch (kind) {
        .corr => {
            if (!have_mean) return gapAt(d, line, "a TYPE=CORR set without a MEAN observation is not implemented", .{});
            if (!have_std) return d.fail(error.ExecError, line, "PROC REG: the TYPE=CORR data set lacks a STD observation.", .{});
            for (0..k) |i| for (0..k) |j| {
                cssp[i * k + j] = m[i * k + j] * sd[i] * sd[j] * (count - 1);
            };
        },
        .cov => {
            if (!have_mean) return gapAt(d, line, "a TYPE=COV set without a MEAN observation is not implemented", .{});
            for (0..k) |i| for (0..k) |j| {
                cssp[i * k + j] = m[i * k + j] * (count - 1);
            };
        },
        .sscp => {
            if (!have_sums) return gapAt(d, line, "a TYPE=SSCP set without an Intercept row is not implemented", .{});
            if (sscp_n) |w| if (w != count) return gapAt(d, line, "a TYPE=SSCP set whose Intercept total differs from N is not implemented", .{});
            for (0..k) |j| mean[j] = sums[j] / count;
            for (0..k) |i| for (0..k) |j| {
                cssp[i * k + j] = m[i * k + j] - sums[i] * sums[j] / count;
            };
        },
    }
    for (cssp) |v| if (!std.math.isFinite(v)) return gapAt(d, line, "missing matrix entries are not implemented", .{});
    for (mean) |v| if (!std.math.isFinite(v)) return gapAt(d, line, "missing means are not implemented", .{});
    // Semidefinite Cholesky: cssp = L L', zero columns for dependent pivots.
    const l = try a.alloc(f64, k * k);
    @memset(l, 0);
    for (0..k) |j| {
        var s = cssp[j * k + j];
        for (0..j) |p| s -= l[j * k + p] * l[j * k + p];
        const tol = 1e-12 * @max(1.0, @abs(cssp[j * k + j]));
        if (s < -tol) return d.fail(error.ExecError, line, "PROC REG: the TYPE={s} matrix is not positive semidefinite.", .{@tagName(kind)});
        if (s <= tol) continue;
        const pivot = @sqrt(s);
        l[j * k + j] = pivot;
        for (j + 1..k) |i| {
            var t = cssp[i * k + j];
            for (0..j) |p| t -= l[i * k + p] * l[j * k + p];
            l[i * k + j] = t / pivot;
        }
    }
    const cells = try a.alloc(Value, keys.len + k);
    for (keys, 0..) |c, j| cells[j] = rows[0][c];
    for (0..nn) |r| {
        for (0..k) |c| {
            var v = mean[c];
            // Helmert column j: rows 0..j get 1/sqrt((j+1)(j+2)), row j+1 gets
            // -(j+1)/sqrt((j+1)(j+2)), later rows 0.
            for (0..k) |j| {
                if (r > j + 1) continue;
                const jf: f64 = @floatFromInt(j + 1);
                const h = if (r == j + 1) -jf / @sqrt(jf * (jf + 1)) else 1 / @sqrt(jf * (jf + 1));
                v += h * l[c * k + j];
            }
            cells[keys.len + c] = .{ .num = v };
        }
        try out.appendRow(cells);
    }
}

test "STAT-REG-001 typed expansion reproduces means and crossproducts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var ds = Dataset.init(a, "s");
    _ = try ds.addColumn("_TYPE_", .char);
    _ = try ds.addColumn("_NAME_", .char);
    _ = try ds.addColumn("Intercept", .num);
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    try ds.appendRow(&.{ .{ .str = "SSCP" }, .{ .str = "Intercept" }, .{ .num = 5 }, .{ .num = 15 }, .{ .num = 21 } });
    try ds.appendRow(&.{ .{ .str = "SSCP" }, .{ .str = "x" }, .{ .num = 15 }, .{ .num = 55 }, .{ .num = 75 } });
    try ds.appendRow(&.{ .{ .str = "SSCP" }, .{ .str = "y" }, .{ .num = 21 }, .{ .num = 75 }, .{ .num = 103 } });
    try ds.appendRow(&.{ .{ .str = "N" }, .{ .str = "" }, .{ .num = 5 }, .{ .num = 5 }, .{ .num = 5 } });
    const out = try expand(a, &d, 1, &ds, .sscp);
    try std.testing.expectEqual(@as(usize, 5), out.rowCount());
    var sx: f64 = 0;
    var sxy: f64 = 0;
    var syy: f64 = 0;
    for (out.rows.items) |r| {
        sx += r[0].num;
        sxy += r[0].num * r[1].num;
        syy += r[1].num * r[1].num;
    }
    try std.testing.expectApproxEqAbs(@as(f64, 15), sx, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 75), sxy, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 103), syy, 1e-9);
    // Unequal N and SUMWGT are loud gaps.
    try ds.appendRow(&.{ .{ .str = "SUMWGT" }, .{ .str = "" }, .{ .num = 5 }, .{ .num = 5 }, .{ .num = 5 } });
    try std.testing.expectError(error.ParseError, expand(a, &d, 1, &ds, .sscp));
}

const lex = @import("../lexer.zig");

fn isName(tok: lex.Token, s: []const u8) bool {
    return tok.tag == .name and eq(tok.text, s);
}

/// Options that need the original observations (S154 p. 8589): disabled.
fn rawOnly(tok: lex.Token) bool {
    if (tok.tag != .name) return false;
    for ([_][]const u8{ "p", "r", "clm", "cli", "dw", "influence", "partial" }) |n| if (eq(tok.text, n)) return true;
    return false;
}

/// Rewrites the statements after the PROC REG statement (which ends at
/// `semi`) for summary input: drops OUTPUT (an empty OUT= set is created, as
/// SAS does), PLOT and PRINT-with-raw-options statements, and removes the
/// raw-only MODEL options, logging the SAS notes. Statements whose summary
/// behaviour is not verified fail loudly.
pub fn strip(cx: proc.ProcCtx, t: []const lex.Token, semi: usize, ty: []const u8) diag.Error![]const lex.Token {
    var out: std.ArrayList(lex.Token) = .empty;
    try out.appendSlice(cx.arena, t[0 .. semi + 1]);
    var i = semi + 1;
    var ignored_options = false;
    while (i < t.len and t[i].tag != .eof) {
        var end = i;
        while (end < t.len and t[end].tag != .semicolon and t[end].tag != .eof) end += 1;
        const stop = if (end < t.len and t[end].tag == .semicolon) end + 1 else end;
        var head = i;
        if (head + 1 < end and t[head].tag == .name and t[head + 1].tag == .colon) head += 2;
        if (head >= end) {
            try out.appendSlice(cx.arena, t[i..stop]);
        } else if (isName(t[head], "output")) {
            var j = head + 1;
            while (j + 2 < end) : (j += 1) if (isName(t[j], "out") and t[j + 1].tag == .eq and t[j + 2].tag == .name) {
                const name = t[j + 2].text;
                if (j + 3 < end and t[j + 3].tag == .dot) return proc.failGap(cx.diags, t[head].line, "PROC REG: OUTPUT OUT= with a libref for TYPE={s} input is not implemented", .{ty});
                const empty = try cx.arena.create(Dataset);
                empty.* = Dataset.init(cx.arena, name);
                try cx.lib.put(name, empty);
                break;
            } else {
                return proc.failGap(cx.diags, t[head].line, "PROC REG: OUTPUT without OUT= for TYPE={s} input is not implemented", .{ty});
            };
            try cx.diags.note(t[head].line, "No raw data are available. The OUTPUT statement is ignored.", .{});
        } else if (isName(t[head], "plot")) {
            try cx.diags.note(t[head].line, "No raw data are available. The PLOT statement is ignored.", .{});
        } else if (isName(t[head], "print")) {
            var j = head + 1;
            if (j == end) return proc.failGap(cx.diags, t[head].line, "PROC REG: PRINT without options for TYPE={s} input is not implemented", .{ty});
            while (j < end) : (j += 1) if (!rawOnly(t[j])) return proc.failGap(cx.diags, t[head].line, "PROC REG: PRINT {s} for TYPE={s} input is not implemented", .{ t[j].text, ty });
            ignored_options = true;
        } else if (isName(t[head], "model")) {
            var slash = head + 1;
            while (slash < end and t[slash].tag != .slash) slash += 1;
            try out.appendSlice(cx.arena, t[i..@min(slash + 1, end)]);
            var kept: usize = 0;
            var j = slash + 1;
            while (j < end) : (j += 1) {
                if (rawOnly(t[j])) {
                    ignored_options = true;
                    continue;
                }
                const allowed = for ([_][]const u8{ "noint", "vif", "tol", "collin", "alpha", "singular" }) |n| {
                    if (isName(t[j], n)) break true;
                } else t[j].tag != .name;
                if (!allowed) return proc.failGap(cx.diags, t[j].line, "PROC REG: MODEL option {s} for TYPE={s} input is not implemented", .{ t[j].text, ty });
                try out.append(cx.arena, t[j]);
                kept += 1;
            }
            // A slash with every option stripped would be a dangling slash.
            if (kept == 0 and slash < end) _ = out.pop();
            try out.appendSlice(cx.arena, t[end..stop]);
        } else if (isName(t[head], "var") or isName(t[head], "by") or isName(t[head], "test") or isName(t[head], "run") or isName(t[head], "quit") or isName(t[head], "where")) {
            try out.appendSlice(cx.arena, t[i..stop]);
        } else {
            return proc.failGap(cx.diags, t[head].line, "PROC REG: the {s} statement for TYPE={s} input is not implemented", .{ t[head].text, ty });
        }
        i = stop;
    }
    if (ignored_options) try cx.diags.note(t[0].line, "No raw data are available. Some options are ignored.", .{});
    try out.appendSlice(cx.arena, t[i..]);
    return out.items;
}
