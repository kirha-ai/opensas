//! Typed NPAR1WAY OUTPUT producer. S154 physical pp.7230-7233/7253-7259,
//! Table90.5 supplies names (including historical eight-character truncations).
//! Statistical cells are numeric8/missing; BY descriptors are copied intact.
//! Descriptor formats/labels not specified by this source remain unset rather
//! than borrowed from listing formats. _VAR_ holds the longest analysis name.
const std = @import("std");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const stats = @import("npar1way_stats.zig");
const A = std.mem.Allocator;
pub const Selection = struct {
    scores: [10]bool = @splat(false),
    anova: bool = false,
    edf: bool = false,
    fp: bool = false,
    hl: bool = false,
    rmd: bool = false,
    pub fn any(self: Selection) bool {
        if (self.anova or self.edf or self.fp or self.hl or self.rmd) return true;
        for (self.scores) |v| if (v) return true;
        return false;
    }
};
pub const Request = struct { name: []const u8, selection: Selection = .{}, explicit: bool = false, options: []const @import("../lexer.zig").Token = &.{} };
pub const Packet = struct { base: stats.Result, fp: ?@import("npar1way_fp.zig").Result = null, hl: ?@import("npar1way_hl.zig").Result = null, rmd: ?@import("npar1way_exact.zig").Rmd = null, ks: ?@import("npar1way_exact.zig").Ks = null, point: bool = false, midp: bool = false };
const Family = struct { kind: stats.Kind, stat: []const u8, prefix: []const u8, chi: []const u8, df: []const u8, p: []const u8, xp: []const u8, xpt: []const u8, xmp: []const u8 };
pub const families = [_]Family{
    .{ .kind = .ab, .stat = "_AB_", .prefix = "AB", .chi = "_CHAB_", .df = "DF_CHAB", .p = "P_CHAB", .xp = "XP_CHAB", .xpt = "XPT_CHAB", .xmp = "XMP_CHAB" },
    .{ .kind = .conover, .stat = "_CON_", .prefix = "CON", .chi = "_CHCON_", .df = "DF_CHCON", .p = "P_CHCON", .xp = "XP_CHCON", .xpt = "XPT_CHCO", .xmp = "XMP_CHCON" },
    .{ .kind = .klotz, .stat = "_KLOTZ_", .prefix = "K", .chi = "_CHK_", .df = "DF_CHK", .p = "P_CHK", .xp = "XP_CHK", .xpt = "XPT_CHK", .xmp = "XMP_CHK" },
    .{ .kind = .median, .stat = "_MED_", .prefix = "MED", .chi = "_CHMED_", .df = "DF_CHMED", .p = "P_CHMED", .xp = "XP_CHMED", .xpt = "XPT_CHME", .xmp = "XMP_CHMED" },
    .{ .kind = .mood, .stat = "_MOOD_", .prefix = "MOOD", .chi = "_CHMOOD_", .df = "DF_CHMOO", .p = "P_CHMOOD", .xp = "XP_CHMOO", .xpt = "XPT_CHMO", .xmp = "XMP_CHMOOD" },
    .{ .kind = .savage, .stat = "_SAV_", .prefix = "SAV", .chi = "_CHSAV_", .df = "DF_CHSAV", .p = "P_CHSAV", .xp = "XP_CHSAV", .xpt = "XPT_CHSA", .xmp = "XMP_CHSAV" },
    .{ .kind = .data, .stat = "_DATA_", .prefix = "DATA", .chi = "_CHDATA_", .df = "DF_CHDAT", .p = "P_CHDATA", .xp = "XP_CHDAT", .xpt = "XPT_CHDA", .xmp = "XMP_CHDATA" },
    .{ .kind = .st, .stat = "_ST_", .prefix = "ST", .chi = "_CHST_", .df = "DF_CHST", .p = "P_CHST", .xp = "XP_CHST", .xpt = "XPT_CHST", .xmp = "XMP_CHST" },
    .{ .kind = .vw, .stat = "_VW_", .prefix = "VW", .chi = "_CHVW_", .df = "DF_CHVW", .p = "P_CHVW", .xp = "XP_CHVW", .xpt = "XPT_CHVW", .xmp = "XMP_CHVW" },
    .{ .kind = .wilcoxon, .stat = "_WIL_", .prefix = "WIL", .chi = "_KW_", .df = "DF_KW", .p = "P_KW", .xp = "XP_KW", .xpt = "XPT_KW", .xmp = "XMP_KW" },
};
const anova_names = [_][]const u8{ "_MSA_", "_MSE_", "_F_", "P_F" };
const edf_names = [_][]const u8{ "_KS_", "_KSA_", "_Dp_", "P_Dp", "_Dm_", "P_Dm", "_D_", "P_KSA", "XP_Dp", "XPT_Dp", "XMP_Dp", "XP_Dm", "XPT_Dm", "XMP_Dm", "XP_D", "XPT_D", "XMP_D", "_CM_", "_CMA_", "_K_", "_KA_", "P_KA" };
const fp_names = [_][]const u8{ "_FP_", "PL_FP", "PR_FP", "P2_FP" };
const hl_names = [_][]const u8{ "_HL_", "L_HL", "U_HL", "M_HL", "E_HL", "XL_HL", "XU_HL", "XM_HL" };
const rmd_names = [_][]const u8{ "_RMD_", "XPL_RMD", "XPR_RMD", "XPT_RMD", "XMP_RMD", "_RMD2_", "XP2_RMD" };
const Entry = struct { name: []const u8, value: Value };
const Row = struct {
    by: []const Value,
    variable: []const u8,
    entries: std.ArrayList(Entry) = .empty,
    fn put(self: *Row, a: A, name: []const u8, value: ?f64) !void {
        if (value) |v| if (std.math.isInf(v)) return error.UnverifiedInfiniteOutput;
        try self.entries.append(a, .{ .name = name, .value = if (value) |v| .{ .num = v } else Value.missing });
    }
    fn prefixed(self: *Row, a: A, prefix: []const u8, suffix: []const u8, value: ?f64) !void {
        try self.put(a, try std.fmt.allocPrint(a, "{s}_{s}", .{ prefix, suffix }), value);
    }
};
fn side(z: ?f64, small: ?f64, left: bool) ?f64 {
    const v = z orelse return null;
    const p = small orelse return null;
    return if ((v <= 0) == left) p else 1 - p;
}
pub const Builder = struct {
    a: A,
    source: *const Dataset,
    by_cols: []const usize,
    selection: Selection,
    variable_width: usize,
    rows: std.ArrayList(Row) = .empty,
    pub fn append(self: *Builder, variable: []const u8, rep: ?[]const Value, packet: Packet) !void {
        const by = try self.a.alloc(Value, self.by_cols.len);
        for (self.by_cols, 0..) |ci, i| by[i] = if (rep) |r| r[ci] else if (self.source.columns.items[ci].type == .num) Value.missing else .{ .str = "" };
        var row: Row = .{ .by = by, .variable = variable };
        const a = self.a;
        const r = packet.base;
        if (self.selection.anova and r.anova == null) return error.MissingProducer;
        if (self.selection.edf and r.edf == null) return error.MissingProducer;
        if (self.selection.anova) if (r.anova) |v| {
            for (anova_names, [_]?f64{ v.among_ms, v.within_ms, v.f, v.p }) |name, value| try row.put(a, name, value);
        };
        for (families) |family| if (self.selection.scores[@intFromEnum(family.kind)]) {
            const score = for (r.scores) |v| {
                if (v.kind == family.kind) break v;
            } else return error.MissingProducer;
            if (score.two_sample) |v| {
                try row.put(a, family.stat, v.statistic);
                try row.prefixed(a, "Z", family.prefix, v.z);
                try row.prefixed(a, "PL", family.prefix, side(v.z, v.p_one, true));
                try row.prefixed(a, "PR", family.prefix, side(v.z, v.p_one, false));
                try row.prefixed(a, "P2", family.prefix, v.p_two);
                if (family.kind == .wilcoxon) {
                    try row.put(a, "PTL_WIL", side(v.z, v.p_t_one, true));
                    try row.put(a, "PTR_WIL", side(v.z, v.p_t_one, false));
                    try row.put(a, "PT2_WIL", v.p_t_two);
                }
                if (score.conditional) |e| {
                    try row.prefixed(a, "XPL", family.prefix, e.probability(e.lower_count));
                    try row.prefixed(a, "XPR", family.prefix, e.probability(e.upper_count));
                    if (packet.point) try row.prefixed(a, "XPT", family.prefix, e.probability(e.point_count));
                    if (packet.midp) try row.prefixed(a, "XMP", family.prefix, e.probability(if (e.right) e.upper_count else e.lower_count) - 0.5 * e.probability(e.point_count));
                    try row.prefixed(a, "XP2", family.prefix, e.probability(e.two_sided_count));
                }
            }
            try row.put(a, family.chi, score.chi_square);
            try row.put(a, family.df, @floatFromInt(score.df));
            try row.put(a, family.p, score.p);
            if (score.two_sample == null) if (score.conditional) |e| {
                try row.put(a, family.xp, e.probability(e.upper_count));
                if (packet.point) try row.put(a, family.xpt, e.probability(e.point_count));
                if (packet.midp) try row.put(a, family.xmp, e.probability(e.upper_count) - 0.5 * e.probability(e.point_count));
            };
        };
        if (self.selection.edf) if (r.edf) |e| {
            try row.put(a, "_KS_", e.ks);
            try row.put(a, "_KSA_", e.ksa);
            if (r.counts.len == 2) {
                for ([_][]const u8{ "_Dp_", "P_Dp", "_Dm_", "P_Dm", "_D_", "P_KSA" }, [_]?f64{ e.d_plus, e.d_plus_p, e.d_minus, e.d_minus_p, e.d, e.ks_p }) |name, value| try row.put(a, name, value);
            }
            if (packet.ks) |exact| {
                for ([_][]const u8{ "Dp", "Dm", "D" }, [_]usize{ 1, 2, 0 }) |suffix, i| {
                    try row.prefixed(a, "XP", suffix, exact.p[i]);
                    if (packet.point) try row.prefixed(a, "XPT", suffix, @as(f64, @floatFromInt(exact.point_counts[i])) / @as(f64, @floatFromInt(exact.allocations)));
                    if (packet.midp) try row.prefixed(a, "XMP", suffix, exact.p[i] - 0.5 * @as(f64, @floatFromInt(exact.point_counts[i])) / @as(f64, @floatFromInt(exact.allocations)));
                }
            }
            try row.put(a, "_CM_", e.cm);
            try row.put(a, "_CMA_", e.cma);
            if (r.counts.len == 2) {
                try row.put(a, "_K_", e.kuiper);
                try row.put(a, "_KA_", e.kuiper_scaled);
                try row.put(a, "P_KA", e.kuiper_p);
            }
        };
        if (self.selection.fp) {
            const v = packet.fp orelse return error.MissingProducer;
            for (fp_names, [_]?f64{ v.z, side(v.z, v.p_one, true), side(v.z, v.p_one, false), v.p_two }) |name, value| try row.put(a, name, value);
        }
        if (self.selection.hl) {
            const v = packet.hl orelse return error.MissingProducer;
            for (hl_names[0..5], [_]?f64{ v.estimate, v.asymptotic.lower, v.asymptotic.upper, v.asymptotic.midpoint(), v.standard_error }) |name, value| try row.put(a, name, value);
            if (v.exact) |interval| {
                try row.put(a, "XL_HL", interval.lower);
                try row.put(a, "XU_HL", interval.upper);
                try row.put(a, "XM_HL", interval.midpoint());
            }
        }
        if (self.selection.rmd) {
            const v = packet.rmd orelse return error.MissingProducer;
            const e = v.exact;
            try row.put(a, "_RMD_", v.ratio);
            try row.put(a, "XPL_RMD", e.probability(e.lower_count));
            try row.put(a, "XPR_RMD", e.probability(e.upper_count));
            if (packet.point) try row.put(a, "XPT_RMD", e.probability(e.point_count));
            if (packet.midp) try row.put(a, "XMP_RMD", e.probability(if (v.ratio <= 1) e.lower_count else e.upper_count) - 0.5 * e.probability(e.point_count));
            try row.put(a, "_RMD2_", v.ratio_two);
            try row.put(a, "XP2_RMD", e.probability(e.two_sided_count));
        }
        if (row.entries.items.len == 0) return error.MissingProducer;
        try self.rows.append(a, row);
    }
    fn addIfPresent(self: *Builder, ds: *Dataset, name: []const u8) !void {
        for (self.rows.items) |row| for (row.entries.items) |entry| if (std.mem.eql(u8, name, entry.name)) {
            if (ds.indexOf(name) != null) return error.ColumnConflict;
            const ci = try ds.addColumn(name, .num);
            ds.columns.items[ci].len = 8;
            return;
        };
    }
    pub fn finish(self: *Builder, name: []const u8) !*Dataset {
        if (self.rows.items.len == 0) return error.UnverifiedEmptyOutput;
        const ds = try self.a.create(Dataset);
        ds.* = Dataset.init(self.a, name);
        for (self.by_cols) |ci| {
            const c = self.source.columns.items[ci];
            if (std.ascii.eqlIgnoreCase(c.name, "_VAR_")) return error.ColumnConflict;
            _ = try ds.addColumnLike(c.name, c);
        }
        const variable = try ds.addColumn("_VAR_", .char);
        ds.columns.items[variable].len = @max(1, self.variable_width);
        // SourceTable90.5 order. Mixed2/multisample rows share the union schema;
        // inapplicable cells remain typed numeric missing rather than fake zeros.
        for (families, 0..) |f, i| {
            if (i == 1) for (anova_names) |n| {
                try self.addIfPresent(ds, n);
            };
            if (i == 2) {
                for (edf_names) |n| try self.addIfPresent(ds, n);
                for (fp_names) |n| try self.addIfPresent(ds, n);
                for (hl_names) |n| try self.addIfPresent(ds, n);
            }
            if (i == 5) for (rmd_names) |n| {
                try self.addIfPresent(ds, n);
            };
            try self.addIfPresent(ds, f.stat);
            for ([_][]const u8{ "Z", "PL", "PR", "P2" }) |prefix| try self.addIfPresent(ds, try std.fmt.allocPrint(self.a, "{s}_{s}", .{ prefix, f.prefix }));
            if (f.kind == .wilcoxon) for ([_][]const u8{ "PTL_WIL", "PTR_WIL", "PT2_WIL" }) |n| {
                try self.addIfPresent(ds, n);
            };
            for ([_][]const u8{ "XPL", "XPR", "XPT", "XMP", "XP2" }) |prefix| try self.addIfPresent(ds, try std.fmt.allocPrint(self.a, "{s}_{s}", .{ prefix, f.prefix }));
            for ([_][]const u8{ f.chi, f.df, f.p, f.xp, f.xpt, f.xmp }) |n| try self.addIfPresent(ds, n);
        }
        for (self.rows.items) |row| {
            const cells = try self.a.alloc(Value, ds.columns.items.len);
            @memset(cells, Value.missing);
            @memcpy(cells[0..row.by.len], row.by);
            cells[row.by.len] = .{ .str = row.variable };
            for (row.entries.items) |entry| {
                const ci = ds.indexOf(entry.name) orelse return error.MissingSchema;
                cells[ci] = entry.value;
            }
            try ds.appendRow(cells);
        }
        return ds;
    }
};

