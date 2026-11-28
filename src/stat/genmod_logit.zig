//! PROC GENMOD (SAS/STAT 15.4 ch.51) — STAT-GENMOD-003: the events/trials
//! binomial-logit step with CLASS main effects in the GLM parameterization,
//! the MODEL option table, and the listing of ch.51 Example 51.1 (Model
//! Information, observation/event/trial counts, Class Level Information,
//! Response Profile, Criteria For Assessing Goodness Of Fit, Analysis Of
//! Maximum Likelihood Parameter Estimates with Wald or LRCI limits).
//! Physical PDF pp.3526–3529 (CLASS), 3544–3555 (MODEL), 3580–3581
//! (parameterization), 3583–3584 (confidence intervals). Kernel: genmod_binomial.zig.
//!
//! Design (p.3580): intercept, then for each MODEL effect in order one column
//! for a continuous variable or one indicator column per CLASS level. With an
//! intercept the last level's column depends on the preceding ones; it is
//! reported with DF 0 and zero estimate, as in the reference listing.
//!
//! ponytail: the Wald-limit layout with a CLASS level column is the documented
//! table template (same columns as the LRCI reference listing with the Normal
//! listing's Wald heading); no SAS listing of exactly that combination was replayed.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const Value = @import("../value.zig").Value;
const genmod = @import("genmod.zig");
const kernel = @import("genmod_binomial.zig");
const chiTail = @import("logistic_fit.zig").chiTail;
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;

pub const Support = enum { implemented, gap };
pub const Option = struct { name: []const u8, owner: []const u8 };
/// MODEL statement options (Table 51.7, pp.3546–3555, with the aliases given
/// in the option entries). DIST=/LINK= are parsed separately. `owner` is the
/// ticket that implements the option; an empty owner means implemented here.
pub const model_options = [_]Option{
    .{ .name = "lrci", .owner = "" },
    .{ .name = "waldci", .owner = "" },
    .{ .name = "aggregate", .owner = "STAT-GENMOD-005" },
    .{ .name = "alpha", .owner = "STAT-GENMOD-012" },
    .{ .name = "alph", .owner = "STAT-GENMOD-012" },
    .{ .name = "a", .owner = "STAT-GENMOD-012" },
    .{ .name = "ciconv", .owner = "STAT-GENMOD-012" },
    .{ .name = "cl", .owner = "STAT-GENMOD-012" },
    .{ .name = "coding", .owner = "STAT-GENMOD-004" },
    .{ .name = "converge", .owner = "STAT-GENMOD-012" },
    .{ .name = "convh", .owner = "STAT-GENMOD-012" },
    .{ .name = "corrb", .owner = "STAT-GENMOD-012" },
    .{ .name = "covb", .owner = "STAT-GENMOD-012" },
    .{ .name = "descending", .owner = "STAT-GENMOD-004" },
    .{ .name = "desc", .owner = "STAT-GENMOD-004" },
    .{ .name = "diagnostics", .owner = "STAT-GENMOD-015" },
    .{ .name = "influence", .owner = "STAT-GENMOD-015" },
    .{ .name = "event", .owner = "STAT-GENMOD-004" },
    .{ .name = "exactmax", .owner = "STAT-GENMOD-010" },
    .{ .name = "expected", .owner = "STAT-GENMOD-012" },
    .{ .name = "id", .owner = "STAT-GENMOD-012" },
    .{ .name = "initial", .owner = "STAT-GENMOD-012" },
    .{ .name = "intercept", .owner = "STAT-GENMOD-012" },
    .{ .name = "itprint", .owner = "STAT-GENMOD-012" },
    .{ .name = "lognb", .owner = "STAT-GENMOD-005" },
    .{ .name = "maxiter", .owner = "STAT-GENMOD-012" },
    .{ .name = "maxit", .owner = "STAT-GENMOD-012" },
    .{ .name = "noint", .owner = "STAT-GENMOD-004" },
    .{ .name = "nolognb", .owner = "STAT-GENMOD-005" },
    .{ .name = "noscale", .owner = "STAT-GENMOD-005" },
    .{ .name = "obstats", .owner = "STAT-GENMOD-012" },
    .{ .name = "offset", .owner = "STAT-GENMOD-005" },
    .{ .name = "order", .owner = "STAT-GENMOD-004" },
    .{ .name = "predicted", .owner = "STAT-GENMOD-012" },
    .{ .name = "pred", .owner = "STAT-GENMOD-012" },
    .{ .name = "p", .owner = "STAT-GENMOD-012" },
    .{ .name = "reference", .owner = "STAT-GENMOD-004" },
    .{ .name = "ref", .owner = "STAT-GENMOD-004" },
    .{ .name = "residuals", .owner = "STAT-GENMOD-012" },
    .{ .name = "r", .owner = "STAT-GENMOD-012" },
    .{ .name = "scale", .owner = "STAT-GENMOD-005" },
    .{ .name = "pscale", .owner = "STAT-GENMOD-005" },
    .{ .name = "dscale", .owner = "STAT-GENMOD-005" },
    .{ .name = "scoring", .owner = "STAT-GENMOD-012" },
    .{ .name = "singular", .owner = "STAT-GENMOD-012" },
    .{ .name = "type1", .owner = "STAT-GENMOD-011" },
    .{ .name = "type3", .owner = "STAT-GENMOD-011" },
    .{ .name = "wald", .owner = "STAT-GENMOD-011" },
    .{ .name = "xvars", .owner = "STAT-GENMOD-012" },
};
pub fn modelOption(name: []const u8) ?Option {
    for (model_options) |o| if (eq(o.name, name)) return o;
    return null;
}

