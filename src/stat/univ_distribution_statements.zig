//! Numerical HISTOGRAM statement execution. Plot rendering is a separate scope.
const std = @import("std");
const proc = @import("../proc.zig");
const univ = @import("univariate.zig");
const parse = @import("univ_distribution_parse.zig");
const fitting = @import("univ_distribution_fit.zig");
const kernel = @import("univ_kernel.zig");
const kernel_parse = @import("univ_kernel_parse.zig");
const kernel_output = @import("univ_kernel_output.zig");
const rendering = @import("univ_distribution_render.zig");
const binning = @import("univ_histogram_bins.zig");
const histogram_output = @import("univ_histogram_output.zig");
const plot_groups = @import("univ_plot_groups.zig");
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
    mode: binning.Mode = .key,
    target_count: ?usize = null,
    max_nbin: ?usize = null,
    max_sigmas: ?f64 = null,
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
    var mode: binning.Mode = .key;
    var midpoint_mode: binning.Mode = .key;
    var target_count: ?usize = null;
    var max_nbin: ?usize = null;
    var max_sigmas: ?f64 = null;
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
            if (t[i.*].tag == .name) {
                const selected: binning.Mode = if (eq(t[i.*].text, "key")) .key else if (eq(t[i.*].text, "uniform")) .uniform else return d.fail(error.ParseError, 0, "UNIVARIATE: expected KEY, UNIFORM or a numeric bin list", .{});
                if (eq(key, "endpoints")) mode = selected else midpoint_mode = selected;
                i.* += 1;
                continue;
            }
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
        } else if (eq(key, "nmidpoints") or eq(key, "nendpoints") or eq(key, "maxnbin")) {
            const value = try number(d, t, i);
            if (value < 0 or value != @floor(value) or value >= @as(f64, @floatFromInt(std.math.maxInt(usize)))) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid histogram count control", .{});
            if (eq(key, "maxnbin")) max_nbin = @intFromFloat(value) else {
                target_count = @intFromFloat(value);
                if (eq(key, "nendpoints")) endpoint_labels = true;
            }
        } else if (eq(key, "maxsigmas")) {
            max_sigmas = try number(d, t, i);
            if (!(max_sigmas.? > 0)) return d.fail(error.ParseError, 0, "UNIVARIATE: MAXSIGMAS must be positive", .{});
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
    if (max_nbin != null and max_sigmas != null) return d.fail(error.ParseError, 0, "UNIVARIATE: MAXNBIN and MAXSIGMAS are alternatives", .{});
    if (max_nbin != null and max_nbin.? == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: MAXNBIN must be positive", .{});
    if (endpoints.items.len > 0) _ = try binning.cover(a, d, &.{}, endpoints.items, right);
    return .{ .variables = vars, .curves = curves.items, .kernels = kernels, .kernel_output = outkernel, .vscale = vscale, .endpoints = endpoints.items, .endpoint_labels = endpoint_labels, .right = right, .output = output, .output_options = output_options, .kernel_output_options = kernel_output_options, .tokens = t[start..i.*], .mode = if (endpoint_labels) mode else midpoint_mode, .target_count = target_count, .max_nbin = max_nbin, .max_sigmas = max_sigmas };
}

pub fn execute(cx: proc.ProcCtx, out: *std.ArrayList(u8), ds: *Dataset, acols: []const usize, ccols: []const usize, bcols: []const usize, wc: ?usize, def: u8, opt: univ.Options, levels: []const h.FmtLevels, statements: []const Statement, has_var: bool) diag.Error!void {
    const a = cx.arena;
    for (statements, 1..) |statement, histogram| {
        if (wc != null) return cx.diags.fail(error.ParseError, 0, "A WEIGHT variable cannot be used together with a CDFPLOT, HISTOGRAM, PPPLOT, PROBPLOT, or QQPLOT statement.", .{});
        if (ccols.len == 0 and (statement.max_nbin != null or statement.max_sigmas != null)) return cx.diags.fail(error.ParseError, 0, "UNIVARIATE: histogram window controls require CLASS", .{});
        const cols = try plot_variables.resolve(a, cx.diags, opt.source orelse ds, acols, statement.variables, has_var);
        var keys: std.ArrayList(usize) = .empty;
        try keys.appendSlice(a, bcols);
        try keys.appendSlice(a, ccols);
        var descriptors = Dataset.init(a, ds.name);
        try descriptors.columns.appendSlice(a, ds.columns.items);
        for (keys.items) |ci| if (h.fmtLevelsFor(levels, ci)) |fl| {
            descriptors.columns.items[ci].type = fl.ty;
            descriptors.columns.items[ci].format = fl.spec;
        };
        var variable_length: usize = 8;
        for (cols) |ci| variable_length = @max(variable_length, ds.columns.items[ci].name.len);
        const schema: histogram_output.Options = .{ .endpoint_labels = statement.endpoint_labels, .right = statement.right, .curve_columns = statement.curves.len > 0, .variable_length = variable_length };
        const output = try histogram_output.create(a, &descriptors, keys.items, schema);
        output.name = statement.output orelse "";
        const kd = try kernel_output.create(a, &descriptors, keys.items, variable_length, statement.vscale);
        for (try univ.bySlices(a, ds.rows.items, bcols, opt)) |bs| {
            var bd = Dataset.init(a, ds.name);
            bd.columns = ds.columns;
            try bd.rows.appendSlice(a, bs.rows);
            const collected = try h.collectGroups(a, &bd, ccols);
            try univ.orderGroups(a, &bd, collected, ccols, levels, wc, opt);
            const resolved = try plot_groups.resolve(a, cx.diags, &bd, collected, ccols, opt);
            const groups = resolved.groups;
            const analyses = try a.alloc(univ.Analysis, groups.len);
            const representatives = try a.alloc([]const Value, groups.len);
            for (groups, 0..) |g, gi| {
                const rep = try a.dupe(Value, g.rep);
                if (g.rows.len > 0) for (ccols) |ci| if (h.fmtLevelsFor(levels, ci) != null) {
                    rep[ci] = univ.classRepresentative(&bd, opt, wc, ccols, ci, g.rep);
                };
                representatives[gi] = rep;
                const gd = try a.create(Dataset);
                gd.* = Dataset.init(a, ds.name);
                gd.columns = ds.columns;
                try gd.rows.appendSlice(a, g.rows);
                analyses[gi] = try univ.analysisView(a, gd, cols, wc, opt);
            }
            // Output order is BY, variable, then class cell; each variable's
            // cells share one bin plan, including empty-key resolution.
            for (cols) |ci| {
                const cells = try a.alloc(binning.Cell, groups.len);
                var pooled: std.ArrayList(f64) = .empty;
                for (analyses, cells) |analysis, *cell| {
                    var x: std.ArrayList(f64) = .empty;
                    for (analysis.ds.rows.items) |row| {
                        const value = h.toNum(row[ci]);
                        if (!std.math.isNan(value)) try x.append(a, value);
                    }
                    std.mem.sort(f64, x.items, {}, std.sort.asc(f64));
                    cell.* = .{ .sorted = x.items };
                    try pooled.appendSlice(a, x.items);
                }
                if (pooled.items.len == 0) {
                    for (statement.kernels) |request| if (request.bandwidth == .sjpi) {
                        _ = try kernel.fitSjpi(cx.diags, &.{}, 0, request);
                        break;
                    };
                    continue;
                }
                std.mem.sort(f64, pooled.items, {}, std.sort.asc(f64));
                const plan = try binning.determine(a, cx.diags, cells, .{ .endpoints = statement.endpoint_labels, .right = statement.right, .mode = statement.mode, .key_index = resolved.key_index, .key_move = opt.key_move, .target_count = statement.target_count, .max_nbin = statement.max_nbin, .max_sigmas = statement.max_sigmas, .initial_endpoints = statement.endpoints });
                var output_options = schema;
                output_options.bin_width = plan.width;
                output_options.clipped = plan.clipped;
                for (plan.cell_order) |gi| {
                    const x = cells[gi].sorted;
                    if (x.len == 0) continue;
                    const rep = representatives[gi];
                    if (statement.kernels.len > 0 or statement.kernel_output != null) {
                        const pairs = try a.alloc(h.XW, x.len);
                        for (x, pairs) |v, *pair| pair.* = .{ .x = v, .w = 1 };
                        const iqr = h.univPercentile(pairs, 75, def) - h.univPercentile(pairs, 25, def);
                        var report: kernel_output.Report = .{};
                        const automatic = statement.endpoints.len == 0;
                        // Retained translated negative-data controls expose an unresolved
                        // automatic endpoint phase. Explicit lattices remain available.
                        if (automatic and statement.endpoint_labels and x[0] < 0 and x[0] != x[x.len - 1]) return proc.failGap(cx.diags, 0, "UNIVARIATE: automatic endpoint kernel phase for negative nonconstant data is not verified; supply explicit endpoints", .{});
                        try kernel_output.appendBatch(cx.diags, kd, ds, keys.items, rep, ci, x, iqr, statement.kernels, plan.endpoints, statement.vscale, .{ .automatic = automatic, .endpoint_labels = statement.endpoint_labels, .windowed = plan.clipped, .bin_width = plan.width, .right = statement.right, .clip_lower = automatic, .clip_upper = automatic, .report = &report });
                        if (report.compact_cutoff_unverified) return proc.failGap(cx.diags, 0, "UNIVARIATE: compact-kernel cutoff has not been verified", .{});
                    }
                    const constant = x[0] == x[x.len - 1];
                    if (statement.curves.len == 0 or constant) {
                        try histogram_output.append(cx.diags, output, ds, keys.items, rep, ci, x, plan.endpoints, output_options, null);
                        continue;
                    }
                    for (statement.curves) |curves| for (curves.requests) |request| {
                        var report: fitting.Report = .{};
                        var trace: fitting.Trace = .{ .allocator = a };
                        var actual_request = request;
                        actual_request.report = &report;
                        if (request.optprint or request.itprint) actual_request.trace = &trace;
                        const curve = fitting.fit(cx.diags, x, actual_request) catch |err| {
                            if (request.itprint and trace.weibull.items.len > 0) try rendering.renderTrace(a, out, trace, report);
                            if (report.no_fit) {
                                if (request.optprint) try rendering.renderTrace(a, out, trace, report);
                                try histogram_output.append(cx.diags, output, ds, keys.items, rep, ci, x, plan.endpoints, output_options, null);
                                continue;
                            }
                            return err;
                        };
                        if (request.optprint or (request.itprint and trace.weibull.items.len > 0)) try rendering.renderTrace(a, out, trace, report);
                        try histogram_output.append(cx.diags, output, ds, keys.items, rep, ci, x, plan.endpoints, output_options, curve);
                        if (!curves.noprint) {
                            const bins = try histogram_output.bins(a, cx.diags, x, plan.endpoints, output_options, curve);
                            try rendering.render(cx, out, analyses[gi].ds, ci, bcols, ccols, histogram, x, def, curve, request, curves, bins, statement.right, !statement.endpoint_labels);
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
    const t = try @import("../lexer.zig").tokenize(a, "proc univariate data=d noprint; histogram x / noplot kernel(k=n q t c=.5 noprint) endpoints=0 to 20 by 5 outkernel=k; run;", &d);
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

test "UNIVARIATE public exponential FREQ boundaries preserve fitted scale and ODS probabilities" {
    @import("../format.zig").resetPerRun();
    defer @import("../format.zig").resetPerRun();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var ds = Dataset.init(a, "d");
    for ([_][]const u8{ "grp", "x", "f" }) |name| _ = try ds.addColumn(name, .num);
    for (1..4) |group| {
        try ds.appendRow(&.{ .{ .num = @floatFromInt(group) }, .{ .num = 1 }, .{ .num = @floatFromInt(group) } });
        for (2..12 - group) |x| try ds.appendRow(&.{ .{ .num = @floatFromInt(group) }, .{ .num = @floatFromInt(x) }, .{ .num = 1 } });
    }
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    const lex = @import("../lexer.zig");
    var capture: @import("../ods.zig").Capture = .{};
    try capture.parse(a, &d, try lex.tokenize(a, "ods output ParameterEstimates=pe GoodnessOfFit=g;", &d));
    const t = try lex.tokenize(a, "proc univariate data=d noprint;by grp;var x;freq f;histogram x / noplot exponential(theta=1) endpoints=0 to 12 by 2;run;", &d);
    var out: std.ArrayList(u8) = .empty;
    try proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d, .capture = &capture }, &out, t);
    try capture.finish(&lib, &d);
    try std.testing.expect(!d.hasErrors());
    const pe = lib.find("pe").?;
    const gof = lib.find("g").?;
    try std.testing.expectEqual(@as(usize, 12), pe.rows.items.len);
    try std.testing.expectEqual(@as(usize, 9), gof.rows.items.len);
    const scale_col = pe.indexOf("Estimate").?;
    const stat_col = gof.indexOf("Stat").?;
    const p_col = gof.indexOf("pValue").?;
    for ([_]f64{ 4.5, 3.6, 2.8 }, [_]f64{ 0.20612584565148, 0.27298140699918, 0.35541564637523 }, [_]f64{ 0.0610498063026, 0.02109092820893, 0.00463333633783 }, 0..) |scale, statistic, p, i| {
        try std.testing.expectApproxEqAbs(scale, pe.rows.items[4 * i + 1][scale_col].num, 1e-14);
        try std.testing.expectApproxEqAbs(statistic, gof.rows.items[3 * i + 1][stat_col].num, 1e-12);
        try std.testing.expectApproxEqAbs(p, gof.rows.items[3 * i + 1][p_col].num, 1e-10);
    }
}

test "UNIVARIATE public small all-known gamma emits D and W2 but no A2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 1, 2, 3, 4 }) |x| try ds.appendRow(&.{.{ .num = x }});
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    const lex = @import("../lexer.zig");
    var capture: @import("../ods.zig").Capture = .{};
    try capture.parse(a, &d, try lex.tokenize(a, "ods output GoodnessOfFit=g;", &d));
    const t = try lex.tokenize(a, "proc univariate data=d noprint;histogram x / noplot gamma(alpha=2 sigma=1) endpoints=0 to 5 by 1;run;", &d);
    var out: std.ArrayList(u8) = .empty;
    try proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d, .capture = &capture }, &out, t);
    try capture.finish(&lib, &d);
    const result = lib.find("g").?;
    try std.testing.expectEqual(@as(usize, 2), result.rows.items.len);
    try std.testing.expectEqualStrings("D", result.rows.items[0][result.indexOf("TestLab").?].str);
    try std.testing.expectEqualStrings("W-Sq", result.rows.items[1][result.indexOf("TestLab").?].str);
}

test "UNIVARIATE public ODS uses valid MC denominator and omits no-valid probabilities" {
    const Controlled = struct {
        calls: usize = 0,
        all_fail: bool = false,
        fn draw(raw: ?*anyopaque, _: std.Random, _: usize, _: *diag.Diagnostics) diag.Error!proc.univariate_edf.SimulationAttempt {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            if (self.all_fail or self.calls == 2 or self.calls == 4) return .{ .numerical_fit_failure = .{ .reason = "controlled failure", .retained_candidate = false } };
            return .{ .valid = if (self.calls == 3) .{ .d = 0.125, .w2 = 1.0 / 48.0, .a2 = 0.14 } else .{ .d = 0.9, .w2 = 0.973333333333, .a2 = 5.63 } };
        }
    };
    @import("../format.zig").resetPerRun();
    defer @import("../format.zig").resetPerRun();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 0.5, 1, 2, 3 }) |x| try ds.appendRow(&.{.{ .num = x }});
    try lib.put("d", &ds);
    const lex = @import("../lexer.zig");
    for ([_]bool{ false, true }) |all_fail| {
        var d = diag.Diagnostics.init(a);
        var sampler: Controlled = .{ .all_fail = all_fail };
        var capture: @import("../ods.zig").Capture = .{};
        try capture.parse(a, &d, try lex.tokenize(a, if (all_fail) "ods output GoodnessOfFit=none;" else "ods output GoodnessOfFit=valid;", &d));
        const t = try lex.tokenize(a, "proc univariate data=d noprint;histogram x / noplot rayleigh(sigma=1 edfseed=17 edfnsamples=5) endpoints=0 to 4 by 1;run;", &d);
        var out: std.ArrayList(u8) = .empty;
        try proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d, .capture = &capture, .univariate_edf_sampler = .{ .context = &sampler, .draw = Controlled.draw } }, &out, t);
        try capture.finish(&lib, &d);
        try std.testing.expectEqual(@as(usize, 5), sampler.calls);
        if (all_fail) {
            try std.testing.expect(lib.find("none") == null and d.hasErrors());
            try std.testing.expect(std.mem.indexOf(u8, out.items, "Goodness-of-Fit Tests") == null);
        } else {
            const result = lib.find("valid").?;
            try std.testing.expectEqual(@as(usize, 3), result.rows.items.len);
            for (result.rows.items) |row| try std.testing.expectApproxEqAbs(@as(f64, 2.0 / 3.0), row[result.indexOf("pValue").?].num, 1e-15);
            try std.testing.expect(!d.hasErrors());
        }
        var counted = false;
        for (d.list.items) |entry| if (entry.severity == .warning and std.mem.indexOf(u8, entry.message, "attempted=5") != null) {
            counted = true;
        };
        try std.testing.expect(counted);
    }
}

