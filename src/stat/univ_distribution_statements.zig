//! Numerical HISTOGRAM statement execution. Plot rendering is a separate scope.
const std = @import("std");
const proc = @import("../proc.zig");
const univ = @import("univariate.zig");
const parse = @import("univ_distribution_parse.zig");
const fitting = @import("univ_distribution_fit.zig");
const values = @import("univ_distribution_values.zig");
const dist = @import("univ_distributions.zig");
const kernel = @import("univ_kernel.zig");
const kernel_parse = @import("univ_kernel_parse.zig");
const kernel_output = @import("univ_kernel_output.zig");
const rendering = @import("univ_distribution_render.zig");
const binning = @import("univ_histogram_bins.zig");
const plot_variables = @import("univ_plot_variables.zig");
const diag = @import("../diag.zig");
const Token = @import("../lexer.zig").Token;
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const h = proc.UnivariateHelpers;
const eq = std.ascii.eqlIgnoreCase;
pub const Statement = struct {
    variables: [][]const u8,
    curves: []parse.Curves,
    kernels: []kernel.Request,
    kernel_output: ?[]const u8,
    vscale: kernel.VScale,
    endpoints: []const f64,
    endpoint_labels: bool,
    right: bool,
    output: ?[]const u8,
    output_options: []const Token = &.{},
    kernel_output_options: []const Token = &.{},
    tokens: []const Token,
};