pub const Limits = enum { wald, lr };
pub const Column = struct {
    /// Index into Spec.effects.
    effect: usize,
    /// CLASS level index, null for a continuous variable.
    level: ?usize = null,
};
pub const Design = struct {
    /// rows*p row-major, column 0 the intercept.
    x: []f64,
    p: usize,
    /// One entry per column after the intercept.
    columns: []Column,
};

/// Position of column `ci` in the CLASS list, or null for a continuous effect.
fn classIndex(s: genmod.Spec, ci: usize) ?usize {
    return std.mem.indexOfScalar(usize, s.class, ci);
}

/// The GLM-parameterization design matrix of the used observations (p.3580).
pub fn design(a: A, s: genmod.Spec, sel: genmod.Selection, rows: []const []const Value) error{OutOfMemory}!Design {
    var columns: std.ArrayList(Column) = .empty;
    for (s.effects, 0..) |ci, e| {
        if (classIndex(s, ci)) |k| {
            for (0..sel.levels[k].levels.len) |level| try columns.append(a, .{ .effect = e, .level = level });
        } else try columns.append(a, .{ .effect = e });
    }
    const p = columns.items.len + 1;
    const x = try a.alloc(f64, sel.used * p);
    for (sel.rows, 0..) |ri, i| {
        x[i * p] = 1;
        for (columns.items, 1..) |c, j| {
            const ci = s.effects[c.effect];
            x[i * p + j] = if (c.level) |level|
                (if (sel.levels[classIndex(s, ci).?].row_to_level[ri] == level) 1 else 0)
            else
                rows[ri][ci].num;
        }
    }
    return .{ .x = x, .p = p, .columns = columns.items };
}

/// PROBCHI quantile chi-square(0.95; 1) = PROBIT(0.975)^2 (ALPHA= is a gap).
const z95: f64 = 1.959963984540054;
const chi95: f64 = z95 * z95;

fn padLeft(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
}
fn padRight(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendSlice(a, text);
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}
fn number(a: A, out: *Out, x: f64, decimals: usize, width: usize) !void {
    // -0.0000 is never printed by SAS.
    const text = try std.fmt.allocPrint(a, "{d:.[1]}", .{ x, decimals });
    var zero = text.len > 0 and text[0] == '-';
    for (text) |c| {
        if (c != '-' and c != '0' and c != '.') zero = false;
    }
    try padLeft(a, out, if (zero) text[1..] else text, width);
}
fn centered(a: A, out: *Out, title: []const u8, width: usize) !void {
    // Reference listing: an odd remainder puts the extra blank on the left.
    if (title.len < width) try out.appendNTimes(a, ' ', (width - title.len + 1) / 2);
    try out.appendSlice(a, title);
    try out.append(a, '\n');
}

const Result = struct {
    full: Design,
    /// Per design column: true = aliased (DF 0).
    alias: []const bool,
    /// Position of each full column in the reduced fit, when not aliased.
    reduced: []const usize,
    fit: kernel.Fit,
    lower: []const f64,
    upper: []const f64,
    events: f64,
    trials: f64,
};

