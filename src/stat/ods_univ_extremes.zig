//! ODS datasets for ordered observations, distinct values, frequencies and modes.
const std = @import("std");
const u = @import("ods_univariate.zig");
const b = @import("ods_table.zig");
const fm = @import("ods_univ_formats.zig");
const Value = @import("../value.zig").Value;

pub fn observations(ctx: ?u.Context, ids: []const usize, freqcol: ?usize) !?u.Table {
    var t = (try u.Context.start(ctx, "ExtremeObs", "Extreme Observations")) orelse return null;
    const c = t.ctx;
    const a = t.builder.ds.arena;
    for ([_][]const u8{ "Low", "High" }, [_][]const u8{ "Lowest", "Highest" }) |side, word| {
        try t.num(side, c.measure_format, try std.fmt.allocPrint(a, "{s} Value", .{word}));
        for (ids) |ci| {
            const id = c.source.columns.items[ci];
            const name = try std.fmt.allocPrint(a, "{s}_{s}", .{ id.name, side });
            const label = id.label orelse id.name;
            if (id.type == .char) {
                try t.char(name, id.len orelse 8, label);
                if (id.format) |f| t.builder.ds.setFormat(name, f);
            } else {
                var vals: std.ArrayList(f64) = .empty;
                if (id.format == null) for (c.source.rows.items) |r| try vals.append(a, r[ci].num);
                try t.num(name, id.format orelse try fm.measurement(a, vals.items), label);
            }
        }
        if (freqcol != null) try t.num(try std.fmt.allocPrint(a, "{s}Freq", .{side}), "6.", try std.fmt.allocPrint(a, "Frequency of {s} Value", .{word}));
        try t.num(try std.fmt.allocPrint(a, "{s}Obs", .{side}), "6.", try std.fmt.allocPrint(a, "Observation Number of {s} Value", .{word}));
    }
    return t;
}

pub const Side = struct { value: f64, obs: usize, source: []const Value };
pub fn observationRow(t: *u.Table, ids: []const usize, freqcol: ?usize, sides: [2]Side) !void {
    var cells: std.ArrayList(Value) = .empty;
    const a = t.builder.ds.arena;
    for (sides) |side| {
        try cells.append(a, b.n(side.value));
        for (ids) |ci| try cells.append(a, side.source[ci]);
        if (freqcol) |ci| try cells.append(a, b.n(@floor(side.source[ci].num)));
        try cells.append(a, b.n(@floatFromInt(side.obs)));
    }
    try t.row(cells.items);
}

pub fn values(ctx: ?u.Context) !?u.Table {
    var t = (try u.Context.start(ctx, "ExtremeValues", "Extreme Values")) orelse return null;
    const a = t.builder.ds.arena;
    for ([_][]const u8{ "Low", "High" }, [_][]const u8{ "Lowest", "Highest" }) |side, word| {
        try t.num(try std.fmt.allocPrint(a, "{s}Order", .{side}), "6.", try std.fmt.allocPrint(a, "Order of {s} Value", .{word}));
        try t.num(side, t.ctx.measure_format, try std.fmt.allocPrint(a, "{s} Value", .{word}));
        try t.num(try std.fmt.allocPrint(a, "{s}Freq", .{side}), "6.", try std.fmt.allocPrint(a, "Frequency of {s} Value", .{word}));
    }
    return t;
}
pub fn frequencies(ctx: ?u.Context, weighted: bool) !?u.Table {
    var t = (try u.Context.start(ctx, "Frequencies", if (weighted) "Weighted Frequency Counts" else "Frequency Counts")) orelse return null;
    try t.num("Value", t.ctx.measure_format, "");
    try t.num("Count", "5.", "Frequency of Value");
    if (weighted) try t.num("WgtCount", "BEST8.", "Weighted Frequency of Value");
    try t.num("Cell", "5.1", "Cell Percent");
    try t.num("Cum", "5.1", "Cumulative Percent");
    return t;
}
pub fn modes(ctx: ?u.Context) !?u.Table {
    var t = (try u.Context.start(ctx, "Modes", "Modes")) orelse return null;
    try t.num("Mode", t.ctx.measure_format, "");
    try t.num("Count", "5.", "Mode Frequency");
    return t;
}