fn number(d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error!f64 {
    var sign: f64 = 1;
    if (t[i.*].tag == .minus or t[i.*].tag == .plus) {
        if (t[i.*].tag == .minus) sign = -1;
        i.* += 1;
    }
    if (t[i.*].tag != .number) return d.fail(error.ParseError, 0, "UNIVARIATE: expected numeric histogram endpoint", .{});
    const v = std.fmt.parseFloat(f64, t[i.*].text) catch return d.fail(error.ParseError, 0, "UNIVARIATE: invalid histogram endpoint", .{});
    i.* += 1;
    if (!std.math.isFinite(v)) return d.fail(error.ParseError, 0, "UNIVARIATE: histogram endpoint must be finite", .{});
    return sign * v;
}

fn outputName(a: std.mem.Allocator, d: *diag.Diagnostics, t: []const Token, i: *usize, options: *[]const Token) diag.Error![]const u8 {
    options.* = &.{};
    if (t[i.*].tag != .name) return d.fail(error.ParseError, 0, "UNIVARIATE: expected output dataset name", .{});
    if (i.* + 2 < t.len and t[i.* + 1].tag == .dot and t[i.* + 2].tag != .name) return d.fail(error.ParseError, 0, "UNIVARIATE: expected output dataset member name", .{});
    const name = try univ.datasetName(a, t, i);
    if (t[i.*].tag == .lparen) {
        var depth: usize = 1;
        i.* += 1;
        const start = i.*;
        while (i.* < t.len and depth > 0) : (i.* += 1) {
            if (t[i.*].tag == .semicolon or t[i.*].tag == .eof) return d.fail(error.ParseError, 0, "UNIVARIATE: unclosed output dataset options", .{});
            if (t[i.*].tag == .lparen) depth += 1;
            if (t[i.*].tag == .rparen) depth -= 1;
        }
        if (depth != 0) return d.fail(error.ParseError, 0, "UNIVARIATE: unclosed output dataset options", .{});
        options.* = t[start .. i.* - 1];
    }
    return name;
}

pub fn parseStatement(a: std.mem.Allocator, d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error!Statement {
    const start = i.*;
    i.* += 1;
    const vars = try plot_variables.parse(a, t, i);
    if (t[i.*].tag != .slash) return proc.failGap(d, 0, "PROC UNIVARIATE: histogram statement requires supported numerical options and NOPLOT", .{});
    i.* += 1;
    var curves: std.ArrayList(parse.Curves) = .empty;
    var endpoints: std.ArrayList(f64) = .empty;
    var midpoints: std.ArrayList(f64) = .empty;
    var endpoint_labels = false;
    var noplot = false;
    var right = false;
    var output: ?[]const u8 = null;
    var outkernel: ?[]const u8 = null;
    var output_options: []const Token = &.{};
    var kernel_output_options: []const Token = &.{};
    var kernels: []kernel.Request = &.{};
    var vscale: kernel.VScale = .percent;
    while (t[i.*].tag != .semicolon and t[i.*].tag != .eof) {
        if (t[i.*].tag != .name) return d.fail(error.ParseError, 0, "UNIVARIATE: expected HISTOGRAM option", .{});
        const key = t[i.*].text;
        if (eq(key, "kernel")) {
            if (kernels.len > 0) return d.fail(error.ParseError, 0, "UNIVARIATE: repeated KERNEL option", .{});
            kernels = try kernel_parse.parse(a, d, t, i);
            continue;
        }
        if (parse.family(key) != null) {
            const c = try parse.parse(a, d, t, i);
            for (curves.items) |old| if (old.requests[0].family == c.requests[0].family) return d.fail(error.ParseError, 0, "UNIVARIATE: repeated distribution family {s}", .{key});
            try curves.append(a, c);
            continue;
        }
        i.* += 1;
        if (eq(key, "noplot") or eq(key, "nochart")) {
            noplot = true;
            continue;
        }
        if (eq(key, "rtinclude")) {
            right = true;
            continue;
        }
        if (eq(key, "endpoints")) {
            endpoint_labels = true;
            if (t[i.*].tag != .eq) continue;
        }
        if (t[i.*].tag != .eq) return d.fail(error.ParseError, 0, "UNIVARIATE: unsupported HISTOGRAM option {s}", .{key});
        i.* += 1;
        if (eq(key, "outhistogram") or eq(key, "outhist")) {
            output = try outputName(a, d, t, i, &output_options);
        } else if (eq(key, "outkernel")) {
            outkernel = try outputName(a, d, t, i, &kernel_output_options);
        } else if (eq(key, "vscale")) {
            const name = t[i.*].text;
            vscale = if (eq(name, "percent")) .percent else if (eq(name, "proportion")) .proportion else if (eq(name, "count")) .count else return d.fail(error.ParseError, 0, "UNIVARIATE: invalid VSCALE", .{});
            i.* += 1;
        } else if (eq(key, "endpoints") or eq(key, "midpoints")) {
            const list = if (eq(key, "endpoints")) &endpoints else &midpoints;
            while (t[i.*].tag == .number or t[i.*].tag == .minus or t[i.*].tag == .plus or t[i.*].tag == .comma) {
                if (t[i.*].tag == .comma) {
                    i.* += 1;
                    continue;
                }
                const first = try number(d, t, i);
                if (t[i.*].tag == .name and eq(t[i.*].text, "to")) {
                    i.* += 1;
                    const last = try number(d, t, i);
                    var step: f64 = 1;
                    if (t[i.*].tag == .name and eq(t[i.*].text, "by")) {
                        i.* += 1;
                        step = try number(d, t, i);
                    }
                    if (step <= 0 or last < first or (last - first) / step > 100000) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid endpoint range", .{});
                    var j: usize = 0;
                    while (first + @as(f64, @floatFromInt(j)) * step <= last + 1e-12 * step) : (j += 1) try list.append(a, first + @as(f64, @floatFromInt(j)) * step);
                } else try list.append(a, first);
            }
        } else return d.fail(error.ParseError, 0, "UNIVARIATE: unsupported HISTOGRAM option {s}", .{key});
    }
    if (!noplot) return proc.failGap(d, 0, "PROC UNIVARIATE: histogram graphics are not supported; specify NOPLOT for numerical output", .{});
    if (endpoints.items.len == 1 or midpoints.items.len == 1) return d.fail(error.ParseError, 0, "UNIVARIATE: explicit bin lists need at least two values", .{});
    if (endpoint_labels and midpoints.items.len > 0) try d.warn(0, "UNIVARIATE: ENDPOINTS takes precedence over MIDPOINTS", .{});
    if (!endpoint_labels and midpoints.items.len > 0) {
        const width = midpoints.items[1] - midpoints.items[0];
        if (!(width > 0)) return d.fail(error.ParseError, 0, "UNIVARIATE: midpoints must increase", .{});
        for (midpoints.items) |point| try endpoints.append(a, point - width / 2);
        try endpoints.append(a, midpoints.items[midpoints.items.len - 1] + width / 2);
    }
    return .{ .variables = vars, .curves = curves.items, .kernels = kernels, .kernel_output = outkernel, .vscale = vscale, .endpoints = endpoints.items, .endpoint_labels = endpoint_labels, .right = right, .output = output, .output_options = output_options, .kernel_output_options = kernel_output_options, .tokens = t[start..i.*] };
}

pub fn execute(cx: proc.ProcCtx, out: *std.ArrayList(u8), ds: *Dataset, acols: []const usize, ccols: []const usize, bcols: []const usize, wc: ?usize, def: u8, opt: univ.Options, levels: []const h.FmtLevels, statements: []const Statement, has_var: bool) diag.Error!void {
    const a = cx.arena;
    for (statements, 1..) |statement, histogram| {
        if (wc != null) return cx.diags.fail(error.ParseError, 0, "A WEIGHT variable cannot be used together with a CDFPLOT, HISTOGRAM, PPPLOT, PROBPLOT, or QQPLOT statement.", .{});
        const selected = try plot_variables.resolve(a, cx.diags, opt.source orelse ds, acols, statement.variables, has_var);
        const cols: std.ArrayList(usize) = .{ .items = @constCast(selected), .capacity = selected.len };
        var keys: std.ArrayList(usize) = .empty;
        try keys.appendSlice(a, bcols);
        try keys.appendSlice(a, ccols);
        var descriptors = Dataset.init(a, ds.name);
        try descriptors.columns.appendSlice(a, ds.columns.items);
        for (keys.items) |ci| if (h.fmtLevelsFor(levels, ci)) |fl| {
            descriptors.columns.items[ci].type = fl.ty;
            descriptors.columns.items[ci].format = fl.spec;
        };
        const output = try a.create(Dataset);
        output.* = Dataset.init(a, statement.output orelse "");
        output.label = "Histogram Statistics";
        for (keys.items) |ci| _ = try output.addColumnLike(descriptors.columns.items[ci].name, descriptors.columns.items[ci]);
        _ = try output.addColumn("_VAR_", .char);
        var variable_length: usize = 8;
        for (cols.items) |ci| variable_length = @max(variable_length, ds.columns.items[ci].name.len);
        const kd = try kernel_output.create(a, &descriptors, keys.items, variable_length, statement.vscale);
        kd.label = "Kernel Density Estimates";
        output.setLen("_VAR_", variable_length);
        output.setLabel("_VAR_", "Variable Name");
        const location = if (!statement.endpoint_labels) "_MIDPT_" else if (statement.right) "_MAXPT_" else "_MINPT_";
        _ = try output.addColumn(location, .num);
        _ = try output.addColumn("_OBSPCT_", .num);
        _ = try output.addColumn("_COUNT_", .num);
        output.setLabel(location, if (!statement.endpoint_labels) "Midpoint of Histogram Interval" else if (statement.right) "Right endpoint of Histogram Interval" else "Left endpoint of Histogram Interval");
        output.setLabel("_OBSPCT_", "Percent of Observations in Interval");
        output.setLabel("_COUNT_", "Observation Count in Interval");
        if (statement.curves.len > 0) {
            _ = try output.addColumn("_CURVE_", .char);
            output.setLen("_CURVE_", 16);
            output.setLabel("_CURVE_", "Fitted Curve");
            _ = try output.addColumn("_EXPPCT_", .num);
            output.setLabel("_EXPPCT_", "Expected Percent From Fitted Curve");
        }
        for (try univ.bySlices(a, ds.rows.items, bcols, opt)) |bs| {
            var bd = Dataset.init(a, ds.name);
            bd.columns = ds.columns;
            try bd.rows.appendSlice(a, bs.rows);
            const groups = try h.collectGroups(a, &bd, ccols);
            try univ.orderGroups(a, &bd, groups, ccols, levels, wc, opt);
            for (groups) |g| {
                if (g.rows.len == 0) continue;
                const representative = try a.dupe(Value, g.rep);
                for (ccols) |ci| if (h.fmtLevelsFor(levels, ci) != null) {
                    representative[ci] = univ.classRepresentative(&bd, opt, wc, ccols, ci, g.rep);
                };
                var gd = Dataset.init(a, ds.name);
                gd.columns = ds.columns;
                try gd.rows.appendSlice(a, g.rows);
                const analysis = try univ.analysisView(a, &gd, cols.items, wc, opt);
                for (cols.items) |ci| {
                    var x: std.ArrayList(f64) = .empty;
                    for (analysis.ds.rows.items) |row| {
                        const value = h.toNum(row[ci]);
                        if (!std.math.isNan(value)) try x.append(a, value);
                    }
                    std.mem.sort(f64, x.items, {}, std.sort.asc(f64));
                    if (x.items.len == 0) continue;
                    var local_statement = statement;
                    if (statement.endpoints.len == 0) local_statement.endpoints = try binning.automatic(a, cx.diags, x.items, statement.endpoint_labels, statement.right);
                    if (statement.kernels.len > 0) {
                        const pairs = try a.alloc(h.XW, x.items.len);
                        for (x.items, pairs) |v, *p| p.* = .{ .x = v, .w = 1 };
                        const iqr = h.univPercentile(pairs, 75, def) - h.univPercentile(pairs, 25, def);
                        const range = x.items[x.items.len - 1] - x.items[0];
                        var period: f64 = 0;
                        if (range > 0 and iqr > 0) for (statement.kernels) |request| {
                            const estimate = try kernel.fit(cx.diags, x.items, iqr, request);
                            period = @max(period, estimate.fftPeriod(range) orelse return cx.diags.fail(error.ParseError, 0, "UNIVARIATE: invalid kernel grid", .{}));
                            if (request.kind == .normal and estimate.bandwidth > range / 2) try cx.diags.warn(0, "UNIVARIATE: normal kernel bandwidth is large and produces wrap-around at the axis ends", .{});
                        };
                        for (statement.kernels) |request| {
                            var shared = request;
                            if (period > 0) shared.fft_period = period;
                            try kernel_output.append(cx.diags, kd, ds, keys.items, representative, ci, x.items, iqr, shared, local_statement.endpoints, statement.vscale);
                        }
                    }
                    if (statement.curves.len == 0) {
                        try rows(cx, output, ds, keys.items, representative, ci, x.items, local_statement, null);
                    } else for (statement.curves) |curves| for (curves.requests) |request| {
                        var report: fitting.Report = .{};
                        var trace: fitting.Trace = .{ .allocator = a };
                        var actual_request = request;
                        actual_request.report = &report;
                        if (request.optprint or request.itprint) actual_request.trace = &trace;
                        const curve = fitting.fit(cx.diags, x.items, actual_request) catch |err| {
                            if (request.itprint and trace.weibull.items.len > 0) try rendering.renderTrace(a, out, trace, report);
                            if (report.no_fit) {
                                if (request.optprint) try rendering.renderTrace(a, out, trace, report);
                                try rows(cx, output, ds, keys.items, representative, ci, x.items, local_statement, null);
                                continue;
                            }
                            return err;
                        };
                        if (request.optprint or (request.itprint and trace.weibull.items.len > 0)) try rendering.renderTrace(a, out, trace, report);
                        try rows(cx, output, ds, keys.items, representative, ci, x.items, local_statement, curve);
                        if (!curves.noprint) {
                            const bins = try values.histogram(a, cx.diags, x.items, local_statement.endpoints, statement.right, curve);
                            try rendering.render(cx, out, analysis.ds, ci, bcols, ccols, histogram, x.items, def, curve, request, curves, bins, statement.right, !statement.endpoint_labels);
                        }
                    };
                }
            }
        }
        if (statement.output) |name| {
            applyOutputOptions(a, cx.diags, output, statement.output_options) catch |err| {
                output.rows.clearRetainingCapacity();
                try cx.lib.put(name, output);
                return err;
            };
            try cx.lib.put(name, output);
        }
        if (statement.kernel_output) |name| {
            kd.name = name;
            applyOutputOptions(a, cx.diags, kd, statement.kernel_output_options) catch |err| {
                kd.rows.clearRetainingCapacity();
                try cx.lib.put(name, kd);
                return err;
            };
            try cx.lib.put(name, kd);
        }
    }
}

/// Output WHERE refers to the final output descriptor (after KEEP/DROP/RENAME).
/// Keep this procedure-owned ordering separate from input dataset semantics.
fn applyOutputOptions(a: std.mem.Allocator, d: *diag.Diagnostics, ds: *Dataset, options: []const Token) diag.Error!void {
    var structural: std.ArrayList(Token) = .empty;
    var where: std.ArrayList(Token) = .empty;
    var depth: usize = 0;
    var i: usize = 0;
    while (i < options.len) {
        if (depth == 0 and options[i].tag == .name and eq(options[i].text, "where") and i + 2 < options.len and options[i + 1].tag == .eq and options[i + 2].tag == .lparen) {
            const start = i;
            i += 3;
            var nesting: usize = 1;
            while (i < options.len and nesting > 0) : (i += 1) {
                if (options[i].tag == .lparen) nesting += 1;
                if (options[i].tag == .rparen) nesting -= 1;
            }
            if (nesting != 0) return d.fail(error.ParseError, 0, "UNIVARIATE: unclosed output WHERE", .{});
            try where.appendSlice(a, options[start..i]);
            continue;
        }
        if (options[i].tag == .lparen) depth += 1;
        if (options[i].tag == .rparen and depth > 0) depth -= 1;
        try structural.append(a, options[i]);
        i += 1;
    }
    const before = d.count();
    try @import("../io.zig").applyDatasetOptions(a, ds, structural.items, d, false);
    if (d.errSince(before)) return error.ParseError;
    try @import("../io.zig").applyDatasetOptions(a, ds, where.items, d, false);
    if (d.errSince(before)) return error.ParseError;
}

fn rows(cx: proc.ProcCtx, output: *Dataset, source: *Dataset, keys: []const usize, representative: []const Value, ci: usize, x: []const f64, statement: Statement, curve: ?dist.Distribution) diag.Error!void {
    const bins = try values.histogram(cx.arena, cx.diags, x, statement.endpoints, statement.right, curve);
    for (bins) |bin| {
        const row = try cx.arena.alloc(Value, output.columns.items.len);
        @memset(row, Value.missing);
        for (keys, 0..) |key, i| row[i] = representative[key];
        const at = keys.len;
        row[at] = .{ .str = source.columns.items[ci].name };
        row[at + 1] = .{ .num = if (!statement.endpoint_labels) bin.midpoint else if (statement.right) bin.upper else bin.lower };
        row[at + 2] = .{ .num = bin.observed_percent };
        row[at + 3] = .{ .num = @floatFromInt(bin.count) };
        if (curve) |c| {
            row[at + 4] = .{ .str = curveName(c.family) };
            row[at + 5] = .{ .num = bin.expected_percent.? };
        } else if (statement.curves.len > 0) row[at + 4] = .{ .str = "" };
        try output.appendRow(row);
    }
}

fn curveName(family: dist.Family) []const u8 {
    return switch (family) {
        .normal => "NORMAL",
        .lognormal => "LNORMAL",
        .exponential => "EXPONTL",
        .gamma => "GAMMA",
        .weibull => "WEIBULL",
        .beta => "BETA",
        .power => "POWER",
        .rayleigh => "RAYLEIGH",
        .pareto => "PARETO",
        .gumbel => "GUMBEL",
        .igauss => "IGAUSS",
        .sb => "SB",
        .su => "SU",
    };
}

test "UNIVARIATE HISTOGRAM NOPLOT OUTHISTOGRAM executes under PROC NOPRINT with BY and FREQ" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var ds = Dataset.init(a, "d");
    for ([_][]const u8{ "g", "x", "f" }) |name| _ = try ds.addColumn(name, .num);
    for ([_]f64{ 1, 2, 4, 8, 2, 3, 6, 9 }, 0..) |x, i| {
        try ds.appendRow(&.{ .{ .num = if (i < 4) 1 else 2 }, .{ .num = x }, .{ .num = if (i == 0) 2 else 1 } });
    }
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    const t = try @import("../lexer.zig").tokenize(a, "proc univariate data=d noprint; by g; freq f; var x; " ++
        "histogram x / noplot normal(mu=0 sigma=2 noprint) endpoints=0 to 10 by 2 outhistogram=h; " ++
        "histogram x / noplot endpoints=0 to 10 by 2 rtinclude outhistogram=r; run;", &d);
    try proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, t);
    try std.testing.expect(!d.hasErrors());
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    const od = lib.find("h").?;
    try std.testing.expectEqual(@as(usize, 9), od.rows.items.len);
    try std.testing.expectEqual(@as(?usize, 8), od.columns.items[1].len);
    try std.testing.expectEqual(@as(?usize, 16), od.columns.items[5].len);
    try std.testing.expectEqualStrings("Fitted Curve", od.columns.items[5].label.?);
    try std.testing.expectEqual(@as(f64, 40), od.rows.items[0][3].num);
    try std.testing.expectEqual(@as(f64, 2), od.rows.items[0][4].num);
    try std.testing.expectApproxEqAbs(@as(f64, 34.1344746069), od.rows.items[0][6].num, 1e-9);
    try std.testing.expectEqual(@as(f64, 2), od.rows.items[5][0].num);
    const right = lib.find("r").?;
    try std.testing.expectEqualStrings("_MAXPT_", right.columns.items[2].name);
    try std.testing.expectEqual(@as(f64, 60), right.rows.items[0][3].num);
    try std.testing.expectEqual(@as(usize, 5), right.columns.items.len);
}

