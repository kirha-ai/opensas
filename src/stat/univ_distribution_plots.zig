//! CDF/PP/QQ/probability statement numerics. Graphics require an explicit sink.
const std = @import("std");
const proc = @import("../proc.zig");
const univ = @import("univariate.zig");
const parameters = @import("univ_distribution_parse.zig");
const fitting = @import("univ_distribution_fit.zig");
const dist = @import("univ_distributions.zig");
const values = @import("univ_distribution_values.zig");
const variables = @import("univ_plot_variables.zig");
const data = @import("univ_plot_data.zig");
const diag = @import("../diag.zig");
const Token = @import("../lexer.zig").Token;
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const h = proc.UnivariateHelpers;
const eq = std.ascii.eqlIgnoreCase;
pub const Statement = struct {
    kind: data.Kind,
    variables: [][]const u8,
    curves: parameters.Curves,
    weibull2: bool = false,
    rankadj: f64 = -0.375,
    nadj: f64 = 0.25,
    rotated: bool = false,
    probability_scale: f64 = 1,
};

pub fn parse(a: std.mem.Allocator, d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error!Statement {
    const key = t[i.*].text;
    const kind: data.Kind = if (eq(key, "cdfplot")) .cdf else if (eq(key, "ppplot")) .pp else if (eq(key, "qqplot")) .qq else if (eq(key, "probplot")) .probability else return d.fail(error.ParseError, 0, "UNIVARIATE: invalid plot statement", .{});
    i.* += 1;
    const names = try variables.parse(a, t, i);
    var statement: Statement = .{ .kind = kind, .variables = names, .curves = .{ .requests = &.{}, .percents = &.{}, .noprint = true, .midpercents = false }, .probability_scale = if (kind == .cdf or kind == .probability) 100 else 1 };
    if (t[i.*].tag == .slash) i.* += 1 else if (t[i.*].tag != .semicolon and t[i.*].tag != .eof) return d.fail(error.ParseError, 0, "UNIVARIATE: expected plot variable list or slash", .{});
    while (t[i.*].tag != .semicolon and t[i.*].tag != .eof) {
        const option = t[i.*].text;
        if (parameters.family(option) != null or eq(option, "weibull2")) {
            if (statement.curves.requests.len != 0) return d.fail(error.ParseError, 0, "UNIVARIATE: a plot statement accepts only one distribution family", .{});
            statement.weibull2 = eq(option, "weibull2");
            if (statement.weibull2 and (kind == .cdf or kind == .pp)) return d.fail(error.ParseError, 0, "UNIVARIATE: WEIBULL2 is a QQPLOT/PROBPLOT option", .{});
            statement.curves = try parameters.parsePlot(a, d, t, i);
            continue;
        }
        i.* += 1;
        if (eq(option, "rotate") and (kind == .qq or kind == .probability)) {
            statement.rotated = true;
            continue;
        }
        if (t[i.*].tag != .eq) return proc.failGap(d, 0, "UNIVARIATE: plot option {s} is not supported by the numerical consumer", .{option});
        i.* += 1;
        if ((eq(option, "rankadj") or eq(option, "nadj")) and (kind == .qq or kind == .probability)) {
            const number = try parameters.numeric(d, t, i);
            if (eq(option, "rankadj")) statement.rankadj = number else statement.nadj = number;
        } else if (eq(option, "vscale") and kind == .cdf) {
            if (eq(t[i.*].text, "percent")) statement.probability_scale = 100 else if (eq(t[i.*].text, "proportion")) statement.probability_scale = 1 else return d.fail(error.ParseError, 0, "UNIVARIATE: CDFPLOT VSCALE requires PERCENT or PROPORTION", .{});
            i.* += 1;
        } else return proc.failGap(d, 0, "UNIVARIATE: unsupported numerical plot option {s}", .{option});
    }
    if (statement.curves.requests.len == 0) {
        const request = try a.alloc(fitting.Request, 1);
        request[0] = .{ .family = .normal };
        statement.curves.requests = request;
    }
    const quantile = kind == .qq or kind == .probability;
    if (!quantile and statement.curves.requests.len != 1) return d.fail(error.ParseError, 0, "UNIVARIATE: CDFPLOT/PPPLOT accept scalar distribution parameters", .{});
    if (statement.curves.noline and kind != .pp) return d.fail(error.ParseError, 0, "UNIVARIATE: NOLINE applies to PPPLOT", .{});
    for (statement.curves.requests) |request| {
        if (request.family == .sb or request.family == .su or (quantile and request.family == .igauss)) return d.fail(error.ParseError, 0, "UNIVARIATE: distribution is not available for this plot statement", .{});
        if (!quantile) continue;
        switch (request.family) {
            .beta => if (!request.specified("alpha") or !request.specified("beta")) return d.fail(error.ParseError, 0, "UNIVARIATE: beta QQ/PROBPLOT requires ALPHA and BETA", .{}),
            .gamma, .pareto, .power => if (!request.specified("alpha")) return d.fail(error.ParseError, 0, "UNIVARIATE: {s} QQ/PROBPLOT requires ALPHA", .{@tagName(request.family)}),
            .lognormal => if (!request.specified("sigma")) return d.fail(error.ParseError, 0, "UNIVARIATE: lognormal QQ/PROBPLOT requires SIGMA", .{}),
            .weibull => if (!statement.weibull2 and !request.specified("c")) return d.fail(error.ParseError, 0, "UNIVARIATE: Weibull QQ/PROBPLOT requires C", .{}),
            else => {},
        }
    }
    return statement;
}

fn curve(d: *diag.Diagnostics, x: []const f64, request: fitting.Request, quantile: bool) diag.Error!dist.Distribution {
    if (!quantile) return fitting.fit(d, x, request);
    var estimate = false;
    inline for (std.meta.fields(dist.Parameters), 0..) |field, j| {
        if (request.specified_fields.isSet(j) and @field(request, field.name) == null) estimate = true;
    }
    if (estimate) return fitting.fit(d, x, request);
    var p: dist.Parameters = .{};
    inline for (std.meta.fields(dist.Parameters)) |field| if (@field(request, field.name)) |v| {
        @field(p, field.name) = v;
    };
    const result: dist.Distribution = .{ .family = request.family, .p = p };
    try result.validate(d);
    return result;
}

/// Sorted finite values after FREQ expansion, without graphical side effects.
pub fn calculate(a: std.mem.Allocator, d: *diag.Diagnostics, x: []const f64, statement: Statement, request: fitting.Request, variable: @import("../dataset.zig").Column, keys: []const data.Key) diag.Error!data.Plot {
    const quantile = statement.kind == .qq or statement.kind == .probability;
    const fitted = try curve(d, x, request, quantile);
    const points = try a.alloc(data.Point, x.len);
    var reference: ?data.Reference = null;
    if (quantile) {
        const result = try values.quantilePlot(a, d, x, fitted, -statement.rankadj, statement.nadj, statement.weibull2);
        const line = switch (request.family) {
            .normal, .gumbel => request.specified("mu") and request.specified("sigma"),
            .lognormal => request.specified("theta") and request.specified("zeta"),
            .weibull => if (statement.weibull2) request.specified("sigma") and request.specified("c") else request.specified("theta") and request.specified("sigma"),
            else => request.specified("theta") and request.specified("sigma"),
        };
        if (line) reference = .{ .intercept = result.intercept, .slope = result.slope };
        for (result.points, points, 0..) |p, *point, j| point.* = .{
            .x = if (statement.kind == .qq) p.theoretical else p.probability * statement.probability_scale,
            .y = p.observed,
            .observed = x[j],
            .empirical_probability = @as(f64, @floatFromInt(j + 1)) / @as(f64, @floatFromInt(x.len)),
            .theoretical_probability = p.probability,
            .theoretical_quantile = p.theoretical,
        };
    } else {
        const n: f64 = @floatFromInt(x.len);
        var tie_end: usize = 0;
        for (x, points, 0..) |v, *point, j| {
            if (j == tie_end) {
                tie_end = j + 1;
                while (tie_end < x.len and x[tie_end] == v) tie_end += 1;
            }
            const empirical = @as(f64, @floatFromInt(if (statement.kind == .cdf) tie_end else j + 1)) / n;
            const theoretical = fitted.cdf(v);
            point.* = .{ .x = if (statement.kind == .cdf) v else theoretical, .y = empirical * statement.probability_scale, .observed = v, .empirical_probability = empirical, .theoretical_probability = theoretical };
        }
        if (statement.kind == .pp and !statement.curves.noline) reference = .{ .intercept = 0, .slope = 1 };
    }
    if (statement.rotated) for (points) |*point| std.mem.swap(f64, &point.x, &point.y);
    return .{ .kind = statement.kind, .variable = variable, .keys = keys, .distribution = fitted, .points = points, .reference = reference, .rotated = statement.rotated, .probability_scale = statement.probability_scale, .weibull2 = statement.weibull2 };
}

const Collector = struct {
    a: std.mem.Allocator,
    plots: std.ArrayList(data.Plot) = .empty,
    fn emit(raw: ?*anyopaque, plot: data.Plot) diag.Error!void {
        const self: *Collector = @ptrCast(@alignCast(raw.?));
        try self.plots.append(self.a, plot);
    }
};

test "UNIVARIATE public CDF PP QQ and probability paths deliver BY CLASS FREQ numerics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var library = @import("../exec.zig").Library.init(a);
    var ds = Dataset.init(a, "d");
    for ([_][]const u8{ "b", "c", "x", "f" }) |name| _ = try ds.addColumn(name, .num);
    const rows = [_][4]f64{ .{ 1, 1, 1, 2 }, .{ 1, 1, 2, 1 }, .{ 1, 1, std.math.nan(f64), 4 }, .{ 1, 2, 4, 1 }, .{ 1, 2, 8, 1 }, .{ 2, 1, 3, 1 }, .{ 2, 1, 5, 2 }, .{ 2, 2, 10, 1 }, .{ 2, 2, 14, 1 } };
    for (rows) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] } });
    try library.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    var collector: Collector = .{ .a = a };
    const t = try @import("../lexer.zig").tokenize(a, "proc univariate data=d noprint;by b;class c;freq f;var x;" ++
        "cdfplot x / normal(mu=0 sigma=2);ppplot x / normal(mu=0 sigma=2);" ++
        "qqplot x / normal(mu=est sigma=est);" ++
        "probplot x / weibull2(theta=0 sigma=2 c=3) rankadj=-.5 nadj=0;run;", &d);
    try proc.runUnivariate(.{ .arena = a, .lib = &library, .diags = &d, .univariate_plot_sink = .{ .context = &collector, .emit = Collector.emit } }, &out, t);
    try std.testing.expect(!d.hasErrors());
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    try std.testing.expectEqual(@as(usize, 16), collector.plots.items.len);
    const cdf = collector.plots.items[0];
    try std.testing.expectEqual(data.Kind.cdf, cdf.kind);
    try std.testing.expectEqual(@as(usize, 3), cdf.points.len);
    try std.testing.expectApproxEqAbs(@as(f64, 200.0 / 3.0), cdf.points[0].y, 1e-12);
    try std.testing.expectEqual(cdf.points[0].y, cdf.points[1].y);
    try std.testing.expectApproxEqAbs(@as(f64, 0.691462461274), cdf.points[0].theoretical_probability, 1e-12);
    try std.testing.expectEqual(@as(f64, 1), cdf.keys[0].value.num);
    try std.testing.expect(cdf.keys[1].class);
    const pp = collector.plots.items[4];
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 3.0), pp.points[0].y, 1e-12);
    try std.testing.expectEqual(@as(f64, 1), pp.reference.?.slope);
    const qq = collector.plots.items[8];
    try std.testing.expectApproxEqAbs(@as(f64, 4.0 / 3.0), qq.reference.?.intercept, 1e-12);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 1.0 / 3.0)), qq.reference.?.slope, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0), qq.points[1].x, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -0.86942377328888), qq.points[0].x, 1e-11);
    const probability = collector.plots.items[12];
    try std.testing.expectApproxEqAbs(@as(f64, 100.0 / 6.0), probability.points[0].x, 1e-12);
    try std.testing.expectEqual(@as(f64, 1), probability.points[0].observed);
    try std.testing.expectEqual(@as(f64, 0), probability.points[0].y);
    try std.testing.expectApproxEqAbs(@log(@as(f64, 2)), probability.reference.?.intercept, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 3.0), probability.reference.?.slope, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -1.7019833552815), probability.points[0].theoretical_quantile.?, 1e-11);
    try std.testing.expectApproxEqAbs(@as(f64, 0.58319808078265), probability.points[2].theoretical_quantile.?, 1e-11);
}

