//! Typed ODS OUTPUT request registry. Producers publish schemas and cells, never text.
const std = @import("std");
const diag = @import("diag.zig");
const lex = @import("lexer.zig");
const Dataset = @import("dataset.zig").Dataset;
const Library = @import("exec.zig").Library;
const Value = @import("value.zig").Value;
const eq = std.ascii.eqlIgnoreCase;
pub const names = [_][]const u8{ "PearsonCorr", "SimpleStats", "OneWayFreqs", "CrossTabFreqs", "Moments", "Quantiles", "BasicMeasures" };
const Request = struct { table: []const u8, target: []const u8, result: ?*Dataset = null };
pub const Capture = struct {
    requests: std.ArrayList(Request) = .empty,
    pub fn wants(self: *const Capture, name: []const u8) bool {
        for (self.requests.items) |r| if (eq(r.table, name)) return true;
        return false;
    }
    pub fn parse(self: *Capture, a: std.mem.Allocator, d: *diag.Diagnostics, toks: []const lex.Token) diag.Error!void {
        var i: usize = 2;
        if (i < toks.len and toks[i].tag == .name and (eq(toks[i].text, "close") or eq(toks[i].text, "clear"))) {
            i += 1;
            if (i < toks.len and toks[i].tag != .semicolon and toks[i].tag != .eof) return d.fail(error.ParseError, 0, "ODS OUTPUT: unexpected token after CLOSE/CLEAR", .{});
            self.requests.clearRetainingCapacity();
            return;
        }
        var pending: std.ArrayList(Request) = .empty;
        while (i < toks.len and toks[i].tag != .semicolon and toks[i].tag != .eof) {
            const table = toks[i];
            if (table.tag != .name) return d.fail(error.ParseError, table.line, "ODS OUTPUT: expected a supported table name", .{});
            var known = false;
            for (names) |name| known = known or eq(name, table.text);
            if (!known) {
                diag.markGap();
                return d.fail(error.ParseError, table.line, "ODS OUTPUT: unsupported table {s}", .{table.text});
            }
            i += 1;
            if (i >= toks.len or toks[i].tag != .eq) return d.fail(error.ParseError, table.line, "ODS OUTPUT: expected table=dataset", .{});
            i += 1;
            if (i >= toks.len or toks[i].tag != .name) return d.fail(error.ParseError, table.line, "ODS OUTPUT: expected dataset name", .{});
            var target = toks[i].text;
            i += 1;
            if (i < toks.len and toks[i].tag == .dot) {
                i += 1;
                if (i >= toks.len or toks[i].tag != .name) return d.fail(error.ParseError, table.line, "ODS OUTPUT: expected member name", .{});
                target = try std.fmt.allocPrint(a, "{s}.{s}", .{ target, toks[i].text });
                i += 1;
            }
            try pending.append(a, .{ .table = table.text, .target = target });
        }
        if (pending.items.len == 0) return d.fail(error.ParseError, 0, "ODS OUTPUT: expected table=dataset or CLOSE", .{});
        for (pending.items) |request| {
            var duplicate = false;
            for (self.requests.items) |old| duplicate = duplicate or eq(member(old.target), member(request.target));
            if (duplicate) try d.report(.warning, 0, "Duplicate data set name on ODS OUTPUT statement. Entry will be ignored.", .{}) else try self.requests.append(a, request);
        }
    }
    /// Schema union is necessary for multiple VAR/TABLES objects. Missing cells
    /// are typed; column order follows first occurrence, as in SAS ODS datasets.
    pub fn publish(self: *Capture, a: std.mem.Allocator, d: *diag.Diagnostics, name: []const u8, part: *const Dataset) diag.Error!void {
        for (part.columns.items, 0..) |c, i| for (part.columns.items[0..i]) |previous| {
            if (eq(c.name, previous.name)) return d.fail(error.ParseError, 0, "ODS OUTPUT: ambiguous generated column {s}", .{c.name});
        };
        for (self.requests.items) |*r| if (eq(r.table, name)) {
            if (r.result == null) {
                const dst = try a.create(Dataset);
                dst.* = Dataset.init(a, r.target);
                dst.label = part.label;
                r.result = dst;
            }
            const dst = r.result.?;
            for (part.columns.items) |c| {
                if (dst.indexOf(c.name)) |ci| {
                    if (dst.columns.items[ci].type != c.type) return d.fail(error.ParseError, 0, "ODS OUTPUT: incompatible types for {s}", .{c.name});
                    if (c.len) |n| dst.columns.items[ci].len = @max(dst.columns.items[ci].len orelse 0, n);
                } else {
                    _ = try dst.addColumnLike(c.name, c);
                    for (dst.rows.items) |*row| {
                        const cells = try a.alloc(Value, dst.columns.items.len);
                        @memcpy(cells[0..row.*.len], row.*);
                        cells[cells.len - 1] = missing(c.type);
                        row.* = cells;
                    }
                }
            }
            for (part.rows.items) |row| {
                const cells = try a.alloc(Value, dst.columns.items.len);
                for (dst.columns.items, 0..) |c, j| cells[j] = missing(c.type);
                for (part.columns.items, row) |c, v| cells[dst.indexOf(c.name).?] = v;
                try dst.appendRow(cells);
            }
        };
    }
    pub fn finish(self: *Capture, lib: *Library, d: *diag.Diagnostics) diag.Error!void {
        // SAS closes ODS outputs in reverse request order (SYSLAST is first).
        var i = self.requests.items.len;
        while (i > 0) {
            i -= 1;
            const r = self.requests.items[i];
            if (r.result) |ds| try lib.put(r.target, ds) else try d.report(.warning, 0, "Output '{s}' was not created. Make sure the output object is produced by the procedure.", .{r.table});
        }
        self.requests.clearRetainingCapacity();
    }
};
fn missing(t: @import("pdv.zig").VarType) Value {
    return if (t == .num) .{ .num = std.math.nan(f64) } else .{ .str = "" };
}
test "FEAT-odsoutput typed union reorders cells widens chars and preserves BY metadata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var capture: Capture = .{};
    try capture.parse(a, &d, try lex.tokenize(a, "ods output OneWayFreqs=one OneWayFreqs=work.two;", &d));
    var first = Dataset.init(a, "");
    _ = try first.addColumn("group", .char);
    first.setLen("group", 12);
    first.setLabel("group", "Group label");
    first.setFormat("group", "$12.");
    first.setInformat("group", "$12.");
    _ = try first.addColumn("Frequency", .num);
    _ = try first.addColumn("category", .char);
    first.setLen("category", 1);
    try first.appendRow(&.{ .{ .str = "G" }, .{ .num = 2 }, .{ .str = "A" } });
    var second = Dataset.init(a, "");
    _ = try second.addColumn("category", .char);
    second.setLen("category", 6);
    _ = try second.addColumn("Percent", .num);
    _ = try second.addColumn("group", .char);
    second.setLen("group", 12);
    try second.appendRow(&.{ .{ .str = "longer" }, .{ .num = 50 }, .{ .str = "H" } });
    try capture.publish(a, &d, "onewayfreqs", &first);
    try capture.publish(a, &d, "OneWayFreqs", &second);
    var lib = Library.init(a);
    try capture.finish(&lib, &d);
    for ([_][]const u8{ "one", "two" }) |name| {
        const ds = lib.find(name).?;
        try std.testing.expectEqual(@as(usize, 2), ds.rowCount());
        try std.testing.expectEqualStrings("H", ds.row(1)[0].str);
        try std.testing.expect(ds.row(1)[1].isMissing());
        try std.testing.expectEqualStrings("longer", ds.row(1)[2].str);
        try std.testing.expect(ds.row(0)[3].isMissing());
        try std.testing.expectEqual(@as(f64, 50), ds.row(1)[3].num);
        try std.testing.expectEqual(@as(?usize, 6), ds.columns.items[2].len);
        try std.testing.expectEqualStrings("Group label", ds.columns.items[0].label.?);
        try std.testing.expectEqualStrings("$12.", ds.columns.items[0].format.?);
        try std.testing.expectEqualStrings("$12.", ds.columns.items[0].informat.?);
    }
    try std.testing.expectEqual(@as(usize, 0), capture.requests.items.len);
}

