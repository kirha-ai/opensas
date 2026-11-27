//! Minimal SGSCATTER prerequisite for STAT-GLM-002, S154 physical p.4051.
//! PROC SGSCATTER [DATA=member]; PLOT numeric-y * numeric-x; RUN;
//! SG procedures generate graphs even with ODS GRAPHICS OFF (SAS ODS User's
//! Guide, ODS GRAPHICS statement); only destination selection suppresses them.
//! Native SVG publication reuses graphics_svg.Session, including GPATH, atomic
//! filenames and destination routing. There is no placeholder or text listing.
const std = @import("std");
const proc = @import("../proc.zig");
const lex = @import("../lexer.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const svg = @import("graphics_svg.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;

pub const Spec = struct { ds: *Dataset, x: usize, y: usize };
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, name: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, name);
}
fn expect(d: *diag.Diagnostics, t: []const lex.Token, i: *usize, tag: lex.Tag) diag.Error!void {
    if (!at(t, i.*, tag)) return d.fail(error.ParseError, if (i.* < t.len) t[i.*].line else 0, "PROC SGSCATTER: expected {s}", .{@tagName(tag)});
    i.* += 1;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    if (!kw(t, 0, "proc") or !kw(t, 1, "sgscatter")) return cx.diags.fail(error.ParseError, 0, "PROC SGSCATTER: invalid procedure header", .{});
    var i: usize = 2;
    var name: ?[]const u8 = null;
    if (kw(t, i, "data")) {
        i += 1;
        try expect(cx.diags, t, &i, .eq);
        try expect(cx.diags, t, &i, .name);
        name = t[i - 1].text;
        if (at(t, i, .dot)) {
            i += 1;
            try expect(cx.diags, t, &i, .name);
            name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name.?, t[i - 1].text });
        }
    }
    if (!at(t, i, .semicolon)) return proc.failGap(cx.diags, 0, "PROC SGSCATTER: only DATA= is supported in the procedure header", .{});
    i += 1;
    if (!kw(t, i, "plot")) return proc.failGap(cx.diags, 0, "PROC SGSCATTER: requires one PLOT y*x statement; other statements are not implemented", .{});
    i += 1;
    try expect(cx.diags, t, &i, .name);
    const yn = t[i - 1].text;
    try expect(cx.diags, t, &i, .star);
    try expect(cx.diags, t, &i, .name);
    const xn = t[i - 1].text;
    if (!at(t, i, .semicolon)) return proc.failGap(cx.diags, 0, "PROC SGSCATTER: plot options and multiple plot requests are not implemented", .{});
    i += 1;
    if (kw(t, i, "run") or kw(t, i, "quit")) {
        i += 1;
        try expect(cx.diags, t, &i, .semicolon);
    }
    if (kw(t, i, "quit")) {
        i += 1;
        try expect(cx.diags, t, &i, .semicolon);
    }
    if (i < t.len and !at(t, i, .eof)) return proc.failGap(cx.diags, 0, "PROC SGSCATTER: additional statements are not implemented", .{});
    const ds = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ExecError, 0, "PROC SGSCATTER: dataset {s} not found", .{name orelse "_LAST_"});
    const x = ds.indexOf(xn) orelse return cx.diags.fail(error.ParseError, 0, "PROC SGSCATTER: variable {s} not found", .{xn});
    const y = ds.indexOf(yn) orelse return cx.diags.fail(error.ParseError, 0, "PROC SGSCATTER: variable {s} not found", .{yn});
    for ([_]usize{ x, y }) |c| {
        if (ds.columns.items[c].type != .num) return proc.failGap(cx.diags, 0, "PROC SGSCATTER: only numeric axes are implemented", .{});
        if (ds.columns.items[c].format != null) return proc.failGap(cx.diags, 0, "PROC SGSCATTER: formatted axes are not implemented", .{});
    }
    return .{ .ds = ds, .x = x, .y = y };
}