test "UNIVARIATE numerical plots retain graphics guard and required-shape diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var library = @import("../exec.zig").Library.init(a);
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    try ds.appendRow(&.{.{ .num = 1 }});
    try ds.appendRow(&.{.{ .num = 2 }});
    try library.put("d", &ds);
    const lex = @import("../lexer.zig");
    inline for (.{ "cdfplot", "ppplot", "qqplot", "probplot" }) |keyword| {
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const t = try lex.tokenize(a, "proc univariate data=d noprint;" ++ keyword ++ " x;run;", &d);
        diag.resetGap();
        try std.testing.expectError(error.ParseError, proc.runUnivariate(.{ .arena = a, .lib = &library, .diags = &d }, &out, t));
        try std.testing.expect(diag.gapHit());
        try std.testing.expect(std.mem.indexOf(u8, d.list.items[0].message, "plot consumer") != null);
    }
    var d = diag.Diagnostics.init(a);
    var i: usize = 0;
    const t = try lex.tokenize(a, "qqplot x / gamma;", &d);
    diag.resetGap();
    try std.testing.expectError(error.ParseError, parse(a, &d, t, &i));
    try std.testing.expect(!diag.gapHit());
    try std.testing.expect(std.mem.indexOf(u8, d.list.items[0].message, "ALPHA") != null);
}

