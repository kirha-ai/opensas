//! ODS listing selection. Procedure producers identify each output object before
//! it is sent to the listing. ODS OUTPUT datasets have a separate destination.
const std = @import("std");
const diag = @import("diag.zig");
const Token = @import("lexer.zig").Token;
const eq = std.ascii.eqlIgnoreCase;

const List = union(enum) {
    all,
    none,
    select: []const []const u8,
    exclude: []const []const u8,

    fn accepts(self: List, path: []const u8) bool {
        switch (self) {
            .all => return true,
            .none => return false,
            .select, .exclude => |patterns| {
                for (patterns) |pattern| {
                    if (path.len < pattern.len) continue;
                    const offset = path.len - pattern.len;
                    if ((offset == 0 or path[offset - 1] == '.') and eq(pattern, path[offset..])) return self == .select;
                }
                return self == .exclude;
            },
        }
    }

    fn endProc(self: *List) void {
        if (self.* == .select or self.* == .exclude) self.* = .all;
    }
};

pub const Listing = struct {
    open: bool = true,
    trace: ?*diag.Diagnostics = null,
    overall: List = .all,
    destination: List = .all,

    pub fn endProc(self: *Listing) void {
        self.overall.endProc();
        self.destination.endProc();
    }

    pub fn accepts(self: Listing, path: []const u8) bool {
        return self.open and self.overall.accepts(path) and self.destination.accepts(path);
    }

    pub fn traceObject(self: Listing, a: std.mem.Allocator, name: []const u8, label: ?[]const u8, template: ?[]const u8, path: []const u8) !void {
        const d = self.trace orelse return;
        const label_line = if (label) |v| try std.fmt.allocPrint(a, "Label:      {s}\n", .{v}) else "";
        const template_line = if (template) |v| try std.fmt.allocPrint(a, "Template:   {s}\n", .{v}) else "";
        try d.plainLine(try std.fmt.allocPrint(a, "Output Added:\n-------------\nName:       {s}\n{s}{s}Path:       {s}\n-------------", .{ name, label_line, template_line, path }));
    }

    pub fn filtered(self: Listing) bool {
        return !self.open or self.overall != .all or self.destination != .all;
    }

    /// Returns whether this is a listing control. Other destination options
    /// such as GPATH remain the responsibility of their own handlers.
    pub fn parse(self: *Listing, a: std.mem.Allocator, d: *diag.Diagnostics, t: []const Token) diag.Error!bool {
        if (t.len < 3 or t[1].tag != .name) return false;
        if (eq(t[1].text, "trace")) {
            if (t[2].tag != .name or (!eq(t[2].text, "on") and !eq(t[2].text, "off"))) return d.fail(error.ParseError, t[2].line, "ODS TRACE: expected ON or OFF", .{});
            if (t.len > 3 and t[3].tag != .semicolon and t[3].tag != .eof) {
                diag.markGap();
                return d.fail(error.ParseError, t[3].line, "ODS TRACE: unsupported option {s}", .{t[3].text});
            }
            self.trace = if (eq(t[2].text, "on")) d else null;
            return true;
        }
        const local = eq(t[1].text, "listing");
        var i: usize = if (local) 2 else 1;
        if (local) {
            if (t[i].tag == .semicolon or t[i].tag == .eof) {
                self.open = true;
                return true;
            }
            if (t[i].tag == .name and (eq(t[i].text, "close") or eq(t[i].text, "off"))) {
                if (t[i + 1].tag != .semicolon and t[i + 1].tag != .eof) return d.fail(error.ParseError, t[i].line, "ODS LISTING: unexpected option after {s}", .{t[i].text});
                self.open = false;
                self.destination = .all;
                return true;
            }
        }
        if (t[i].tag != .name) return false;
        const select = eq(t[i].text, "select");
        if (!select and !eq(t[i].text, "exclude")) return false;
        i += 1;
        if (i >= t.len or t[i].tag != .name) return d.fail(error.ParseError, 0, "ODS: expected selection name, ALL or NONE", .{});
        const target = if (local) &self.destination else &self.overall;
        if (eq(t[i].text, "all") or eq(t[i].text, "none")) {
            if (t[i + 1].tag != .semicolon and t[i + 1].tag != .eof) return d.fail(error.ParseError, t[i].line, "ODS: ALL and NONE must appear alone", .{});
            target.* = if (select == eq(t[i].text, "all")) .all else .none;
            return true;
        }
        var names: std.ArrayList([]const u8) = .empty;
        while (i < t.len and t[i].tag != .semicolon and t[i].tag != .eof) {
            if (t[i].tag != .name) return d.fail(error.ParseError, t[i].line, "ODS: expected output object name or path", .{});
            var name = t[i].text;
            var path = try pathPart(a, name);
            i += 1;
            while (i < t.len and t[i].tag == .dot) {
                i += 1;
                if (i >= t.len or t[i].tag != .name) return d.fail(error.ParseError, 0, "ODS: expected object name after dot", .{});
                name = t[i].text;
                path = try std.fmt.allocPrint(a, "{s}.{s}", .{ path, try pathPart(a, name) });
                i += 1;
            }
            if (!known(name)) {
                diag.markGap();
                return d.fail(error.ParseError, 0, "ODS: unsupported selection object {s}", .{name});
            }
            try names.append(a, path);
        }
        target.* = if (select) .{ .select = names.items } else .{ .exclude = names.items };
        return true;
    }
};

