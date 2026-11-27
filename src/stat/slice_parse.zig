//! Shared SLICE syntax/defaults, S154 physical pp.539-543. Consumers resolve
//! the single CLASS interaction and actual L matrix; no syntax-only success.
const std = @import("std");
const lex = @import("../lexer.zig");
const diag = @import("../diag.zig");
const proc = @import("../proc.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const Rule = struct { factors: []const []const u8, values: []const []const u8 = &.{} };
pub const Options = struct { means: bool = false, nof: bool = false, diff: bool = false, cl: bool = false, alpha: f64 = 0.05, df: ?f64 = null, singular: f64 = 1e-4, adjust: @import("lsmeans_inference.zig").Adjustment = .none };
pub const Spec = struct { effect: []const lex.Token, rules: []const Rule, options: Options, line: usize };
pub fn applicable(procedure: []const u8) bool {
    for ([_][]const u8{ "GEE", "GENMOD", "GLIMMIX", "LIFEREG", "LOGISTIC", "MIXED", "ORTHOREG", "PHREG", "PLM", "PROBIT", "SURVEYLOGISTIC", "SURVEYPHREG", "SURVEYREG", "RELIABILITY" }) |name| if (eq(name, procedure)) return true;
    return false;
}
const Reader = struct {
    cx: proc.ProcCtx,
    t: []const lex.Token,
    i: usize,
    line: usize,
    fn at(r: Reader, tag: lex.Tag) bool {
        return r.i < r.t.len and r.t[r.i].tag == tag;
    }
    fn bad(r: Reader) diag.Error {
        return r.cx.diags.fail(error.ParseError, r.line, "SLICE: invalid statement or option", .{});
    }
    fn rule(r: *Reader) diag.Error!Rule {
        var factors: std.ArrayList([]const u8) = .empty;
        if (!r.at(.name)) return r.bad();
        try factors.append(r.cx.arena, r.t[r.i].text);
        r.i += 1;
        while (r.at(.star)) {
            r.i += 1;
            if (!r.at(.name)) return r.bad();
            try factors.append(r.cx.arena, r.t[r.i].text);
            r.i += 1;
        }
        var values: std.ArrayList([]const u8) = .empty;
        if (r.at(.eq)) {
            r.i += 1;
            const list = r.at(.lparen);
            if (list) r.i += 1;
            if (r.at(.number)) return proc.failGap(r.cx.diags, r.line, "SLICE: unquoted formatted-value selectors are not independently verified", .{});
            while (r.at(.string)) {
                try values.append(r.cx.arena, r.t[r.i].text);
                r.i += 1;
                if (list and r.at(.comma)) r.i += 1;
            }
            if (values.items.len == 0) return r.bad();
            if (list) {
                if (!r.at(.rparen)) return r.bad();
                r.i += 1;
            }
        }
        return .{ .factors = factors.items, .values = values.items };
    }
};
pub fn parse(cx: proc.ProcCtx, procedure: []const u8, t: []const lex.Token, line: usize) diag.Error!Spec {
    if (!applicable(procedure)) return cx.diags.fail(error.ParseError, line, "SLICE is not applicable to PROC {s}", .{procedure});
    var slash: usize = 0;
    while (slash < t.len and t[slash].tag != .slash) slash += 1;
    if (slash == 0) return cx.diags.fail(error.ParseError, line, "SLICE requires one interaction effect", .{});
    var s = Spec{ .effect = t[0..slash], .rules = &.{}, .options = .{}, .line = line };
    var rules: std.ArrayList(Rule) = .empty;
    var r = Reader{ .cx = cx, .t = t, .i = if (slash < t.len) slash + 1 else slash, .line = line };
    while (r.i < t.len) {
        if (!r.at(.name)) return r.bad();
        const name = t[r.i].text;
        r.i += 1;
        if (eq(name, "sliceby") or eq(name, "simple")) {
            if (r.at(.eq)) r.i += 1;
            const list = r.at(.lparen);
            if (list) r.i += 1;
            while (true) {
                try rules.append(cx.arena, try r.rule());
                if (!list) break;
                if (r.at(.rparen)) {
                    r.i += 1;
                    break;
                }
                if (r.at(.comma)) r.i += 1;
                if (!r.at(.name)) return r.bad();
            }
        } else if (eq(name, "means")) s.options.means = true else if (eq(name, "nomeans")) s.options.means = false else if (eq(name, "nof")) {
            s.options.nof = true;
            s.options.diff = true;
        } else if (eq(name, "cl")) s.options.cl = true else if (eq(name, "diff") or eq(name, "pdiff")) {
            s.options.diff = true;
            if (r.at(.eq)) {
                r.i += 1;
                if (!r.at(.name)) return r.bad();
                if (!eq(t[r.i].text, "all")) return proc.failGap(cx.diags, line, "SLICE: control differences are not implemented", .{});
                r.i += 1;
            }
        } else if (eq(name, "adjust")) {
            if (!r.at(.eq)) return r.bad();
            r.i += 1;
            if (!r.at(.name)) return r.bad();
            const adjustment = t[r.i].text;
            r.i += 1;
            s.options.adjust = if (eq(adjustment, "bon")) .bon else if (eq(adjustment, "sidak")) .sidak else if (eq(adjustment, "tukey")) .tukey else return proc.failGap(cx.diags, line, "SLICE: requested comparison adjustment is not implemented", .{});
            s.options.diff = true;
        } else if (eq(name, "alpha") or eq(name, "df") or eq(name, "singular")) {
            if (!r.at(.eq)) return r.bad();
            r.i += 1;
            if (!r.at(.number)) return r.bad();
            const v = std.fmt.parseFloat(f64, t[r.i].text) catch return r.bad();
            r.i += 1;
            if (!std.math.isFinite(v) or v <= 0 or (!eq(name, "df") and v >= 1)) return r.bad();
            if (eq(name, "df")) s.options.df = v else if (eq(name, "singular")) s.options.singular = v else {
                s.options.alpha = v;
                s.options.cl = true;
            }
        } else if (eq(name, "adjdfe")) {
            if (!r.at(.eq)) return r.bad();
            r.i += 1;
            if (!r.at(.name)) return r.bad();
            if (!eq(t[r.i].text, "source")) return proc.failGap(cx.diags, line, "SLICE: rowwise adjustment degrees of freedom are not implemented", .{});
            r.i += 1;
        } else {
            for ([_][]const u8{ "at", "bylevel", "corr", "cov", "e", "exp", "ilink", "oddsratio", "om", "obsmargins", "plots", "lines", "stepdown", "seed", "simulate", "dunnett", "scheffe" }) |known| if (eq(name, known)) return proc.failGap(cx.diags, line, "SLICE: option {s} is not implemented", .{name});
            return r.bad();
        }
    }
    s.rules = rules.items;
    return s;
}