test "UNIVARIATE QQ fixed shapes avoid unwanted location-scale fits and map SLOPE" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const lex = @import("../lexer.zig");
    var i: usize = 0;
    const t = try lex.tokenize(a, "qqplot x / gamma(alpha=1 2);", &d);
    const statement = try parse(a, &d, t, &i);
    try std.testing.expectEqual(@as(usize, 2), statement.curves.requests.len);
    for (statement.curves.requests) |request| {
        const plot = try calculate(a, &d, &.{ -5, -5, -5 }, statement, request, .{ .name = "x", .type = .num }, &.{});
        try std.testing.expect(plot.reference == null);
        try std.testing.expectEqual(@as(f64, -5), plot.points[1].y);
        try std.testing.expect(plot.points[1].x > 0);
    }
    i = 0;
    const slope = try lex.tokenize(a, "probplot x / lognormal(sigma=1 theta=0 slope=2) rotate;", &d);
    const s = try parse(a, &d, slope, &i);
    const plot = try calculate(a, &d, &.{ 1, 2, 3 }, s, s.curves.requests[0], .{ .name = "x", .type = .num }, &.{});
    try std.testing.expectApproxEqAbs(@as(f64, 2), plot.reference.?.slope, 1e-12);
    try std.testing.expectEqual(@as(f64, 50), plot.points[1].y);
    try std.testing.expectEqual(@as(f64, 2), plot.points[1].x);
}