test "FEAT-odsoutput parser is atomic and malformed unsupported requests stay loud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "ods output NoSuch=x;", "ods output Moments=;", "ods output Moments=x(bogus);", "ods output Moments=x NoSuch=y;", "ods output Moments;", "ods output;", "ods output close junk;" }) |source| {
        var d = diag.Diagnostics.init(a);
        var capture: Capture = .{};
        try std.testing.expectError(error.ParseError, capture.parse(a, &d, try lex.tokenize(a, source, &d)));
        try std.testing.expect(d.hasErrors());
        try std.testing.expectEqual(@as(usize, 0), capture.requests.items.len);
    }
}

test "FEAT-odsoutput mixed requests expire after next procedure SAS lifecycle" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var capture: Capture = .{};
    try capture.parse(a, &d, try lex.tokenize(a, "ods output PearsonCorr=c Moments=m;", &d));
    var part = Dataset.init(a, "");
    _ = try part.addColumn("x", .num);
    try part.appendRow(&.{.{ .num = 1 }});
    try capture.publish(a, &d, "PearsonCorr", &part);
    var lib = Library.init(a);
    try capture.finish(&lib, &d);
    try std.testing.expect(lib.find("c") != null);
    try std.testing.expect(lib.find("m") == null);
    try capture.publish(a, &d, "Moments", &part);
    try capture.finish(&lib, &d);
    try std.testing.expect(lib.find("m") == null);
    try std.testing.expect(!d.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, try d.render(), "Output 'Moments' was not created") != null);
}

