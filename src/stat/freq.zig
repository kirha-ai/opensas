//! PROC FREQ computation policy, independent of parsing and listing layout.
const std = @import("std");
const Value = @import("../value.zig").Value;

pub fn isMissing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |s| std.mem.trim(u8, s, " ").len == 0,
    };
}

/// An empty percent base is undefined, including WEIGHT / ZEROS tables.
pub fn percent(count: f64, denominator: f64) f64 {
    return if (denominator == 0) std.math.nan(f64) else 100 * count / denominator;
}