test "UNIVARIATE shared KEY and UNIFORM bins are variable-first and honor NOKEYMOVE" {
    @import("../format.zig").resetPerRun();
    defer @import("../format.zig").resetPerRun();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("c", .char);
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    for ([_][2]f64{ .{ 0, 100 }, .{ 1, 101 }, .{ 10, 200 }, .{ 12, 202 } }, 0..) |r, i| try ds.appendRow(&.{ .{ .str = if (i < 2) "A" else "B" }, .{ .num = r[0] }, .{ .num = r[1] } });
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    const lex = @import("../lexer.zig");
    var out: std.ArrayList(u8) = .empty;
    const cases = [_]struct { cls: []const u8, options: []const u8, rows: usize, first_class: []const u8, first: f64 }{
        .{ .cls = "keylevel='B'", .options = "", .rows = 10, .first_class = "B", .first = 10 },
        .{ .cls = "keylevel='B' nokeymove", .options = "", .rows = 10, .first_class = "A", .first = 0 },
        .{ .cls = "keylevel='B'", .options = "midpoints=uniform", .rows = 4, .first_class = "B", .first = 12 },
        .{ .cls = "keylevel='A'", .options = "nmidpoints=4", .rows = 4, .first_class = "A", .first = 0 },
        .{ .cls = "keylevel='Z'", .options = "", .rows = 16, .first_class = "A", .first = 0 },
    };
    for (cases) |case| {
        const program = try std.fmt.allocPrint(a, "proc univariate data=d noprint;class c / {s};var x y;histogram x y / noplot {s} outhistogram=h;run;", .{ case.cls, case.options });
        const t = try lex.tokenize(a, program, &d);
        try proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, t);
        const result = lib.find("h").?;
        try std.testing.expectEqual(case.rows, result.rows.items.len);
        try std.testing.expectEqualStrings(case.first_class, result.rows.items[0][0].str);
        try std.testing.expectApproxEqAbs(case.first, result.rows.items[0][2].num, 1e-12);
        var seen_y = false;
        for (result.rows.items) |row| {
            if (std.mem.eql(u8, row[1].str, "y")) seen_y = true else try std.testing.expect(!seen_y);
        }
    }
    try std.testing.expect(!d.hasErrors());
}