test "FEAT-odsoutput table types cannot silently change" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var capture: Capture = .{};
    try capture.parse(a, &d, try lex.tokenize(a, "ods output Moments=m;", &d));
    var x = Dataset.init(a, "");
    _ = try x.addColumn("x", .num);
    var y = Dataset.init(a, "");
    _ = try y.addColumn("x", .char);
    try capture.publish(a, &d, "Moments", &x);
    try std.testing.expectError(error.ParseError, capture.publish(a, &d, "Moments", &y));
    try std.testing.expect(d.hasErrors());
}
test "FEAT-odsoutput SAS M9 seven producer schemas row counts and precise cells" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    var capture: Capture = .{};
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    for ([_][]const u8{ "b", "x", "y" }) |name| _ = try ds.addColumn(name, .num);
    ds.setLabel("b", "Group");
    ds.setFormat("b", "2.");
    for ([_][3]f64{ .{ 1, 1, 3 }, .{ 1, 2, 5 }, .{ 1, 4, 4 }, .{ 2, 3, 1 }, .{ 2, 5, 2 }, .{ 2, 7, 9 } }) |row| try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] } });
    try lib.put("d", ds);
    const proc = @import("proc.zig");
    const cx: proc.ProcCtx = .{ .arena = a, .diags = &d, .lib = &lib, .capture = &capture };
    var listing: std.ArrayList(u8) = .empty;
    try capture.parse(a, &d, try lex.tokenize(a, "ods output PearsonCorr=pc SimpleStats=ss;", &d));
    try @import("stat/corr.zig").run(cx, &listing, try lex.tokenize(a, "proc corr data=d; by b; var x y; run;", &d));
    try capture.finish(&lib, &d);
    try capture.parse(a, &d, try lex.tokenize(a, "ods output OneWayFreqs=ow CrossTabFreqs=ct;", &d));
    try proc.runFreq(cx, &listing, try lex.tokenize(a, "proc freq data=d; by b; tables x x*y; run;", &d));
    try capture.finish(&lib, &d);
    try capture.parse(a, &d, try lex.tokenize(a, "ods output Moments=mo Quantiles=qu BasicMeasures=bm;", &d));
    try proc.runUnivariate(cx, &listing, try lex.tokenize(a, "proc univariate data=d; by b; var x y; run;", &d));
    try capture.finish(&lib, &d);
    const expected_rows = [_]usize{ 4, 4, 6, 32, 24, 44, 16 };
    const expected_columns = [_]usize{ 6, 8, 8, 11, 8, 4, 6 };
    for ([_][]const u8{ "pc", "ss", "ow", "ct", "mo", "qu", "bm" }, expected_rows, expected_columns) |name, nr, nc| {
        const got = lib.find(name).?;
        try std.testing.expectEqual(nr, got.rowCount());
        try std.testing.expectEqual(nc, got.columns.items.len);
        try std.testing.expectEqualStrings("Group", got.columns.items[0].label.?);
        try std.testing.expectEqualStrings("2.", got.columns.items[0].format.?);
    }
    const pc = lib.find("pc").?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.32732683535398), pc.row(0)[pc.indexOf("y").?].num, 1e-13);
    try std.testing.expectEqual(@as(u8, '_'), Value.missingChar(pc.row(0)[pc.indexOf("Px").?].num));
    const mo = lib.find("mo").?;
    try std.testing.expectApproxEqAbs(@as(f64, 7.0 / 3.0), mo.row(1)[mo.indexOf("nValue1").?].num, 1e-14);
    try std.testing.expectEqualStrings("2.33333333", mo.row(1)[mo.indexOf("cValue1").?].str);
    try std.testing.expectEqualStrings("Std Error Mean", mo.row(5)[mo.indexOf("Label2").?].str);
    const qu = lib.find("qu").?;
    try std.testing.expectEqualStrings("50% Median", qu.row(5)[qu.indexOf("Quantile").?].str);
    try std.testing.expectEqual(@as(f64, 2), qu.row(5)[qu.indexOf("Estimate").?].num);
    const ct = lib.find("ct").?;
    try std.testing.expectEqualStrings("00", ct.row(15)[ct.indexOf("_TYPE_").?].str);
    try std.testing.expectEqual(@as(f64, 3), ct.row(15)[ct.indexOf("Frequency").?].num);
    try std.testing.expect(!d.hasErrors());
}