/// ODS trace quotes class levels and variable names that require a SAS name literal.
pub fn pathPart(a: std.mem.Allocator, name: []const u8) ![]const u8 {
    if (@import("functions.zig").isValidName(name)) return name;
    const escaped = try std.mem.replaceOwned(u8, a, name, "'", "''");
    return std.fmt.allocPrint(a, "'{s}'n", .{escaped});
}

const Identity = struct {
    name: []const u8,
    template: []const u8,
    label: ?[]const u8 = null,
};

const identities = [_]Identity{
    .{ .name = "Statistics", .template = "Stat.TTest.Statistics", .label = "Statistics" },
    .{ .name = "ConfLimits", .template = "Stat.TTest.ConfLimits", .label = "Confidence Limits" },
    .{ .name = "TTests", .template = "Stat.TTest.TTests", .label = "T-Tests" },
    .{ .name = "Equality", .template = "Stat.TTest.Equality", .label = "Equality of Variances" },
    .{ .name = "EquivLimits", .template = "Stat.TTest.EquivLimits", .label = "Equivalence Limits" },
    .{ .name = "EquivTests", .template = "Stat.TTest.EquivTests", .label = "Equivalence Tests" },
    .{ .name = "Bootstrap", .template = "Stat.TTest.Bootstrap", .label = "Bootstrap Statistics and Confidence Limits" },
    .{ .name = "CrossoverVarInfo", .template = "Stat.TTest.CrossoverVarInfo", .label = "Crossover Variable Information" },
    .{ .name = "VarInformation", .template = "base.corr.VarInfo", .label = "Variables Information" },
    .{ .name = "Sscp", .template = "base.corr.Matrix", .label = "SSCP Matrix" },
    .{ .name = "Csscp", .template = "base.corr.Matrix", .label = "CSSCP Matrix" },
    .{ .name = "Cov", .template = "base.corr.Matrix", .label = "Covariance Matrix" },
    .{ .name = "SimpleStats", .template = "base.corr.UniStat", .label = "Simple Statistics" },
    .{ .name = "CronbachAlpha", .template = "base.corr.Alpha", .label = "Cronbach Coefficient Alpha" },
    .{ .name = "CronbachAlphaDel", .template = "base.corr.AlphaDel", .label = "Cronbach Coefficient Alpha with Deleted Variable" },
    .{ .name = "PearsonCorr", .template = "base.corr.StackedMatrix", .label = "Pearson Correlations" },
    .{ .name = "SpearmanCorr", .template = "base.corr.StackedMatrix", .label = "Spearman Correlations" },
    .{ .name = "KendallCorr", .template = "base.corr.StackedMatrix", .label = "Kendall Correlations" },
    .{ .name = "HoeffdingCorr", .template = "base.corr.StackedMatrix", .label = "Hoeffding Correlations" },
    .{ .name = "FisherPearsonCorr", .template = "base.corr.FisherPearsonCorr" },
    .{ .name = "FisherSpearmanCorr", .template = "base.corr.FisherSpearmanCorr" },
    .{ .name = "PartialCsscp", .template = "base.corr.Matrix", .label = "Partial CSSCP Matrix" },
    .{ .name = "PartialCov", .template = "base.corr.Matrix", .label = "Partial Covariance Matrix" },
    .{ .name = "PartialPearsonCorr", .template = "base.corr.StackedMatrix", .label = "Pearson Partial Correlations" },
    .{ .name = "PartialSpearmanCorr", .template = "base.corr.StackedMatrix", .label = "Spearman Partial Correlations" },
    .{ .name = "PartialKendallCorr", .template = "base.corr.StackedMatrix", .label = "Kendall Partial Correlations" },
    .{ .name = "FisherPearsonPartialCorr", .template = "base.corr.FisherPearsonPartialCorr" },
    .{ .name = "FisherSpearmanPartialCorr", .template = "base.corr.FisherSpearmanPartialCorr" },
    .{ .name = "Moments", .template = "base.univariate.Moments", .label = "Moments" },
    .{ .name = "BasicMeasures", .template = "base.univariate.Measures", .label = "Basic Measures of Location and Variability" },
    .{ .name = "Modes", .template = "base.univariate.Modes", .label = "Modes" },
    .{ .name = "BasicIntervals", .template = "base.univariate.ConfLimits", .label = "Basic Confidence Limits" },
    .{ .name = "TestsForLocation", .template = "base.univariate.Location", .label = "Tests For Location" },
    .{ .name = "LocationCounts", .template = "base.univariate.LocCount", .label = "Location Counts" },
    .{ .name = "TestsForNormality", .template = "base.univariate.Normal", .label = "Tests For Normality" },
    .{ .name = "TrimmedMeans", .template = "base.univariate.Trim", .label = "Trimmed Means" },
    .{ .name = "WinsorizedMeans", .template = "base.univariate.Wins", .label = "Winsorized Means" },
    .{ .name = "RobustScale", .template = "base.univariate.Robustscale", .label = "Robust Measures of Scale" },
    .{ .name = "Quantiles", .template = "base.univariate.Quantiles", .label = "Quantiles" },
    .{ .name = "MissingValues", .template = "base.univariate.Missings", .label = "Missing Values" },
    .{ .name = "ExtremeObs", .template = "base.univariate.ExtObs", .label = "Extreme Observations" },
    .{ .name = "ExtremeValues", .template = "base.univariate.ExtVal", .label = "Extreme Values" },
    .{ .name = "Frequencies", .template = "base.univariate.Frequency", .label = "Frequencies" },
    .{ .name = "ParameterEstimates", .template = "base.univariate.FitParms", .label = "Parameter Estimates" },
    .{ .name = "GoodnessOfFit", .template = "base.univariate.FitGood", .label = "Goodness of Fit" },
    .{ .name = "HistogramBins", .template = "base.univariate.Bins", .label = "Bin Midpoints" },
    .{ .name = "Bins", .template = "base.univariate.BinPercents", .label = "Histogram Bins" },
    .{ .name = "FitQuantiles", .template = "base.univariate.FitQuant", .label = "Quantiles" },
};