fn field(ds: *const Dataset, row: usize, name: []const u8) f64 {
    return ds.rows.items[row][ds.indexOf(name).?].num;
}
test "NPAR008 source-defined asymptotic family names every numeric type and producer value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var source = Dataset.init(a, "source");
    _ = try source.addColumn("x", .num);
    const values = [_]f64{ 1, 2, 3, 2, 4, 5 };
    const groups = [_]usize{ 0, 0, 0, 1, 1, 1 };
    const r = try stats.compute(a, &values, &groups, 2, .{ .ab = true, .st = true, .klotz = true, .mood = true, .conover = true, .data = true });
    var builder: Builder = .{ .a = a, .source = &source, .by_cols = &.{}, .selection = .{ .scores = @splat(true), .anova = true, .edf = true }, .variable_width = 1 };
    try builder.append("x", null, .{ .base = r });
    const ds = try builder.finish("o");
    try std.testing.expectEqual(@as(usize, 1), ds.rowCount());
    try std.testing.expectEqualStrings("x", ds.rows.items[0][0].str);
    try std.testing.expectEqual(@import("../pdv.zig").VarType.char, ds.columns.items[0].type);
    // Literal order fromTable90.5, rather than the producer's enumeration order.
    const expected = "_VAR_ _AB_ Z_AB PL_AB PR_AB P2_AB _CHAB_ DF_CHAB P_CHAB _MSA_ _MSE_ _F_ P_F _CON_ Z_CON PL_CON PR_CON P2_CON _CHCON_ DF_CHCON P_CHCON _KS_ _KSA_ _Dp_ P_Dp _Dm_ P_Dm _D_ P_KSA _CM_ _CMA_ _K_ _KA_ P_KA _KLOTZ_ Z_K PL_K PR_K P2_K _CHK_ DF_CHK P_CHK _MED_ Z_MED PL_MED PR_MED P2_MED _CHMED_ DF_CHMED P_CHMED _MOOD_ Z_MOOD PL_MOOD PR_MOOD P2_MOOD _CHMOOD_ DF_CHMOO P_CHMOOD _SAV_ Z_SAV PL_SAV PR_SAV P2_SAV _CHSAV_ DF_CHSAV P_CHSAV _DATA_ Z_DATA PL_DATA PR_DATA P2_DATA _CHDATA_ DF_CHDAT P_CHDATA _ST_ Z_ST PL_ST PR_ST P2_ST _CHST_ DF_CHST P_CHST _VW_ Z_VW PL_VW PR_VW P2_VW _CHVW_ DF_CHVW P_CHVW _WIL_ Z_WIL PL_WIL PR_WIL P2_WIL PTL_WIL PTR_WIL PT2_WIL _KW_ DF_KW P_KW";
    var names = std.mem.tokenizeScalar(u8, expected, ' ');
    for (ds.columns.items, 0..) |column, i| {
        try std.testing.expectEqualStrings(names.next().?, column.name);
        if (i > 0) {
            try std.testing.expectEqual(@import("../pdv.zig").VarType.num, column.type);
            try std.testing.expectEqual(@as(?usize, 8), column.len);
            try std.testing.expect(column.format == null and column.informat == null);
        }
    }
    try std.testing.expect(names.next() == null);
    // Each scalar is compared to its independently tested actual computational
    // producer; the literal names above separately catch mapping/order defects.
    for (r.scores) |score| {
        const f = for (families) |family| {
            if (family.kind == score.kind) break family;
        } else unreachable;
        try std.testing.expectEqual(score.two_sample.?.statistic, field(ds, 0, f.stat));
        try std.testing.expectEqual(score.two_sample.?.z.?, field(ds, 0, try std.fmt.allocPrint(a, "Z_{s}", .{f.prefix})));
        try std.testing.expectEqual(score.chi_square.?, field(ds, 0, f.chi));
        try std.testing.expectEqual(score.p.?, field(ds, 0, f.p));
        const left = field(ds, 0, try std.fmt.allocPrint(a, "PL_{s}", .{f.prefix}));
        const right = field(ds, 0, try std.fmt.allocPrint(a, "PR_{s}", .{f.prefix}));
        try std.testing.expectApproxEqAbs(@as(f64, 1), left + right, 1e-15);
        try std.testing.expectApproxEqAbs(score.two_sample.?.p_two.?, 2 * @min(left, right), 1e-15);
    }
    try std.testing.expectEqual(r.anova.?.f.?, field(ds, 0, "_F_"));
    try std.testing.expectEqual(r.edf.?.d_plus.?, field(ds, 0, "_Dp_"));
    try std.testing.expectEqual(r.edf.?.cm, field(ds, 0, "_CM_"));
    try std.testing.expectEqual(r.edf.?.kuiper_p.?, field(ds, 0, "P_KA"));
}
test "NPAR008 mixed two multisample BY rows retain metadata and numeric missing cells" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var source = Dataset.init(a, "source");
    _ = try source.addColumn("visit", .num);
    source.columns.items[0].format = "date9.";
    source.columns.items[0].informat = "date9.";
    source.columns.items[0].label = "Visit date";
    source.columns.items[0].len = 8;
    var select: Selection = .{};
    select.scores[@intFromEnum(stats.Kind.wilcoxon)] = true;
    var builder: Builder = .{ .a = a, .source = &source, .by_cols = &.{0}, .selection = select, .variable_width = 8 };
    const a2 = try stats.compute(a, &.{ 1, 2, 3, 4 }, &.{ 0, 0, 1, 1 }, 2, .{ .exact_wilcoxon = true });
    const a3 = try stats.compute(a, &.{ 1, 1, 2, 2, 3, 3 }, &.{ 0, 0, 1, 1, 2, 2 }, 3, .{ .exact_wilcoxon = true });
    try builder.append("x", &.{.{ .num = 1 }}, .{ .base = a2, .point = true, .midp = true });
    try builder.append("longname", &.{.{ .num = 2 }}, .{ .base = a3, .point = true, .midp = true });
    const ds = try builder.finish("out");
    try std.testing.expectEqual(@as(usize, 2), ds.rowCount());
    try std.testing.expectEqualStrings("date9.", ds.columns.items[0].format.?);
    try std.testing.expectEqualStrings("date9.", ds.columns.items[0].informat.?);
    try std.testing.expectEqualStrings("Visit date", ds.columns.items[0].label.?);
    try std.testing.expectEqual(@as(?usize, 8), ds.columns.items[1].len);
    try std.testing.expectEqual(@as(f64, 1), ds.rows.items[0][0].num);
    try std.testing.expectEqual(@as(f64, 2), ds.rows.items[1][0].num);
    try std.testing.expectEqual(@as(f64, 3), field(ds, 0, "_WIL_"));
    try std.testing.expect(std.math.isNan(field(ds, 1, "_WIL_")));
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 6.0), field(ds, 0, "XPL_WIL"), 1e-15);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 3.0), field(ds, 0, "XP2_WIL"), 1e-15);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 12.0), field(ds, 0, "XMP_WIL"), 1e-15);
    try std.testing.expect(std.math.isNan(field(ds, 0, "XP_KW")));
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 15.0), field(ds, 1, "XP_KW"), 1e-15);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 15.0), field(ds, 1, "XPT_KW"), 1e-15);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 30.0), field(ds, 1, "XMP_KW"), 1e-15);
    try std.testing.expect(ds.indexOf("_MSA_") == null and ds.indexOf("_KS_") == null);
}
test "NPAR008 exact legacy names FP HL RMD KS and undeclared empty contracts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var source = Dataset.init(a, "source");
    _ = try source.addColumn("x", .num);
    const values = [_]f64{ 1, 2, 3, 2, 4, 5 };
    const groups = [_]usize{ 0, 0, 0, 1, 1, 1 };
    var opts: stats.Options = .{};
    for ([_]stats.Kind{ .ab, .median, .mood, .savage, .data, .st, .wilcoxon }) |kind| opts.exact_scores[@intFromEnum(kind)] = true;
    const r = try stats.compute(a, &values, &groups, 2, opts);
    const fp = try @import("npar1way_fp.zig").compute(a, &values, &groups, 0);
    const hl = try @import("npar1way_hl.zig").compute(a, &.{ 1, 2, 3 }, &.{ 2, 4, 5 }, 0.2, true);
    const rmd = try @import("npar1way_exact.zig").rmd(a, &values, &groups);
    const ks = try @import("npar1way_exact.zig").ks(a, &values, &groups);
    var builder: Builder = .{ .a = a, .source = &source, .by_cols = &.{}, .selection = .{ .scores = @splat(true), .fp = true, .hl = true, .rmd = true, .edf = true }, .variable_width = 1 };
    // Klotz/Conover asymptotic producers must exist if requested.
    const all = try stats.compute(a, &values, &groups, 2, .{ .ab = true, .st = true, .mood = true, .data = true, .conover = true, .klotz = true });
    const combined = all;
    for (combined.scores) |*score| for (r.scores) |e| if (e.kind == score.kind and e.conditional != null) {
        score.* = e;
    };
    try builder.append("x", null, .{ .base = combined, .fp = fp, .hl = hl, .rmd = rmd, .ks = ks, .point = true, .midp = true });
    const ds = try builder.finish("o");
    try std.testing.expectEqual(fp.z.?, field(ds, 0, "_FP_"));
    try std.testing.expectEqual(hl.estimate, field(ds, 0, "_HL_"));
    try std.testing.expectEqual(hl.exact.?.lower, field(ds, 0, "XL_HL"));
    try std.testing.expectEqual(rmd.ratio, field(ds, 0, "_RMD_"));
    try std.testing.expectEqual(rmd.exact.probability(rmd.exact.two_sided_count), field(ds, 0, "XP2_RMD"));
    try std.testing.expectEqual(ks.p[0], field(ds, 0, "XP_D"));
    try std.testing.expectEqual(ks.p[1], field(ds, 0, "XP_Dp"));
    try std.testing.expectEqual(ks.p[2], field(ds, 0, "XP_Dm"));
    for ([_][]const u8{ "XPL_AB", "XPT_AB", "XMP_AB", "XP2_AB", "XPL_MED", "XPT_MOOD", "XMP_SAV", "XP2_DATA", "XPR_ST", "PTL_WIL" }) |name| try std.testing.expect(ds.indexOf(name) != null);
    try std.testing.expect(ds.indexOf("XPL_K") == null and ds.indexOf("XPL_CON") == null);
    var empty: Builder = .{ .a = a, .source = &source, .by_cols = &.{}, .selection = .{ .anova = true }, .variable_width = 1 };
    try std.testing.expectError(error.UnverifiedEmptyOutput, empty.finish("empty"));
}