fn member(name: []const u8) []const u8 {
    return if (name.len > 5 and eq(name[0..5], "work.")) name[5..] else name;
}
test "FEAT-odsoutput duplicate target first request wins and CLOSE clears" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var capture: Capture = .{};
    try capture.parse(a, &d, try lex.tokenize(a, "ods output Moments=same Quantiles=work.SAME;", &d));
    try std.testing.expectEqual(@as(usize, 1), capture.requests.items.len);
    try std.testing.expect(capture.wants("Moments"));
    try std.testing.expect(!capture.wants("Quantiles"));
    try std.testing.expect(std.mem.indexOf(u8, try d.render(), "Duplicate data set name") != null);
    try capture.parse(a, &d, try lex.tokenize(a, "ods output close;", &d));
    try std.testing.expectEqual(@as(usize, 0), capture.requests.items.len);
}

test "FEAT-odsoutput repeated FREQ variables renamed and requests union by name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    var capture: Capture = .{};
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("b", .num);
    _ = try ds.addColumn("x", .num);
    for ([_][2]f64{ .{ 1, 1 }, .{ 1, 2 }, .{ 2, 2 }, .{ 2, 3 } }) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] } });
    try lib.put("d", ds);
    try capture.parse(a, &d, try lex.tokenize(a, "ods output CrossTabFreqs=c OneWayFreqs=o;", &d));
    var listing: std.ArrayList(u8) = .empty;
    try @import("proc.zig").runFreq(.{ .arena = a, .lib = &lib, .diags = &d, .capture = &capture }, &listing, try lex.tokenize(a, "proc freq data=d; by b; tables b b*x x*x; run;", &d));
    try capture.finish(&lib, &d);
    const o = lib.find("o").?;
    const c = lib.find("c").?;
    try std.testing.expectEqualStrings("b2", o.columns.items[3].name);
    try std.testing.expectEqualStrings("b", o.columns.items[3].label.?);
    try std.testing.expectEqual(@as(usize, 2), o.rowCount());
    try std.testing.expectEqual(@as(usize, 30), c.rowCount());
    try std.testing.expectEqual(@as(usize, 12), c.columns.items.len);
    try std.testing.expectEqualStrings("b2", c.columns.items[2].name);
    try std.testing.expectEqualStrings("x2", c.columns.items[11].name);
    try std.testing.expectEqual(@as(f64, 1), c.row(6)[c.indexOf("x2").?].num);
}