test "UNIVARIATE constant curves are suppressed and OUTKERNEL alone computes default estimate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    for (0..4) |_| try ds.appendRow(&.{.{ .num = 5 }});
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    const t = try @import("../lexer.zig").tokenize(a, "proc univariate data=d noprint;histogram x / noplot normal(mu=5 sigma=1) outhistogram=h outkernel=k;run;", &d);
    var out: std.ArrayList(u8) = .empty;
    try proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, t);
    const histogram = lib.find("h").?;
    try std.testing.expectEqual(@as(usize, 1), histogram.rows.items.len);
    try std.testing.expectEqualStrings("", histogram.rows.items[0][histogram.indexOf("_CURVE_").?].str);
    try std.testing.expect(histogram.rows.items[0][histogram.indexOf("_EXPPCT_").?].isMissing());
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    const output = lib.find("k").?;
    try std.testing.expectEqual(@as(usize, 512), output.rows.items.len);
    try std.testing.expectEqual(@as(f64, 3), output.rows.items[0][output.indexOf("_VALUE_").?].num);
    try std.testing.expectEqual(@as(f64, 0.78520352), output.rows.items[0][output.indexOf("_C_").?].num);
}

test "UNIVARIATE explicit kernel windows retain zeros outside reflection bounds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 1, 2, 3, 4, 6, 8, 10, 15 }) |x| try ds.appendRow(&.{.{ .num = x }});
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    const t = try @import("../lexer.zig").tokenize(a, "proc univariate data=d noprint;histogram x / noplot kernel(k=n q t c=.5 lower=0 upper=20) endpoints=-5 to 25 by 5 outkernel=k;run;", &d);
    var out: std.ArrayList(u8) = .empty;
    try proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, t);
    const result = lib.find("k").?;
    const value = result.indexOf("_VALUE_").?;
    const density = result.indexOf("_DENSITY_").?;
    try std.testing.expectEqual(@as(f64, -5), result.rows.items[0][value].num);
    var beyond = false;
    for (result.rows.items) |row| if (row[value].num < 0 or row[value].num > 20) {
        beyond = true;
        try std.testing.expectEqual(@as(f64, 0), row[density].num);
    };
    try std.testing.expect(beyond);
    try std.testing.expect(!d.hasErrors());
}