test "UNIVARIATE OUTKERNEL grid descriptors and values match SAS M9" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 1, 2, 3, 4, 6, 8, 10, 15 }) |x| try ds.appendRow(&.{.{ .num = x }});
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    const t = try @import("../lexer.zig").tokenize(a, "proc univariate data=d noprint; histogram x / noplot kernel(k=n q t c=.5) endpoints=0 to 20 by 5 outkernel=k; run;", &d);
    try proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, t);
    const k = lib.find("k").?;
    try std.testing.expectEqual(@as(usize, 555), k.rows.items.len);
    try std.testing.expectEqualStrings("_PERCENT_", k.columns.items[4].name);
    try std.testing.expectEqualStrings("Percent of Observations Per Data Unit", k.columns.items[4].label.?);
    try std.testing.expectEqualStrings("Normal", k.rows.items[0][1].str);
    try std.testing.expectEqualStrings("Quadratic", k.rows.items[185][1].str);
    try std.testing.expectEqualStrings("Triangular", k.rows.items[370][1].str);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0492280549), k.rows.items[0][5].num, 5e-10);
    try std.testing.expectEqual(@as(f64, 0.015625), k.rows.items[1][3].num);
    try std.testing.expectApproxEqAbs(@as(f64, 24.777645636), k.rows.items[1][4].num, 2e-7);
    try std.testing.expectEqual(@as(f64, 20), k.rows.items[184][3].num);
}