/// The dispatcher clears/flushes the graphics session as for other procedures.
/// Supply cx.graphics for SG procedures regardless of Session.enabled/sink().
pub fn run(cx: proc.ProcCtx, tokens: []const lex.Token) diag.Error!void {
    const spec = try parse(cx, tokens);
    // This minimal path does not claim SAS ODS TRACE metadata compatibility.
    if (cx.listing) |dest| if (dest.trace != null) return proc.failGap(cx.diags, 0, "PROC SGSCATTER: ODS TRACE metadata is not implemented", .{});
    const bytes = try render(cx.arena, cx.diags, spec, cx.graph_title);
    if (cx.listing) |dest| if (!dest.accepts("SGScatter.ScatterPlot")) return;
    const session = cx.graphics orelse return proc.failGap(cx.diags, 0, "PROC SGSCATTER: requires a native graphics consumer", .{});
    // Deliberately do not test session.enabled: OFF does not disable SG procs.
    try session.queue(0, "sgscatter", bytes, .{ .name = .ScatterPlot, .label = "Scatter Plot", .template = null, .path = "SGScatter.ScatterPlot" });
}

/// Render actual complete x/y pairs. Labels and title are XML-escaped; missing
/// pairs are omitted, while infinities and unrepresentable axes fail visibly.
pub fn render(a: A, d: *diag.Diagnostics, spec: Spec, title: ?[]const u8) diag.Error![]const u8 {
    var xr = svg.Range{};
    var yr = svg.Range{};
    var n: usize = 0;
    for (spec.ds.rows.items) |row| {
        const x = row[spec.x].num;
        const y = row[spec.y].num;
        if (std.math.isNan(x) or std.math.isNan(y)) continue;
        if (!std.math.isFinite(x) or !std.math.isFinite(y)) return d.fail(error.ExecError, 0, "PROC SGSCATTER: nonfinite plot coordinate", .{});
        xr.add(x);
        yr.add(y);
        n += 1;
    }
    if (n == 0) return d.fail(error.ExecError, 0, "PROC SGSCATTER: no complete numeric pairs", .{});
    const b = svg.Bounds{ .x = xr.padded(), .y = yr.padded(), .top = 65, .bottom = 390 };
    for ([_]svg.Range{ b.x, b.y }) |r| if (!std.math.isFinite(r.lo) or !std.math.isFinite(r.hi) or !std.math.isFinite(r.hi - r.lo) or !(r.hi > r.lo)) return d.fail(error.ExecError, 0, "PROC SGSCATTER: axis range is not representable", .{});
    return draw(a, spec, title, b, n) catch return error.OutOfMemory;
}

fn draw(a: A, spec: Spec, title: ?[]const u8, b: svg.Bounds, n: usize) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(a);
    errdefer out.deinit();
    const w = &out.writer;
    const heading = title orelse "Scatter Plot";
    try w.writeAll("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"720\" height=\"470\" viewBox=\"0 0 720 470\" role=\"img\" data-kind=\"sgscatter\"><title>");
    try svg.escaped(w, heading);
    try w.print("</title><desc>Scatter plot of {d} complete observations.</desc>", .{n});
    try w.writeAll("<style>text{font:13px system-ui,sans-serif;fill:#263445}.heading{font-size:19px;font-weight:600}.axes path{stroke:#738295;fill:none}.point{fill:white;stroke:#245c92;stroke-width:1.5}</style><rect width=\"720\" height=\"470\" fill=\"white\"/><text class=\"heading\" x=\"360\" y=\"32\" text-anchor=\"middle\">");
    try svg.escaped(w, heading);
    try w.print("</text><g class=\"axes\"><path d=\"M{d} {d}V{d}H{d}\"/>", .{ svg.Bounds.left, b.top, b.bottom, svg.Bounds.right });
    for (0..6) |i| {
        const fraction = @as(f64, @floatFromInt(i)) / 5;
        try svg.tick(a, w, b, true, b.x.at(fraction), b.x.at(fraction));
        try svg.tick(a, w, b, false, b.y.at(fraction), b.y.at(fraction));
    }
    try w.writeAll("</g><text class=\"axis-x\" x=\"374\" y=\"447\" text-anchor=\"middle\">");
    try svg.escaped(w, spec.ds.columns.items[spec.x].label orelse spec.ds.columns.items[spec.x].name);
    try w.writeAll("</text><text class=\"axis-y\" transform=\"translate(20 228) rotate(-90)\" text-anchor=\"middle\">");
    try svg.escaped(w, spec.ds.columns.items[spec.y].label orelse spec.ds.columns.items[spec.y].name);
    try w.writeAll("</text>");
    for (spec.ds.rows.items, 1..) |row, observation| {
        const x = row[spec.x].num;
        const y = row[spec.y].num;
        if (std.math.isNan(x) or std.math.isNan(y)) continue;
        try w.print("<circle class=\"point\" data-observation=\"{d}\" data-x=\"{d}\" data-y=\"{d}\" cx=\"{d:.3}\" cy=\"{d:.3}\" r=\"4\"/>", .{ observation, x, y, b.px(x), b.py(y) });
    }
    try w.writeAll("</svg>\n");
    return out.written();
}