test "UNIVARIATE empty analysis key uses UNIFORM while selected missing variable keeps schema length" {
    @import("../format.zig").resetPerRun();
    defer @import("../format.zig").resetPerRun();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("c", .char);
    _ = try ds.addColumn("x", .num);
    const missing_name = "all_missing_long_variable_name";
    _ = try ds.addColumn(missing_name, .num);
    try ds.appendRow(&.{ .{ .str = "A" }, Value.missing, Value.missing });
    try ds.appendRow(&.{ .{ .str = "B" }, .{ .num = 10 }, Value.missing });
    try ds.appendRow(&.{ .{ .str = "B" }, .{ .num = 12 }, Value.missing });
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    const t = try @import("../lexer.zig").tokenize(a, "proc univariate data=d noprint;class c;var x all_missing_long_variable_name;histogram / noplot outhistogram=h;run;", &d);
    var out: std.ArrayList(u8) = .empty;
    try proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, t);
    const result = lib.find("h").?;
    try std.testing.expectEqual(@as(?usize, missing_name.len), result.columns.items[result.indexOf("_VAR_").?].len);
    try std.testing.expectEqual(@as(usize, 3), result.rows.items.len);
    try std.testing.expectEqualStrings("B", result.rows.items[0][0].str);
    var warned = false;
    for (d.list.items) |entry| if (std.mem.indexOf(u8, entry.message, "empty key cell") != null) {
        warned = true;
    };
    try std.testing.expect(warned and !d.hasErrors());
}