fn identity(name: []const u8) ?Identity {
    for (identities) |obj| if (eq(name, obj.name)) return obj;
    return null;
}
// SAS/STAT15.4 physical pp.7267-7269. NPAR producers supply truthful names
// and paths directly; template names are omitted until independently verified.
const npar_names=[_][]const u8{"VarInfo","ABScores","ABTest","ABAnalysis","STScores","STTest","STAnalysis","KlotzScores","KlotzTest","KlotzAnalysis","MoodScores","MoodTest","MoodAnalysis","ConoverScores","ConoverTest","ConoverAnalysis","DataScores","DataScoresTest","DataScoresAnalysis","ClassMeans","ANOVA","WilcoxonScores","WilcoxonTest","KruskalWallisTest","MedianScores","MedianTest","MedianAnalysis","VWScores","VWTest","VWAnalysis","SavageScores","SavageTest","SavageAnalysis","KSTest","KSStats","KS2Stats","CVMTest","CVMStats","KuiperTest","KuiperStats","HodgesLehmann","StrataInfo","StrataMethod","WilcoxonStrata","WilcoxonStrataTest","MedianStrata","MedianStrataTest","VWStrata","VWStrataTest","SavageStrata","SavageStrataTest","DataScoresStrata","DataScoresStrataTest"};
fn known(name: []const u8) bool {
    for(npar_names) |n| if(eq(name,n)) return true;
    return identity(name) != null or @import("stat/graph_ods.zig").known(name);
}

/// A table's listing text can be suppressed after its numerical and typed ODS
/// production. The caller sets each boundary explicitly; no listing text is parsed.
pub const Tables = struct {
    selection: ?*const Listing = null,
    prefix: []const u8 = "",

    pub fn finish(self: Tables, a: std.mem.Allocator, out: *std.ArrayList(u8), start: usize, name: []const u8) !void {
        try self.section(a, out, start, name, true);
    }

    pub fn section(self: Tables, a: std.mem.Allocator, out: *std.ArrayList(u8), start: usize, name: []const u8, first: bool) !void {
        if (out.items.len == start) return;
        const selection = self.selection orelse return;
        if (!selection.filtered() and selection.trace == null) return;
        const path = try std.fmt.allocPrint(a, "{s}.{s}", .{ self.prefix, name });
        if (!selection.accepts(path)) {
            out.shrinkRetainingCapacity(start);
            return;
        }
        if (first and selection.trace != null) {
            const obj = identity(name) orelse return;
            try selection.traceObject(a, obj.name, obj.label, obj.template, path);
        }
    }
};