pub fn execute(cx: proc.ProcCtx, ds: *Dataset, acols: []const usize, ccols: []const usize, bcols: []const usize, wc: ?usize, opt: univ.Options, levels: []const h.FmtLevels, statements: []const Statement, has_var: bool) diag.Error!void {
    const a = cx.arena;
    for (statements) |statement| {
        if (wc != null) return cx.diags.fail(error.ParseError, 0, "A WEIGHT variable cannot be used together with a CDFPLOT, HISTOGRAM, PPPLOT, PROBPLOT, or QQPLOT statement.", .{});
        const source = opt.source orelse ds;
        const cols = try variables.resolve(a, cx.diags, source, acols, statement.variables, has_var);
        const sink = cx.univariate_plot_sink orelse return proc.failGap(cx.diags, 0, "UNIVARIATE: {s} graphics require a plot consumer; graphics rendering is not supported", .{@tagName(statement.kind)});
        for (try univ.bySlices(a, ds.rows.items, bcols, opt)) |bs| {
            var bd = Dataset.init(a, ds.name);
            bd.columns = ds.columns;
            try bd.rows.appendSlice(a, bs.rows);
            const groups = try h.collectGroups(a, &bd, ccols);
            try univ.orderGroups(a, &bd, groups, ccols, levels, null, opt);
            for (groups) |group| {
                if (group.rows.len == 0) continue;
                var gd = Dataset.init(a, ds.name);
                gd.columns = ds.columns;
                try gd.rows.appendSlice(a, group.rows);
                const analysis = try univ.analysisView(a, &gd, cols, null, opt);
                const keys = try a.alloc(data.Key, bcols.len + ccols.len);
                for (keys, 0..) |*key, j| {
                    const is_class = j >= bcols.len;
                    const ci = if (is_class) ccols[j - bcols.len] else bcols[j];
                    var column = source.columns.items[ci];
                    const value = if (is_class) univ.classRepresentative(&bd, opt, null, ccols, ci, group.rep) else group.rep[ci];
                    if (h.fmtLevelsFor(levels, ci)) |fl| column.format = fl.spec;
                    const text = if (value == .str) value.str else try @import("../format.zig").apply(a, value, column.format orelse "BEST12.");
                    key.* = .{ .column = column, .value = value, .display = std.mem.trim(u8, text, " "), .class = is_class };
                }
                for (cols) |ci| {
                    var x: std.ArrayList(f64) = .empty;
                    for (analysis.ds.rows.items) |row| {
                        const v = h.toNum(row[ci]);
                        if (!std.math.isNan(v)) try x.append(a, v);
                    }
                    if (x.items.len == 0) continue;
                    std.mem.sort(f64, x.items, {}, std.sort.asc(f64));
                    for (statement.curves.requests) |request| try sink.emit(sink.context, try calculate(a, cx.diags, x.items, statement, request, source.columns.items[ci], keys));
                }
            }
        }
    }
}