test "UNIVARIATE crossed KEYLEVEL promotes its hierarchy and preserves other block order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("c", .char);
    _ = try ds.addColumn("q", .char);
    _ = try ds.addColumn("x", .num);
    for (0..4) |cell| for (0..2) |i| try ds.appendRow(&.{ .{ .str = if (cell < 2) "A" else "B" }, .{ .str = if (cell % 2 == 0) "X" else "Y" }, .{ .num = @floatFromInt(10 * cell + i) } });
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    const t = try @import("../lexer.zig").tokenize(a, "proc univariate data=d noprint;class c q / keylevel=('B' 'Y');var x;histogram x / noplot outhistogram=h;run;", &d);
    var out: std.ArrayList(u8) = .empty;
    try proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, t);
    const result = lib.find("h").?;
    try std.testing.expectEqual(@as(usize, 12), result.rows.items.len);
    for ([_][]const u8{ "B", "B", "A", "A" }, [_][]const u8{ "Y", "X", "X", "Y" }, 0..) |c, q, i| {
        try std.testing.expectEqualStrings(c, result.rows.items[3 * i][0].str);
        try std.testing.expectEqualStrings(q, result.rows.items[3 * i][1].str);
    }
}

test "UNIVARIATE public endpoint axes match every SAS M9 coordinate and density" {
    const samples = [_][]const f64{ &.{ 1, 2, 3, 4, 6, 8, 10, 15 }, &.{ 5, 5, 5, 5 }, &.{ 0, 0, 0, 0 }, &.{ -12, -12, -12, -12 }, &.{ 0.01, 0.01, 0.01, 0.01 } };
    for (samples, [_][]const u8{ "wide", "five", "zero", "neg", "small" }) |sample, name| {
        for ([_][]const u8{ ".5", "1", "2" }, [_][]const u8{ "p5", "1", "2" }) |c, suffix| {
            for ([_]bool{ false, true }) |right| {
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const a = arena.allocator();
                var lib = @import("../exec.zig").Library.init(a);
                var ds = Dataset.init(a, "d");
                _ = try ds.addColumn("x", .num);
                for (sample) |x| try ds.appendRow(&.{.{ .num = x }});
                try lib.put("d", &ds);
                var d = diag.Diagnostics.init(a);
                const text = try std.fmt.allocPrint(a, "proc univariate data=d noprint;histogram x / noplot endpoints {s} kernel(c={s}) outkernel=k;run;", .{ if (right) "rtinclude" else "", c });
                const tokens = try @import("../lexer.zig").tokenize(a, text, &d);
                var out: std.ArrayList(u8) = .empty;
                try proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, tokens);
                const rows = lib.find("k").?.rows.items;
                const key = try std.fmt.allocPrint(a, "{s}_{s}{s}", .{ name, suffix, if (right) "_r" else "" });
                var lines = std.mem.tokenizeScalar(u8, @embedFile("testdata/univ_endpoint_axis_dev4.txt"), '\n');
                var i: usize = 0;
                while (lines.next()) |line| {
                    var fields = std.mem.splitScalar(u8, line, '|');
                    _ = fields.next();
                    if (!std.mem.eql(u8, fields.next().?, key)) continue;
                    errdefer std.debug.print("endpoint case {s} row {d}\n", .{ key, i });
                    try std.testing.expect(i < rows.len);
                    for ([_]usize{ 3, 5, 4 }) |col| {
                        const expected = try std.fmt.parseFloat(f64, std.mem.trim(u8, fields.next().?, " "));
                        try std.testing.expectApproxEqAbs(expected, rows[i][col].num, 1e-9 * @max(@as(f64, 1), @abs(expected)));
                    }
                    i += 1;
                }
                try std.testing.expectEqual(i, rows.len);
            }
        }
    }
}