test "UNIVARIATE fitted numerical tables publish ODS without creating unrequested OUT datasets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 1, 2, 3, 4, 6, 8, 10, 15 }) |x| try ds.appendRow(&.{.{ .num = x }});
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    const lex = @import("../lexer.zig");
    var capture: @import("../ods.zig").Capture = .{};
    try capture.parse(a, &d, try lex.tokenize(a, "ods output ParameterEstimates=pe FitQuantiles=q GoodnessOfFit=g Bins=b;", &d));
    var out: std.ArrayList(u8) = .empty;
    const t = try lex.tokenize(a, "proc univariate data=d noprint; histogram x / noplot normal(mu=0 sigma=2 midpercents percents=10 50 90) endpoints=0 to 20 by 5; run;", &d);
    try proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d, .capture = &capture }, &out, t);
    try capture.finish(&lib, &d);
    try std.testing.expect(!d.hasErrors());
    try std.testing.expect(lib.find("") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Parameters for Normal Distribution") != null);
    const pe = lib.find("pe").?;
    try std.testing.expectEqual(@as(usize, 2), pe.rows.items.len);
    try std.testing.expectEqual(@as(?usize, 9), pe.columns.items[3].len);
    try std.testing.expectEqualStrings("Parameter Estimate", pe.columns.items[5].label.?);
    try std.testing.expectEqual(@as(f64, 2), pe.rows.items[1][5].num);
    const q = lib.find("q").?;
    try std.testing.expectEqual(@as(usize, 3), q.rows.items.len);
    try std.testing.expectEqual(@as(f64, 50), q.rows.items[1][3].num);
    try std.testing.expectEqual(@as(f64, 5), q.rows.items[1][4].num);
    try std.testing.expectApproxEqAbs(@as(f64, 0), q.rows.items[1][5].num, 1e-12);
    const bins = lib.find("b").?;
    try std.testing.expectEqual(@as(usize, 4), bins.rows.items.len);
    try std.testing.expectApproxEqAbs(@as(f64, 49.379), bins.rows.items[0][5].num, 0.0005);
    const g = lib.find("g").?;
    try std.testing.expectEqual(@as(usize, 3), g.rows.items.len);
    try std.testing.expectEqualStrings("pValue", g.columns.items[8].name);
}

