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
    overall: List = .all,
    destination: List = .all,

    pub fn endProc(self: *Listing) void {
        self.overall.endProc();
        self.destination.endProc();
    }

    pub fn accepts(self: Listing, path: []const u8) bool {
        return self.open and self.overall.accepts(path) and self.destination.accepts(path);
    }

    pub fn filtered(self: Listing) bool {
        return !self.open or self.overall != .all or self.destination != .all;
    }

    /// Returns whether this is a listing control. Other destination options
    /// such as GPATH remain the responsibility of their own handlers.
    pub fn parse(self: *Listing, a: std.mem.Allocator, d: *diag.Diagnostics, t: []const Token) diag.Error!bool {
        if (t.len < 3 or t[1].tag != .name) return false;
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
            var path = t[i].text;
            var name = path;
            i += 1;
            while (i < t.len and t[i].tag == .dot) {
                i += 1;
                if (i >= t.len or t[i].tag != .name) return d.fail(error.ParseError, 0, "ODS: expected object name after dot", .{});
                name = t[i].text;
                path = try std.fmt.allocPrint(a, "{s}.{s}", .{ path, name });
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

fn known(name: []const u8) bool {
    // Only accept table names with a listing producer. New entries must route
    // a real object before adding its name here.
    const names = [_][]const u8{ "Moments", "BasicMeasures", "TestsForLocation", "Quantiles", "ExtremeObs", "ExtremeValues", "Modes", "Frequencies", "BasicIntervals", "TrimmedMeans", "WinsorizedMeans", "RobustScale", "LocationCounts", "TestsForNormality", "ParameterEstimates", "GoodnessOfFit", "FitQuantiles", "Bins" };
    for (names) |value| if (eq(name, value)) return true;
    return false;
}

/// A table's listing text can be suppressed after its numerical and typed ODS
/// production. The caller sets each boundary explicitly; no listing text is parsed.
pub const Tables = struct {
    selection: ?*const Listing = null,
    prefix: []const u8 = "",

    pub fn finish(self: Tables, a: std.mem.Allocator, out: *std.ArrayList(u8), start: usize, name: []const u8) !void {
        const selection = self.selection orelse return;
        if (!selection.filtered()) return;
        const path = try std.fmt.allocPrint(a, "{s}.{s}", .{ self.prefix, name });
        if (!selection.accepts(path)) out.shrinkRetainingCapacity(start);
    }
};