test "UNIVARIATE public supplied lattices preserve budgets clipped rows and percentages" {
    for ([_][]const u8{ "endpoints", "midpoints" }) |kind| {
        for ([_][]const u8{ "maxnbin=2", "maxnbin=6", "maxnbin=10", "maxsigmas=1", "maxsigmas=3" }) |control| {
            for ([_]bool{ false, true }) |right| {
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const a = arena.allocator();
                var lib = @import("../exec.zig").Library.init(a);
                var ds = Dataset.init(a, "d");
                _ = try ds.addColumn("c", .char);
                _ = try ds.addColumn("x", .num);
                for ([_]f64{ 1, 4, 8, 12, -12, -5, 20, 35 }, [_][]const u8{ "A", "A", "A", "A", "B", "B", "C", "C" }) |x, c| try ds.appendRow(&.{ .{ .str = c }, .{ .num = x } });
                try lib.put("d", &ds);
                var d = diag.Diagnostics.init(a);
                const source = try std.fmt.allocPrint(a, "proc univariate data=d noprint;class c;var x;histogram x / noplot {s}=0 to 15 by 5 {s} {s} outhistogram=h;run;", .{ kind, control, if (right) "rtinclude" else "" });
                const tokens = try @import("../lexer.zig").tokenize(a, source, &d);
                var out: std.ArrayList(u8) = .empty;
                try proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, tokens);
                const rows = lib.find("h").?.rows.items;
                const key = try std.fmt.allocPrint(a, "{s}_{s}{s}", .{ kind, control, if (right) "_r" else "" });
                var lines = std.mem.tokenizeScalar(u8, @embedFile("testdata/univ_supplied_lattice_dev4.txt"), '\n');
                var i: usize = 0;
                while (lines.next()) |line| {
                    var fields = std.mem.splitScalar(u8, line, '|');
                    if (!std.mem.eql(u8, fields.next().?, key)) continue;
                    errdefer std.debug.print("supplied lattice case {s} row {d}\n", .{ key, i });
                    try std.testing.expect(i < rows.len);
                    try std.testing.expectEqualStrings(std.mem.trim(u8, fields.next().?, " "), rows[i][0].str);
                    for ([_]usize{ 2, 4, 3 }) |col| try std.testing.expectApproxEqAbs(try std.fmt.parseFloat(f64, std.mem.trim(u8, fields.next().?, " ")), rows[i][col].num, 1e-12);
                    i += 1;
                }
                try std.testing.expectEqual(i, rows.len);
            }
        }
    }
}