test "UNIVARIATE WEIGHT with HISTOGRAM is a SAS error before output publication" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("w", .num);
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 1 } });
    try ds.appendRow(&.{ .{ .num = 2 }, .{ .num = 2 } });
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    const t = try @import("../lexer.zig").tokenize(a, "proc univariate data=d noprint; var x; weight w; output out=s mean=m; histogram x / noplot outhistogram=h; run;", &d);
    diag.resetGap();
    try std.testing.expectError(error.ParseError, proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, t));
    try std.testing.expect(!diag.gapHit());
    try std.testing.expect(lib.find("h") == null and lib.find("s") == null);
    try std.testing.expect(std.mem.indexOf(u8, d.list.items[0].message, "WEIGHT variable cannot") != null);
}

test "UNIVARIATE public Johnson methods endpoint adapter and fallback trace reach ODS" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("b", .num);
    _ = try ds.addColumn("u", .num);
    for (1..102) |i| {
        const z = @import("../functions.zig").distQuantile(.normal, (@as(f64, @floatFromInt(i)) - 0.375) / 101.25, &.{}).?;
        try ds.appendRow(&.{ .{ .num = 1 / (1 + @exp((0.4 - z) / 1.2)) }, .{ .num = 3 + 2 * std.math.sinh((z - 0.4) / 1.2) } });
    }
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    const lex = @import("../lexer.zig");
    var capture: @import("../ods.zig").Capture = .{};
    try capture.parse(a, &d, try lex.tokenize(a, "ods output ParameterEstimates=pe;", &d));
    const t = try lex.tokenize(a, "proc univariate data=d noprint;var b u;" ++
        "histogram b / noplot sb(fitmethod=moments) endpoints=0 to 1 by .25;" ++
        "histogram u / noplot su(fitmethod=mle theta=3 sigma=2 optseed=123) endpoints=-20 to 20 by 5;" ++
        "histogram u / noplot su(fitmethod=mle optmaxiter=1 optmaxstarts=1 optseed=17 optprint) endpoints=-20 to 20 by 5;" ++
        "histogram b / noplot beta(theta=est sigma=1 alpha=2 beta=3) endpoints=0 to 1 by .25;run;", &d);
    var out: std.ArrayList(u8) = .empty;
    try proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d, .capture = &capture }, &out, t);
    try capture.finish(&lib, &d);
    try std.testing.expect(!d.hasErrors());
    const pe = lib.find("pe").?;
    try std.testing.expectEqual(@as(usize, 33), pe.rows.items.len);
    try std.testing.expectApproxEqAbs(@as(f64, 1.177443), pe.rows.items[2][5].num, 7e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 1.219036), pe.rows.items[11][5].num, 6e-7);
    try std.testing.expectEqual(@as(f64, 1), pe.rows.items[28][5].num);
    try std.testing.expectEqual(@as(f64, 2), pe.rows.items[29][5].num);
    try std.testing.expectEqual(@as(f64, 3), pe.rows.items[30][5].num);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Optimization status: nonconverged") != null);
    var warned = false;
    for (d.list.items) |message| if (message.severity == .warning and std.mem.indexOf(u8, message.message, "fallback") != null) {
        warned = true;
    };
    try std.testing.expect(warned);
}