const testing = std.testing;
fn iron(a: A) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "iron");
    _ = try ds.addColumn("fe", .num);
    _ = try ds.addColumn("loss", .num);
    const x = [_]f64{ 0.01, 0.48, 0.71, 0.95, 1.19, 0.01, 0.48, 1.44, 0.71, 1.96, 0.01, 1.44, 1.96 };
    const y = [_]f64{ 127.6, 124, 110.8, 103.9, 101.5, 130.1, 122, 92.3, 113.1, 83.7, 128, 91.4, 86.2 };
    for (x, y) |xx, yy| try ds.appendRow(&.{ .{ .num = xx }, .{ .num = yy } });
    return ds;
}

test "SGSCATTER original iron data publishes native graph with ODS GRAPHICS OFF" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("iron", try iron(a));
    var dir = testing.tmpDir(.{});
    defer dir.cleanup();
    var listing = @import("../ods_listing.zig").Listing{};
    var session = svg.Session{ .arena = a, .io = testing.io, .diags = &d, .enabled = false, .listing = &listing, .gpath = try dir.dir.realPathFileAlloc(testing.io, ".", a) };
    const cx = proc.ProcCtx{ .arena = a, .diags = &d, .lib = &lib, .graphics = &session, .listing = &listing, .graph_title = "Regression in PROC GLM" };
    try run(cx, try lex.tokenize(a, "proc sgscatter data=work.IRON; plot LOSS*FE; run;", &d));
    try session.flush();
    const bytes = try dir.dir.readFileAlloc(testing.io, "opensas-0001-sgscatter.svg", a, .limited(1 << 20));
    try testing.expect(!d.hasErrors());
    try testing.expectEqual(@as(usize, 13), std.mem.count(u8, bytes, "<circle "));
    try testing.expect(std.mem.indexOf(u8, bytes, "data-x=\"0.01\" data-y=\"127.6\"") != null);
    try testing.expect(std.mem.indexOf(u8, bytes, "data-x=\"1.96\" data-y=\"86.2\"") != null);
    try testing.expect(std.mem.indexOf(u8, bytes, ">fe</text>") != null);
    try testing.expect(std.mem.indexOf(u8, bytes, ">loss</text>") != null);
    try testing.expect(std.mem.indexOf(u8, bytes, "Regression in PROC GLM") != null);
    session.enabled = null;
    try run(cx, try lex.tokenize(a, "proc sgscatter; plot loss*fe; run;", &d));
    try session.flush();
    try testing.expectEqualStrings(bytes, try dir.dir.readFileAlloc(testing.io, "opensas-0002-sgscatter.svg", a, .limited(1 << 20)));
    // Destination suppression remains effective even though GRAPHICS OFF does not.
    listing.open = false;
    try run(cx, try lex.tokenize(a, "proc sgscatter; plot loss*fe; run;", &d));
    try testing.expectEqual(@as(usize, 0), session.prepared.items.len);
}