fn render(a: A, out: *Out, s: genmod.Spec, sel: genmod.Selection, limits: Limits, r: Result) !void {
    const ds = s.input.ds;
    try out.appendSlice(a, "\nThe GENMOD Procedure\n\n");
    const upper = try std.ascii.allocUpperString(a, s.data_name);
    const data_name = if (std.mem.indexOfScalar(u8, upper, '.') == null) try std.fmt.allocPrint(a, "WORK.{s}", .{upper}) else upper;
    const info = [_][2][]const u8{
        .{ "Data Set", data_name },
        .{ "Distribution", "Binomial" },
        .{ "Link Function", "Logit" },
        .{ "Response Variable (Events)", ds.columns.items[s.response].name },
        .{ "Response Variable (Trials)", ds.columns.items[s.trials.?].name },
    };
    var value_width: usize = 0;
    for (info) |row| value_width = @max(value_width, row[1].len);
    try centered(a, out, "Model Information", 30 + value_width);
    try out.append(a, '\n');
    for (info) |row| {
        try padRight(a, out, row[0], 26);
        try padLeft(a, out, row[1], value_width + 4);
        try out.append(a, '\n');
    }
    try out.print(a, "\n\nNumber of Observations Read{d:>12}\nNumber of Observations Used{d:>12}\nNumber of Events           {d:>12.0}\nNumber of Trials           {d:>12.0}\n\n\n", .{ sel.read, sel.used, r.events, r.trials });

    if (s.class.len > 0) {
        var name_width: usize = 5;
        for (s.class) |ci| name_width = @max(name_width, ds.columns.items[ci].name.len);
        var values: std.ArrayList([]const u8) = .empty;
        var widest: usize = 6;
        for (sel.levels) |levels| {
            var text: Out = .empty;
            for (levels.levels) |level| {
                try text.appendSlice(a, std.mem.trim(u8, level.label, " "));
                try text.append(a, ' ');
            }
            widest = @max(widest, text.items.len);
            try values.append(a, text.items);
        }
        try centered(a, out, "Class Level Information", name_width + 16 + widest);
        try out.appendSlice(a, " \n");
        try padRight(a, out, "Class", name_width);
        try out.appendSlice(a, "      Levels    Values\n\n");
        for (s.class, sel.levels, values.items) |ci, levels, text| {
            try padRight(a, out, ds.columns.items[ci].name, name_width);
            try out.print(a, "{d:>12}    {s}\n", .{ levels.levels.len, text });
        }
        try out.appendSlice(a, "\n\n");
    }

    try centered(a, out, "Response Profile", 33);
    try out.appendSlice(a, " \n Ordered    Binary          Total\n   Value    Outcome     Frequency\n\n");
    try out.print(a, "       1    Event   {d:>13.0}\n       2    Nonevent{d:>13.0}\n\n\n", .{ r.events, r.trials - r.events });

    const f = r.fit;
    const n: f64 = @floatFromInt(sel.used);
    const k: f64 = @floatFromInt(f.q);
    const df = n - k;
    try centered(a, out, "Criteria For Assessing Goodness Of Fit", 64);
    try out.appendSlice(a, " \nCriterion                     DF           Value        Value/DF\n\n");
    // The scale is held fixed at 1, so the scaled statistics equal the unscaled ones.
    for ([_][]const u8{ "Deviance", "Scaled Deviance", "Pearson Chi-Square", "Scaled Pearson X2" }, [_]f64{ f.deviance, f.deviance, f.pearson, f.pearson }) |label, value| {
        try padRight(a, out, label, 24);
        try number(a, out, df, 0, 8);
        try number(a, out, value, 4, 16);
        try number(a, out, value / df, 4, 16);
        try out.append(a, '\n');
    }
    // The fixed scale is not a parameter: k regression coefficients, n observations.
    const aic = -2 * f.full_loglik + 2 * k;
    for ([_][]const u8{ "Log Likelihood", "Full Log Likelihood", "AIC (smaller is better)", "AICC (smaller is better)", "BIC (smaller is better)" }, [_]f64{ f.loglik, f.full_loglik, aic, aic + 2 * k * (k + 1) / (n - k - 1), -2 * f.full_loglik + k * @log(n) }) |label, value| {
        try padRight(a, out, label, 32);
        try number(a, out, value, 4, 16);
        try out.appendNTimes(a, ' ', 16);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n");
    try padRight(a, out, "Algorithm converged.", 75);
    try out.appendSlice(a, "\n\n\n");

    var name_width: usize = 9;
    for (s.effects) |ci| name_width = @max(name_width, ds.columns.items[ci].name.len);
    var level_width: usize = 0;
    for (r.full.columns) |c| if (c.level) |level| {
        const ci = s.effects[c.effect];
        level_width = @max(level_width, std.mem.trim(u8, sel.levels[classIndex(s, ci).?].levels[level].label, " ").len);
    };
    // Parameter name, then (with CLASS effects) a 4-blank gap and the level column.
    const lead = name_width + (if (level_width > 0) 4 + level_width else 0);
    try centered(a, out, "Analysis Of Maximum Likelihood Parameter Estimates", lead + 82);
    try out.appendSlice(a, " \n");
    try out.appendNTimes(a, ' ', lead + 6);
    try out.appendSlice(a, if (limits == .lr) "                Standard    Likelihood Ratio 95%          Wald\n" else "                Standard     Wald 95% Confidence          Wald\n");
    try padRight(a, out, "Parameter", lead);
    try out.appendSlice(a, "    DF");
    try out.appendSlice(a, if (limits == .lr) "    Estimate       Error      Confidence Limits     Chi-Square    Pr > ChiSq\n\n" else "    Estimate       Error           Limits           Chi-Square    Pr > ChiSq\n\n");
    for (0..r.full.p) |j| {
        var label: []const u8 = "";
        if (j == 0) {
            try padRight(a, out, "Intercept", name_width);
        } else {
            const c = r.full.columns[j - 1];
            const ci = s.effects[c.effect];
            try padRight(a, out, ds.columns.items[ci].name, name_width);
            if (c.level) |level| label = std.mem.trim(u8, sel.levels[classIndex(s, ci).?].levels[level].label, " ");
        }
        if (level_width > 0) {
            try out.appendSlice(a, "    ");
            try padRight(a, out, label, level_width);
        }
        if (r.alias[j]) {
            try out.appendSlice(a, "     0      0.0000      0.0000      0.0000      0.0000           .           .    \n");
            continue;
        }
        const m = r.reduced[j];
        const b = f.beta[m];
        const se = @sqrt(f.cov[m * f.q + m]);
        const chi = (b / se) * (b / se);
        const pv = chiTail(chi, 1);
        try out.appendSlice(a, "     1");
        try number(a, out, b, 4, 12);
        try number(a, out, se, 4, 12);
        try number(a, out, r.lower[m], 4, 12);
        try number(a, out, r.upper[m], 4, 12);
        try number(a, out, chi, 2, 14);
        if (pv < 0.0001) try padLeft(a, out, "<.0001", 14) else try number(a, out, pv, 4, 14);
        try out.append(a, '\n');
    }
    try padRight(a, out, "Scale", lead);
    try out.appendSlice(a, "     0      1.0000      0.0000      1.0000      1.0000");
    try out.appendNTimes(a, ' ', 28);
    try out.appendSlice(a, "\n\nNOTE: The scale parameter was held fixed.\n");
}

/// Runs the events/trials binomial step. The caller has parsed the step,
/// selected the observations (one group, no BY) and rejected later statements.
pub fn run(cx: proc.ProcCtx, out: *Out, s: genmod.Spec, sel: genmod.Selection, rows: []const []const Value, l0: usize) diag.Error!void {
    const a = cx.arena;
    if (s.dist) |d| {
        if (!eq(d, "binomial") and !eq(d, "bin") and !eq(d, "b"))
            return proc.failGap(cx.diags, l0, "PROC GENMOD: events/trials responses with DIST={s} are not verified (only DIST=BINOMIAL)", .{d});
    } else return proc.failGap(cx.diags, l0, "PROC GENMOD: events/trials responses without DIST=BINOMIAL are not verified (STAT-GENMOD-005)", .{});
    // p.3548: the binomial default link is the logit.
    if (s.link) |v| if (!eq(v, "logit"))
        return proc.failGap(cx.diags, l0, "PROC GENMOD: LINK={s} is not implemented for DIST=BINOMIAL (only LINK=LOGIT; STAT-GENMOD-005)", .{v});
    var limits: Limits = .wald;
    var lrci = false;
    var waldci = false;
    for (s.model_options) |name| {
        const option = modelOption(name) orelse return cx.diags.fail(error.ParseError, l0, "PROC GENMOD: {s} is not a valid MODEL statement option", .{name});
        if (option.owner.len > 0) return proc.failGap(cx.diags, l0, "PROC GENMOD: MODEL option {s} is not implemented ({s})", .{ name, option.owner });
        if (eq(option.name, "lrci")) lrci = true else waldci = true;
    }
    // The section does not say which limits are printed when both are requested.
    if (lrci and waldci) return proc.failGap(cx.diags, l0, "PROC GENMOD: LRCI together with WALDCI is not verified", .{});
    if (lrci) limits = .lr;
    if (s.by_cols.len > 0) return proc.failGap(cx.diags, l0, "PROC GENMOD: BY groups with a binomial model are not verified (STAT-GENMOD-003 remaining gap)", .{});
    if (s.frequency != null or s.weight != null) return proc.failGap(cx.diags, l0, "PROC GENMOD: FREQ and WEIGHT with a binomial model are not verified (STAT-GENMOD-005)", .{});
    if (s.output != null) return proc.failGap(cx.diags, l0, "PROC GENMOD: OUTPUT for a binomial model is not implemented (STAT-GENMOD-018)", .{});
    for (s.effects, 0..) |ci, j| if (std.mem.indexOfScalar(usize, s.effects[0..j], ci) != null)
        return proc.failGap(cx.diags, l0, "PROC GENMOD: a repeated MODEL effect is not verified", .{});

    const r = try a.alloc(f64, sel.used);
    const n = try a.alloc(f64, sel.used);
    var events: f64 = 0;
    var trials: f64 = 0;
    for (sel.rows, 0..) |ri, i| {
        r[i] = rows[ri][s.response].num;
        n[i] = rows[ri][s.trials.?].num;
        // p.3544 calls such observations not valid; how SAS counts and reports
        // them, and noninteger counts in the printed totals, is not verified.
        if (!kernel.validObservation(r[i], n[i]))
            return proc.failGap(cx.diags, l0, "PROC GENMOD: an observation with invalid events/trials values (events<0, trials<=0 or events>trials) is not verified", .{});
        if (r[i] != @floor(r[i]) or n[i] != @floor(n[i]))
            return proc.failGap(cx.diags, l0, "PROC GENMOD: noninteger events/trials values are not verified", .{});
        events += r[i];
        trials += n[i];
    }
    const full = try design(a, s, sel, rows);
    const alias = try kernel.aliased(a, full.x, sel.used, full.p, kernel.singular_default);
    // Only the documented GLM-parameterization dependence (the last level of a
    // CLASS main effect, given the intercept) is reported; any other linear
    // dependence has unverified notes and DF, so it stays loud.
    for (alias, 0..) |flag, j| {
        var expected = false;
        if (j > 0) if (full.columns[j - 1].level) |level| {
            const k = classIndex(s, s.effects[full.columns[j - 1].effect]).?;
            expected = level + 1 == sel.levels[k].levels.len;
        };
        if (flag != expected) return proc.failGap(cx.diags, l0, "PROC GENMOD: linearly dependent model columns beyond the CLASS reference levels are not implemented (STAT-GENMOD-004)", .{});
    }
    var q: usize = 0;
    const reduced = try a.alloc(usize, full.p);
    for (alias, 0..) |flag, j| {
        reduced[j] = q;
        if (!flag) q += 1;
    }
    if (sel.used <= q) return proc.failGap(cx.diags, l0, "PROC GENMOD: a fit with {d} usable observations for {d} parameters is not verified", .{ sel.used, q });
    const x = try a.alloc(f64, sel.used * q);
    for (0..sel.used) |i| for (alias, 0..) |flag, j| {
        if (!flag) x[i * q + reduced[j]] = full.x[i * full.p + j];
    };
    const f = kernel.fitLogit(a, x, r, n, q) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Singular => return proc.failGap(cx.diags, l0, "PROC GENMOD: a singular information matrix is not implemented (STAT-GENMOD-004)", .{}),
        error.NotConverged, error.Unbounded => return proc.failGap(cx.diags, l0, "PROC GENMOD: the binomial fit did not converge (possible separation); nonconvergence reporting is not implemented", .{}),
    };
    const lower = try a.alloc(f64, q);
    const upper = try a.alloc(f64, q);
    for (0..q) |m| {
        if (limits == .wald) {
            const se = @sqrt(f.cov[m * q + m]);
            lower[m] = f.beta[m] - z95 * se;
            upper[m] = f.beta[m] + z95 * se;
            continue;
        }
        for ([_]bool{ false, true }) |side| {
            const v = (try kernel.quadraticLimit(a, x, r, n, f, m, side, chi95, kernel.ciconv_default)) orelse kernel.profileLimit(a, x, r, n, f, m, side, chi95) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return proc.failGap(cx.diags, l0, "PROC GENMOD: a likelihood ratio confidence limit without a finite solution is not verified", .{}),
            };
            if (side) upper[m] = v else lower[m] = v;
        }
    }
    try render(a, out, s, sel, limits, .{ .full = full, .alias = alias, .reduced = reduced, .fit = f, .lower = lower, .upper = upper, .events = events, .trials = trials });
    try cx.diags.note(0, "Algorithm converged.", .{});
    try cx.diags.note(0, "The scale parameter was held fixed.", .{});
}