test "FEAT-odsoutput missing pair counts labels and UNIVARIATE CLASS character schema" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    var capture: Capture = .{};
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    for ([_][]const u8{ "x", "y" }) |name| _ = try ds.addColumn(name, .num);
    ds.setLabel("x", "X label");
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 3 } });
    try ds.appendRow(&.{ .{ .num = 2 }, Value.missing });
    try ds.appendRow(&.{ Value.missing, .{ .num = 4 } });
    try ds.appendRow(&.{ .{ .num = 4 }, .{ .num = 5 } });
    try lib.put("d", ds);
    var listing: std.ArrayList(u8) = .empty;
    const cx: @import("proc.zig").ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d, .capture = &capture };
    try capture.parse(a, &d, try lex.tokenize(a, "ods output PearsonCorr=pc;", &d));
    try @import("stat/corr.zig").run(cx, &listing, try lex.tokenize(a, "proc corr data=d; var x y; run;", &d));
    try capture.finish(&lib, &d);
    const pc = lib.find("pc").?;
    try std.testing.expectEqual(@as(usize, 8), pc.columns.items.len);
    try std.testing.expectEqualStrings("Label", pc.columns.items[1].name);
    try std.testing.expectEqual(@as(f64, 2), pc.row(0)[pc.indexOf("Ny").?].num);
    try std.testing.expectEqual(@as(f64, 3), pc.row(0)[pc.indexOf("Nx").?].num);
    try capture.parse(a, &d, try lex.tokenize(a, "ods output Moments=m;", &d));
    try @import("proc.zig").runUnivariate(cx, &listing, try lex.tokenize(a, "proc univariate data=d; class y; var x; run;", &d));
    try capture.finish(&lib, &d);
    const m = lib.find("m").?;
    try std.testing.expectEqualStrings("y", m.columns.items[1].name);
    try std.testing.expectEqual(@import("pdv.zig").VarType.char, m.columns.items[1].type);
    try std.testing.expectEqual(@as(?usize, 16), m.columns.items[1].len);
    try std.testing.expectEqualStrings("3", m.row(0)[1].str);
}
test "FEAT-odsoutput negative FREQ weights remove percentage schema SAS M9" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    var capture: Capture = .{};
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    for ([_][]const u8{ "x", "y", "w" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][3]f64{ .{ 1, 3, 1 }, .{ 1, 5, 2 }, .{ 4, 4, 0 }, .{ 7, 1, -1 } }) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] } });
    try lib.put("d", ds);
    try capture.parse(a, &d, try lex.tokenize(a, "ods output OneWayFreqs=o CrossTabFreqs=c;", &d));
    var listing: std.ArrayList(u8) = .empty;
    try @import("proc.zig").runFreq(.{ .arena = a, .lib = &lib, .diags = &d, .capture = &capture }, &listing, try lex.tokenize(a, "proc freq data=d; weight w; tables x x*y; run;", &d));
    try capture.finish(&lib, &d);
    const o = lib.find("o").?;
    const c = lib.find("c").?;
    try std.testing.expectEqual(@as(usize, 5), o.columns.items.len);
    try std.testing.expectEqual(@as(usize, 7), c.columns.items.len);
    try std.testing.expectEqual(@as(f64, 2), o.row(1)[o.indexOf("CumFrequency").?].num);
    try std.testing.expect(c.indexOf("Percent") == null);
    try std.testing.expectEqualStrings("o", @import("proc.zig").lastDataset(&lib).?.name);
}
