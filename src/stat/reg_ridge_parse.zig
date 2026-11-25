const std = @import("std");
const lex = @import("../lexer.zig");
const diag = @import("../diag.zig");
const proc = @import("../proc.zig");
pub const Plots = struct { only: bool = false, unpack: bool = false, vif_log: bool = false, ridge_log: bool = false, disabled: bool = false, requested: bool = false };
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, s: []const u8) bool {
    return at(t, i, .name) and std.ascii.eqlIgnoreCase(t[i].text, s);
}
fn number(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!f64 {
    if (!at(t, i.*, .number)) return cx.diags.fail(error.ParseError, if (i.* < t.len) t[i.*].line else 0, "PROC REG RIDGE: expected a nonnegative number", .{});
    const v = std.fmt.parseFloat(f64, t[i.*].text) catch return error.ParseError;
    i.* += 1;
    if (!std.math.isFinite(v) or v < 0) return cx.diags.fail(error.ParseError, t[i.* - 1].line, "PROC REG RIDGE: invalid constant", .{});
    return v;
}
pub fn constants(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error![]const f64 {
    if (!at(t, i.* + 1, .eq)) return cx.diags.fail(error.ParseError, t[i.*].line, "PROC REG RIDGE requires =", .{});
    i.* += 2;
    var values: std.ArrayList(f64) = .empty;
    while (true) {
        const start = try number(cx, t, i);
        if (kw(t, i.*, "to")) {
            i.* += 1;
            const end = try number(cx, t, i);
            var step: f64 = 1;
            if (kw(t, i.*, "by")) {
                i.* += 1;
                step = try number(cx, t, i);
            }
            if (!(step > 0) or end < start) return cx.diags.fail(error.ParseError, t[i.* - 1].line, "PROC REG RIDGE: expected an ascending range with positive increment", .{});
            const ratio = (end - start) / step;
            if (!std.math.isFinite(ratio) or ratio > 100000) return proc.failGap(cx.diags, 0, "PROC REG: RIDGE paths above 100001 points are not implemented", .{});
            const count: usize = @intFromFloat(@floor(std.math.nextAfter(f64, ratio, std.math.inf(f64))) + 1);
            for (0..count) |j| try values.append(cx.arena, start + @as(f64, @floatFromInt(j)) * step);
        } else try values.append(cx.arena, start);
        if (at(t, i.*, .comma)) {
            i.* += 1;
            continue;
        }
        if (!at(t, i.*, .number)) break;
    }
    return values.items;
}
pub fn matches(t: []const lex.Token, i: usize) bool {
    var j = i + 1;
    if (at(t, j, .lparen)) {
        while (j < t.len and !at(t, j, .rparen) and !at(t, j, .semicolon)) j += 1;
        j += 1;
    }
    return at(t, j, .eq) and (kw(t, j + 1, "ridge") or kw(t, j + 1, "ridgepanel") or kw(t, j + 1, "ridgeplot"));
}
pub fn plots(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!Plots {
    var result: Plots = .{ .requested = true };
    i.* += 1;
    if (at(t, i.*, .lparen)) {
        i.* += 1;
        if (!kw(t, i.*, "only")) return proc.failGap(cx.diags, t[i.*].line, "PROC REG: this global ridge plot option is not implemented", .{});
        result.only = true;
        i.* += 1;
        if (!at(t, i.*, .rparen)) return cx.diags.fail(error.ParseError, t[i.*].line, "PROC REG: expected ) after ONLY", .{});
        i.* += 1;
    }
    if (!at(t, i.*, .eq)) return cx.diags.fail(error.ParseError, t[i.*].line, "PROC REG: PLOTS requires =", .{});
    i.* += 2;
    if (at(t, i.*, .lparen)) {
        i.* += 1;
        while (i.* < t.len and !at(t, i.*, .rparen)) {
            if (kw(t, i.*, "unpack")) {
                result.unpack = true;
                i.* += 1;
                continue;
            }
            const vif = kw(t, i.*, "vifaxis");
            const ridge = kw(t, i.*, "ridgeaxis");
            if (!vif and !ridge) return proc.failGap(cx.diags, t[i.*].line, "PROC REG: ridge plot option {s} is not implemented", .{t[i.*].text});
            if (!at(t, i.* + 1, .eq) or (!kw(t, i.* + 2, "log") and !kw(t, i.* + 2, "linear"))) return cx.diags.fail(error.ParseError, t[i.*].line, "PROC REG: ridge axis must be LOG or LINEAR", .{});
            if (vif) result.vif_log = kw(t, i.* + 2, "log") else result.ridge_log = kw(t, i.* + 2, "log");
            i.* += 3;
        }
        if (!at(t, i.*, .rparen)) return cx.diags.fail(error.ParseError, 0, "PROC REG: unclosed ridge plot options", .{});
        i.* += 1;
    }
    return result;
}
