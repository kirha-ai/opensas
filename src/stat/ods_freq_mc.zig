//! Monte Carlo ODS tables consume the estimates and seeds of the actual FREQ
//! simulations. Each family has one probability stream and one native schema.
const std = @import("std");
const A = std.mem.Allocator;
const diag = @import("../diag.zig");
const ods = @import("../ods.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const b = @import("ods_table.zig");
const dist = @import("freq_exact_distribution.zig");
const parse = @import("freq_exact_parse.zig");
const model = @import("freq_table.zig");
pub const Simulation = struct {
    family: parse.Family,
    sample: @FieldType(dist.MonteCarlo, "complete"),
    seed: u64,
};

const Definition = struct { object: []const u8, suffix: []const u8, symbol: ?[]const u8 = null };
fn definition(f: parse.Family, one: bool) ?Definition {
    return switch (f) {
        .pchi => .{ .object = if (one) "OneWayChiSqMC" else "PearsonChiSqMC", .suffix = "PCHI" },
        .lrchi => .{ .object = if (one) "OneWayLRChiSqMC" else "LRChiSqMC", .suffix = "LRCHI" },
        .mhchi => .{ .object = "MHChiSqMC", .suffix = "MHCHI" },
        .fisher => .{ .object = "FishersExactMC", .suffix = "FISH" },
        .jt => .{ .object = "JTTestMC", .suffix = "JT", .symbol = "JT" },
        .trend => .{ .object = "TrendTestMC", .suffix = "TREND", .symbol = "Z" },
        .pcorr => .{ .object = "PearsonCorrMC", .suffix = "PCORR", .symbol = "r" },
        .scorr => .{ .object = "SpearmanCorrMC", .suffix = "SCORR", .symbol = "r" },
        .kentb => .{ .object = "TauBMC", .suffix = "KENTB", .symbol = "t" },
        .stutc => .{ .object = "TauCMC", .suffix = "STUTC", .symbol = "t" },
        .smdcr => .{ .object = "SomersDCRMC", .suffix = "SMDCR", .symbol = "D" },
        .smdrc => .{ .object = "SomersDRCMC", .suffix = "SMDRC", .symbol = "D" },
        .kappa => .{ .object = "KappaMC", .suffix = "KAPPA", .symbol = "K" },
        .wtkappa => .{ .object = "WtKappaMC", .suffix = "WTKAP", .symbol = "K" },
        .symmetry => .{ .object = "SymmetryMC", .suffix = "TSYMM" },
        else => null,
    };
}

const Rows = @import("ods_freq_exact_rows.zig").Rows;
fn interval(rows: *Rows, prefix: []const u8, suffix: []const u8, label: []const u8, est: dist.Estimate, level: []const u8) !void {
    const id = try std.fmt.allocPrint(rows.a, "{s}_{s}", .{ prefix, suffix });
    try rows.probability(id, label, est.p);
    try rows.probability(try std.fmt.allocPrint(rows.a, "L_{s}", .{id}), try std.fmt.allocPrint(rows.a, "{s}% Lower Conf Limit", .{level}), est.lower);
    try rows.probability(try std.fmt.allocPrint(rows.a, "U_{s}", .{id}), try std.fmt.allocPrint(rows.a, "{s}% Upper Conf Limit", .{level}), est.upper);
    try rows.add("", "", "", null);
}

fn longTable(a: A, t: *b.Builder, title: []const u8, def: Definition, sim: Simulation, opt: parse.Options, level: []const u8) !void {
    var rows = try Rows.init(a, t, title, opt.pformat, 1);
    if (def.symbol) |symbol| {
        const right = sim.sample.right_sided;
        const label = try std.fmt.allocPrint(a, "One-sided Pr {s}  {s}", .{ if (right) ">=" else "<=", symbol });
        try rows.add("", label, "", null);
        try interval(&rows, if (right) "MCPR" else "MCPL", def.suffix, "Estimate", sim.sample.one_sided, level);
        try rows.add("", try std.fmt.allocPrint(a, "Two-sided Pr >= |{s}|", .{symbol}), "", null);
        try interval(&rows, "MCP2", def.suffix, "Estimate", sim.sample.two_sided, level);
    } else try interval(&rows, "MCP", def.suffix, if (sim.family == .fisher) "Pr <= P" else if (sim.family == .symmetry) "Pr >= S" else "Pr >= ChiSq", sim.sample.two_sided, level);
    try rows.integer(try std.fmt.allocPrint(a, "N_MC_{s}", .{def.suffix}), "Number of Samples", sim.sample.samples);
    try rows.integer(try std.fmt.allocPrint(a, "SEED_MC_{s}", .{def.suffix}), "Initial Seed", sim.seed);
    rows.finish();
}
fn agreement(a: A, t: *b.Builder, title: []const u8, sim: Simulation, level: []const u8, opt: parse.Options) !void {
    const symmetry = sim.family == .symmetry;
    try t.char("Label", if (symmetry) 11 else 9);
    t.ds.setLabel("Label", "Probability");
    const format = try @import("ods_freq_exact_rows.zig").probabilityFormat(a, opt.pformat);
    for ([_][]const u8{ "Estimate", "LowerCL", "UpperCL" }) |name| try t.num(name, format);
    t.ds.setLabel("LowerCL", try std.fmt.allocPrint(a, "{s}% Lower Confidence Limit", .{level}));
    t.ds.setLabel("UpperCL", try std.fmt.allocPrint(a, "{s}% Upper Confidence Limit", .{level}));
    try t.num("Samples", "8.");
    t.ds.setLabel("Samples", "Number of Samples");
    try t.num("Seed", "10.");
    t.ds.setLabel("Seed", "Initial Seed");
    for ([_]dist.Estimate{ sim.sample.one_sided, sim.sample.two_sided }, 0..) |est, i| {
        if (symmetry and i == 0) continue;
        const label = if (symmetry) "Pr >= ChiSq" else if (i == 1) "Pr >= |K|" else if (sim.sample.right_sided) "Pr >=  K" else "Pr <=  K";
        try t.row(&.{ b.s(title), b.s(label), b.n(est.p), b.n(est.lower), b.n(est.upper), b.n(@floatFromInt(sim.sample.samples)), b.n(@floatFromInt(sim.seed)) });
    }
}

pub fn publish(a: A, d: *diag.Diagnostics, capture: *ods.Capture, source: *const Dataset, by: []const usize, rep: ?[]const Value, tab: *model.Table, number: usize, simulations: []const Simulation, opt: parse.Options, restore: bool) diag.Error!void {
    const nd = tab.dimensions.len;
    for (simulations) |sim| {
        const def = definition(sim.family, nd == 1) orelse continue;
        if (!capture.wants(def.object)) continue;
        var t = try b.Builder.init(a, source, by, rep);
        try t.char("Table", 256);
        const title = try @import("ods_freq_exact_rows.zig").tableName(a, tab, number);
        const level = try @import("freq_risk_render.zig").confidence(a, opt.alpha);
        switch (sim.family) {
            .kappa, .wtkappa, .symmetry => if (restore) try longTable(a, &t, title, def, sim, opt, level) else try agreement(a, &t, title, sim, level, opt),
            else => try longTable(a, &t, title, def, sim, opt, level),
        }
        try capture.publish(a, d, def.object, &t.ds);
    }
}