test "UNIVARIATE public endpoint axes heldouts cover shifted data and compact kernels" {
    const samples = [_][]const f64{ &.{ 1.2, 1.7, 2.1, 3.6, 5.2, 9.7, 12.3, 17.8 }, &.{ -15, -9, -6, -4, -2, -1, 0, 3 }, &.{ 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5 }, &.{ -0.1, -0.1, -0.1, -0.1, -0.1, -0.1, -0.1 } };
    for (samples, [_][]const u8{ "shift", "negative", "half", "tiny" }) |sample, name| {
        for ([_][]const u8{ "0.3", "1.1" }) |c| {
            for ([_][]const u8{ "n", "q", "t" }) |kind| {
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const a = arena.allocator();
                var lib = @import("../exec.zig").Library.init(a);
                var ds = Dataset.init(a, "d");
                _ = try ds.addColumn("x", .num);
                for (sample) |x| try ds.appendRow(&.{.{ .num = x }});
                try lib.put("d", &ds);
                var d = diag.Diagnostics.init(a);
                const text = try std.fmt.allocPrint(a, "proc univariate data=d noprint;histogram x / noplot endpoints kernel(k={s} c={s}) outkernel=k;run;", .{ kind, c });
                const tokens = try @import("../lexer.zig").tokenize(a, text, &d);
                var out: std.ArrayList(u8) = .empty;
                if (std.mem.eql(u8, name, "negative")) {
                    diag.resetGap();
                    defer diag.resetGap();
                    try std.testing.expectError(error.ParseError, proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, tokens));
                    try std.testing.expect(diag.gapHit());
                    try std.testing.expect(std.mem.indexOf(u8, d.list.items[d.list.items.len - 1].message, "negative nonconstant") != null);
                    continue;
                }
                try proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, tokens);
                const rows = lib.find("k").?.rows.items;
                const key = try std.fmt.allocPrint(a, "{s}_{s}_{s}", .{ name, kind, c });
                var lines = std.mem.tokenizeScalar(u8, @embedFile("testdata/univ_endpoint_axis_heldout_dev4.txt"), '\n');
                var i: usize = 0;
                while (lines.next()) |line| {
                    var fields = std.mem.splitScalar(u8, line, '|');
                    if (!std.mem.eql(u8, fields.next().?, key)) continue;
                    errdefer std.debug.print("endpoint case {s} row {d}\n", .{ key, i });
                    try std.testing.expect(i < rows.len);
                    for ([_]usize{ 3, 5, 4 }) |col| {
                        const expected = try std.fmt.parseFloat(f64, std.mem.trim(u8, fields.next().?, " "));
                        try std.testing.expectApproxEqAbs(expected, rows[i][col].num, 1e-9 * @max(@as(f64, 1), @abs(expected)));
                    }
                    i += 1;
                }
                try std.testing.expectEqual(i, rows.len);
            }
        }
    }
}