test "NPAR008 all implemented multisample exact legacy fields follow Table90.5" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var source = Dataset.init(a, "source");
    _ = try source.addColumn("value", .num);
    var options: stats.Options = .{};
    var select: Selection = .{};
    for ([_]stats.Kind{ .ab, .median, .mood, .savage, .data, .st, .wilcoxon }) |kind| {
        options.exact_scores[@intFromEnum(kind)] = true;
        select.scores[@intFromEnum(kind)] = true;
    }
    const r = try stats.compute(a, &.{ 1, 1, 2, 2, 3, 3 }, &.{ 0, 0, 1, 1, 2, 2 }, 3, options);
    var builder: Builder = .{ .a = a, .source = &source, .by_cols = &.{}, .selection = select, .variable_width = 5 };
    try builder.append("value", null, .{ .base = r, .point = true, .midp = true });
    const ds = try builder.finish("o");
    const expected = "_VAR_ _CHAB_ DF_CHAB P_CHAB XP_CHAB XPT_CHAB XMP_CHAB _CHMED_ DF_CHMED P_CHMED XP_CHMED XPT_CHME XMP_CHMED _CHMOOD_ DF_CHMOO P_CHMOOD XP_CHMOO XPT_CHMO XMP_CHMOOD _CHSAV_ DF_CHSAV P_CHSAV XP_CHSAV XPT_CHSA XMP_CHSAV _CHDATA_ DF_CHDAT P_CHDATA XP_CHDAT XPT_CHDA XMP_CHDATA _CHST_ DF_CHST P_CHST XP_CHST XPT_CHST XMP_CHST _KW_ DF_KW P_KW XP_KW XPT_KW XMP_KW";
    var names = std.mem.tokenizeScalar(u8, expected, ' ');
    for (ds.columns.items) |column| try std.testing.expectEqualStrings(names.next().?, column.name);
    try std.testing.expect(names.next() == null);
    try std.testing.expectApproxEqAbs(@as(f64, 0.2), field(ds, 0, "XP_CHAB"), 1e-15);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 15.0), field(ds, 0, "XP_KW"), 1e-15);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 30.0), field(ds, 0, "XMP_KW"), 1e-15);
}
