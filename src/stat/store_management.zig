//! Narrow guard around unimplemented native item-store management.
//! Base SAS 9.4 Procedures Guide, physical631–632: PROC DATASETS MEMTYPE
//! defaults ALL; KILL obeys it. Physical651: CHANGE defaults ALL (unless the
//! PROC restricts it). Physical675: DELETE defaults DATA. No deletion engine
//! or member-type support is added here; native files must never be silently
//! skipped while a caller believes an ALL-members operation succeeded.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const eq = std.ascii.eqlIgnoreCase;
fn exists(cx: proc.ProcCtx, library: ?[]const u8, member: ?[]const u8) diag.Error!bool {
    var libname = library orelse "work";
    var stem = member;
    if (stem) |name| if (std.mem.indexOfScalar(u8, name, '.')) |dot| {
        libname = name[0..dot];
        stem = name[dot + 1 ..];
    };
    if (stem) |name| if (eq(name, "_all_")) {
        stem = null;
    };
    if (eq(libname, "work")) {
        if (stem) |name| {
            const key = try std.fmt.allocPrint(cx.arena, "work.{s}", .{try std.ascii.allocLowerString(cx.arena, name)});
            return cx.lib.item_stores.contains(key);
        }
        return cx.lib.item_stores.count() > 0;
    }
    const path = @import("../dsfns.zig").librefDir(libname) orelse return false;
    const extension = @import("store.zig").extension;
    const io = std.Io.Threaded.global_single_threaded.io();
    var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return false;
    defer dir.close(io);
    var iterator = dir.iterate();
    while (iterator.next(io) catch null) |entry| {
        if (!std.ascii.endsWithIgnoreCase(entry.name, extension)) continue;
        if (stem) |name| {
            if (!eq(entry.name[0 .. entry.name.len - extension.len], name)) continue;
        }
        return true;
    }
    return false;
}
fn gap(cx: proc.ProcCtx, line: usize) diag.Error {
    return proc.failGap(cx.diags, line, "PROC DATASETS: management of native OpenSAS item stores is not implemented; use MEMTYPE=DATA for DATA-only operations", .{});
}
pub fn checkKill(cx: proc.ProcCtx, library: ?[]const u8, data_only: bool) diag.Error!void {
    if (!data_only and try exists(cx, library, null)) return gap(cx, 0);
}
pub fn checkStatement(cx: proc.ProcCtx, library: ?[]const u8, data_only: bool, stmt: []const lex.Token) diag.Error!void {
    // DELETE's documented default is DATA; CHANGE inherits PROC MEMTYPE.
    var only_data = data_only or eq(stmt[0].text, "delete");
    var native_selector = false;
    for (stmt, 0..) |token, i| {
        if (token.tag == .name and (eq(token.text, "memtype") or eq(token.text, "mtype") or eq(token.text, "mt")) and i + 2 < stmt.len and stmt[i + 1].tag == .eq and stmt[i + 2].tag == .name) {
            const kind = stmt[i + 2].text;
            if (eq(kind, "itemstor")) native_selector = true;
            if (eq(kind, "all")) only_data = false;
            if (eq(kind, "data")) only_data = true;
        }
    }
    // Explicit ITEMSTOR syntax is a known gap even without a matching file.
    if (native_selector) return gap(cx, stmt[0].line);
    if (only_data) return;
    for (stmt[1..], 1..) |token, i| {
        if (token.tag == .slash or token.tag == .lparen) break;
        if (token.tag != .name) continue;
        if (eq(stmt[0].text, "change") and (i + 1 >= stmt.len or stmt[i + 1].tag != .eq)) continue;
        // Prefix-list management is not supported for item stores. A prefix
        // may match native members, so guard against any native member here.
        const member: ?[]const u8 = if (i + 1 < stmt.len and stmt[i + 1].tag == .colon) null else token.text;
        if (try exists(cx, library, member)) return gap(cx, token.line);
    }
}