test "UNIVARIATE public power location publishes only oracle curves with nonstationary warnings" {
    var lines = std.mem.tokenizeScalar(u8, @embedFile("testdata/univ_endpoint_power_location_dev5.txt"), '\n');
    var curves: usize = 0;
    var absent: usize = 0;
    while (lines.next()) |line| {
        if (line[0] == '#') continue;
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fields = std.mem.splitScalar(u8, line, '|');
        const id = fields.next().?;
        errdefer std.debug.print("public power location case {s}\n", .{id});
        const sigma = fields.next().?;
        const alpha = fields.next().?;
        const theta = fields.next().?;
        const exact = std.mem.eql(u8, fields.next().?, "1");
        var observations = std.mem.splitScalar(u8, fields.next().?, ',');
        var lib = @import("../exec.zig").Library.init(a);
        var ds = Dataset.init(a, "d");
        _ = try ds.addColumn("x", .num);
        while (observations.next()) |v| try ds.appendRow(&.{.{ .num = try std.fmt.parseFloat(f64, v) }});
        try lib.put("d", &ds);
        var d = diag.Diagnostics.init(a);
        const lex = @import("../lexer.zig");
        var capture: @import("../ods.zig").Capture = .{};
        try capture.parse(a, &d, try lex.tokenize(a, "ods output ParameterEstimates=pe;", &d));
        const source = try std.fmt.allocPrint(a, "proc univariate data=d noprint;histogram x / noplot power(theta=est sigma={s} alpha={s}) outhistogram=h;run;", .{ sigma, alpha });
        const tokens = try lex.tokenize(a, source, &d);
        var out: std.ArrayList(u8) = .empty;
        try proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d, .capture = &capture }, &out, tokens);
        const no_fit = std.mem.eql(u8, theta, "none");
        var warned = false;
        for (d.list.items) |message| {
            try std.testing.expect(message.severity == .warning);
            if (std.mem.indexOf(u8, message.message, if (no_fit) "initialization_failed" else "nonstationary_candidate") != null) warned = true;
        }
        try std.testing.expect(warned);
        try capture.finish(&lib, &d);
        if (no_fit) {
            absent += 1;
            try std.testing.expect(lib.find("pe") == null);
        } else {
            curves += 1;
            const pe = lib.find("pe").?;
            for ([_][]const u8{ "Theta", "Sigma", "Alpha" }, [_][]const u8{ theta, sigma, alpha }) |symbol, value| {
                var found = false;
                for (pe.rows.items) |row| if (std.ascii.eqlIgnoreCase(row[4].str, symbol)) {
                    const expected = try std.fmt.parseFloat(f64, value);
                    if (exact or !std.ascii.eqlIgnoreCase(symbol, "Theta")) try std.testing.expectEqual(expected, row[5].num) else try std.testing.expectApproxEqAbs(expected, row[5].num, 1e-12);
                    found = true;
                };
                try std.testing.expect(found);
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 93), curves);
    try std.testing.expectEqual(@as(usize, 41), absent);
}

test "UNIVARIATE public SJPI uses the normal kernel and omits a constant curve" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 4, 10 }) |x| try ds.appendRow(&.{ .{ .num = x }, .{ .num = 2.75 } });
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    const t = try @import("../lexer.zig").tokenize(a, "proc univariate data=d noprint; " ++
        "histogram x / kernel(k=q c=sjpi) outkernel=k noplot; " ++
        "histogram y / kernel(c=sjpi) outkernel=empty noplot; run;", &d);
    try proc.runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, t);
    try std.testing.expect(!d.hasErrors());
    try std.testing.expectEqual(@as(usize, 0), lib.find("empty").?.rows.items.len);
    const k = lib.find("k").?;
    try std.testing.expectEqual(@as(usize, 249), k.rows.items.len);
    // M9 kde_sjpi_ties: first, center and last grid ordinates.
    for ([_]usize{ 0, 124, 248 }, [_]f64{ -3, 5.7109375, 14.4296875 }, [_]f64{ 0.00246106157244, 2.34204123863303, 0.00022758796908 }, [_]f64{ 8.20353857482e-6, 0.00780680412878, 7.58626563587e-7 }) |i, point, percent, density| {
        const row = k.rows.items[i];
        try std.testing.expectEqualStrings("Normal", row[1].str);
        try std.testing.expectApproxEqAbs(@as(f64, 1.0053107939231), row[2].num, 1e-12);
        try std.testing.expectEqual(point, row[3].num);
        try std.testing.expectApproxEqAbs(percent, row[4].num, 1e-11);
        try std.testing.expectApproxEqAbs(density, row[5].num, 1e-13);
    }
    const messages = try d.render();
    try std.testing.expect(std.mem.indexOf(u8, messages, "normal kernel") != null);
    try std.testing.expect(std.mem.indexOf(u8, messages, "no estimate") != null);
}