test "SGSCATTER labels missing pairs and constant axes retain real coordinates" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    ds.setLabel("x", "Iron <content> & percent");
    try ds.appendRow(&.{ .{ .num = 2 }, .{ .num = 4 } });
    try ds.appendRow(&.{ .{ .num = 2 }, .{ .num = 4 } });
    try ds.appendRow(&.{ .{ .num = std.math.nan(f64) }, .{ .num = 100 } });
    const bytes = try render(a, &d, .{ .ds = &ds, .x = 0, .y = 1 }, "A < B");
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, bytes, "<circle "));
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, bytes, "cx=\"374.000\" cy=\"227.500\""));
    try testing.expect(std.mem.indexOf(u8, bytes, "Iron &lt;content&gt; &amp; percent") != null);
    try testing.expect(std.mem.indexOf(u8, bytes, "A &lt; B") != null);
    try ds.appendRow(&.{ .{ .num = std.math.inf(f64) }, .{ .num = 4 } });
    try testing.expectError(error.ExecError, render(a, &d, .{ .ds = &ds, .x = 0, .y = 1 }, null));
    try testing.expect(d.hasErrors());
}

test "SGSCATTER unsupported syntax and absent consumer fail through diagnostics" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("iron", try iron(a));
    for ([_][]const u8{
        "proc sgscatter data=iron; plot loss*fe / reg; run;",
        "proc sgscatter data=iron; matrix loss fe; run;",
        "proc sgscatter data=iron; plot loss*fe; by fe; run;",
        "proc sgscatter data=iron; plot loss*fe; plot fe*loss; run;",
        "proc sgscatter data=iron; plot loss*fe; run;",
    }) |source| {
        var d = diag.Diagnostics.init(a);
        const cx = proc.ProcCtx{ .arena = a, .diags = &d, .lib = &lib };
        try testing.expectError(error.ParseError, run(cx, try lex.tokenize(a, source, &d)));
        try testing.expect(d.hasErrors());
    }
}

test "SGSCATTER axes map observations independently and reject empty pairs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    const spec = Spec{ .ds = &ds, .x = 0, .y = 1 };
    try ds.appendRow(&.{ .{ .num = std.math.nan(f64) }, .{ .num = 100 } });
    try testing.expectError(error.ExecError, render(a, &d, spec, null));
    try testing.expect(d.hasErrors());
    try ds.appendRow(&.{ .{ .num = 0 }, .{ .num = 100 } });
    try ds.appendRow(&.{ .{ .num = 10 }, .{ .num = 200 } });
    const bytes = try render(a, &d, spec, null);
    // 5% padding places each extreme 1/22 of the 572x325 frame from its edge.
    try testing.expect(std.mem.indexOf(u8, bytes, "data-x=\"0\" data-y=\"100\" cx=\"114.000\" cy=\"375.227\"") != null);
    try testing.expect(std.mem.indexOf(u8, bytes, "data-x=\"10\" data-y=\"200\" cx=\"634.000\" cy=\"79.773\"") != null);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, bytes, "<circle "));
}

test "SGSCATTER missing variables and formatted axes are captured failures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    const ds = try iron(a);
    try lib.put("iron", ds);
    for ([_][]const u8{
        "proc sgscatter data=iron; plot absent*fe; run;",
        "proc sgscatter data=iron; plot loss fe; run;",
        "proc sgscatter data=iron(obs=2); plot loss*fe; run;",
    }) |source| {
        var d = diag.Diagnostics.init(a);
        const cx = proc.ProcCtx{ .arena = a, .diags = &d, .lib = &lib };
        try testing.expectError(error.ParseError, run(cx, try lex.tokenize(a, source, &d)));
        try testing.expect(d.hasErrors());
    }
    ds.setFormat("fe", "percent8.2");
    var d = diag.Diagnostics.init(a);
    const cx = proc.ProcCtx{ .arena = a, .diags = &d, .lib = &lib };
    try testing.expectError(error.ParseError, run(cx, try lex.tokenize(a, "proc sgscatter; plot loss*fe; run;", &d)));
    try testing.expect(d.hasErrors());
}