test "UNIVARIATE public Weibull ITPRINT renders actual iteration history" {
    @import("../format.zig").resetPerRun();
    defer @import("../format.zig").resetPerRun();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 1, 2, 3, 4, 6, 8, 10, 15 }) |x| try ds.appendRow(&.{.{ .num = x }});
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    const lexer = @import("../lexer.zig");
    const t = try lexer.tokenize(a, "proc univariate data=d noprint;histogram x / noplot weibull(itprint maxiter=5) endpoints=0 to 20 by 5 outhistogram=h;run;", &d);
    try proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, t);
    try std.testing.expect(!d.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Weibull Optimization History") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Optimization status: converged") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "newton") != null);
    try std.testing.expectApproxEqAbs(@as(f64, 47.9626), lib.find("h").?.rows.items[0][5].num, 5e-5);
    var bad = diag.Diagnostics.init(a);
    const invalid = try lexer.tokenize(a, "histogram x / noplot weibull(maxiter=1);", &bad);
    var i: usize = 0;
    try std.testing.expectError(error.ParseError, parseStatement(a, &bad, invalid, &i));
}

test "UNIVARIATE output WHERE follows the renamed descriptor for qualified outputs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 1, 2, 3, 4, 6, 8, 10, 15 }) |x| try ds.appendRow(&.{.{ .num = x }});
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    const lex = @import("../lexer.zig");
    var out: std.ArrayList(u8) = .empty;
    const valid = try lex.tokenize(a, "proc univariate data=d noprint;histogram x / noplot endpoints=0 to 20 by 5 outhist=work.good(keep=_count_ rename=(_count_=n) where=(n>0));run;", &d);
    try proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, valid);
    const good = lib.find("work.good").?;
    try std.testing.expectEqualStrings("Histogram Statistics", good.label.?);
    try std.testing.expectEqual(@as(usize, 1), good.columns.items.len);
    try std.testing.expectEqualStrings("n", good.columns.items[0].name);
    try std.testing.expectEqual(@as(usize, 4), good.rows.items.len);
    try std.testing.expectEqual(@as(f64, 4), good.rows.items[0][0].num);
    var invalid_diag = diag.Diagnostics.init(a);
    const invalid = try lex.tokenize(a, "proc univariate data=d noprint;histogram x / noplot endpoints=0 to 20 by 5 outhistogram=work.bad(keep=_count_ rename=(_count_=n) where=(_count_>0));run;", &invalid_diag);
    try std.testing.expectError(error.ParseError, proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &invalid_diag }, &out, invalid));
    const bad = lib.find("work.bad").?;
    try std.testing.expectEqual(@as(usize, 0), bad.rows.items.len);
    try std.testing.expectEqualStrings("n", bad.columns.items[0].name);
    try std.testing.expect(invalid_diag.hasErrors());
}
