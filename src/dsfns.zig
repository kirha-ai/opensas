//! The SCL dataset-access engine — the OPEN/FETCH/GETVAR family of functions that
//! read an in-memory Dataset through an integer data-set id (`dsid`).
//!
//! OPEN(member) looks the table up in the bound Library and returns a dsid into a
//! module-global table of open datasets; each open dataset carries a 1-based
//! current-observation cursor that FETCH/FETCHOBS move and GETVARN/GETVARC read.
//!
//! The executor binds the live Library once via `bind()`; until then OPEN/EXIST
//! find nothing (they return 0). ponytail: no update/where/by clauses, no engine
//! options — read-only sequential/positional access over the in-memory tables.

const std = @import("std");
const exec = @import("exec.zig");
const Library = exec.Library;
const Dataset = @import("dataset.zig").Dataset;
const Value = @import("value.zig").Value;
const sio = @import("io.zig");

const OpenDs = struct {
    ds: *Dataset,
    open: bool = true,
    cur: usize = 0, // 1-based current observation; 0 = none fetched yet
    row: ?[]const Value = null, // the fetched row (borrowed from ds.rows)
};

var g_arena: ?std.heap.ArenaAllocator = null;
var opens: std.ArrayList(OpenDs) = .empty;
var bound: ?*Library = null;

/// Drop all handles from a prior run (taste #12) — open dsids point at that
/// run's (now-freed) Library, the disk-load cache at this module's arena.
pub fn resetPerRun() void {
    if (g_arena) |*ar| ar.deinit();
    g_arena = null;
    opens = .empty;
    disk_loaded = .empty;
    bound = null;
    librefs = &.{};
}

fn arena() std.mem.Allocator {
    if (g_arena == null) g_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    return g_arena.?.allocator();
}

/// The executor calls this once so OPEN/EXIST resolve names against the live tables.
pub fn bind(lib: *Library) void {
    bound = lib;
}

/// A `libname NAME "dir"` declaration, as bound by the CLI (BUG-existdisk):
/// EXIST must see members that live on disk in a libref dir even when nothing
/// preloaded them into memory — a member named only inside macro text is
/// invisible to main's literal-`lib.ds`-token preload.
pub const Libref = struct { name: []const u8, dir: []const u8 };
var librefs: []const Libref = &.{};

/// Bound once per run by the CLI; empty for pure-in-memory runs (io == null),
/// which have no disk semantics. A rebind is a run boundary — drop the OPEN
/// disk-load cache, whose names could otherwise resolve against the previous
/// run's libref dirs.
pub fn bindLibrefs(refs: []const Libref) void {
    librefs = refs;
    disk_loaded.clearRetainingCapacity();
}

/// The directory bound to `libref`, if any — PROC DATASETS DELETE/KILL unlink
/// member files through this, else the disk probe below makes deleted members
/// undead (BUG-datasetsdeletedisk).
pub fn librefDir(name: []const u8) ?[]const u8 {
    for (librefs) |lr| if (eqi(lr.name, name)) return lr.dir;
    return null;
}

/// Every bound libref — SASHELP.VTABLE enumerates their dirs so disk-only
/// members show in the dictionary view (GAP-vtabledisk).
pub fn boundLibrefs() []const Libref {
    return librefs;
}

fn memberPath(dir: []const u8, member: []const u8) ?[]const u8 {
    var buf: [1024]u8 = undefined;
    for (sio.member_exts) |ext| {
        const path = std.fmt.bufPrint(&buf, "{s}/{s}{s}", .{ dir, member, ext }) catch return null;
        if (sio.fileExistsRaw(path)) return arena().dupe(u8, path) catch null;
    }
    return null;
}

/// The on-disk file behind `libref.member` under a bound libref: the libref's
/// file itself when it points straight at a dataset file, else
/// `dir/member.{sas7bdat,xpt,csv}` — probing the member as written and
/// lower-cased (SAS names are case-insensitive; disk files usually aren't).
/// Arena-owned path, or null. EXIST uses it as a pure probe; OPEN loads
/// through it (GAP-opendisk).
fn diskPath(name: []const u8) ?[]const u8 {
    const nm = std.mem.trim(u8, name, " ");
    const dot = std.mem.lastIndexOfScalar(u8, nm, '.') orelse return null;
    const lr = for (librefs) |lr| {
        if (eqi(lr.name, nm[0..dot])) break lr;
    } else return null;
    // A libref pointed straight at a dataset FILE: every member maps to it
    // (same rule as main's loadLibInputs).
    if (sio.endsWithIgnoreCase(lr.dir, ".sas7bdat") or sio.endsWithIgnoreCase(lr.dir, ".xpt"))
        return if (sio.fileExistsRaw(lr.dir)) lr.dir else null;
    const member = nm[dot + 1 ..];
    if (memberPath(lr.dir, member)) |p| return p;
    var mbuf: [32]u8 = undefined; // SAS member names are <= 32 chars
    if (member.len > mbuf.len) return null;
    const lower = std.ascii.lowerString(&mbuf, member);
    if (std.mem.eql(u8, lower, member)) return null;
    return memberPath(lr.dir, lower);
}

/// Disk members OPEN has lazy-loaded, keyed by name — one load per member no
/// matter how often a dataset-existence-check pattern re-opens it.
var disk_loaded: std.ArrayList(struct { name: []const u8, ds: *Dataset }) = .empty;

/// Lazy-load a disk-only member for OPEN, into the dsfns arena — deliberately
/// NOT into the bound Library, so writeLibOutputs/loaded_ro semantics stay
/// untouched (GAP-opendisk). Applies the `.labels` sidecar (VARLABEL/VARFMT/
/// VARINFMT read those attrs). Null when the member isn't on disk or won't parse.
fn loadFromDisk(name: []const u8) ?*Dataset {
    const nm = std.mem.trim(u8, name, " ");
    for (disk_loaded.items) |e| if (eqi(e.name, nm)) return e.ds;
    const path = diskPath(nm) orelse return null;
    const a = arena();
    const bytes = sio.readFileRaw(a, path) orelse return null;
    const member = nm[(std.mem.lastIndexOfScalar(u8, nm, '.') orelse return null) + 1 ..];
    const ds = (sio.readByExt(a, path, bytes, member) catch return null) orelse return null;
    if (std.mem.lastIndexOfScalar(u8, path, '.')) |ext| { // data path -> sidecar path
        const lpath = std.fmt.allocPrint(a, "{s}{s}", .{ path[0..ext], sio.label_ext }) catch return null;
        if (sio.readFileRaw(a, lpath)) |lb| sio.applyLabelSidecar(a, ds, lb) catch {};
    }
    disk_loaded.append(a, .{ .name = a.dupe(u8, nm) catch return null, .ds = ds }) catch return null;
    return ds;
}

fn find(name: []const u8) ?*Dataset {
    const lib = bound orelse return null;
    if (lib.find(name)) |ds| return ds; // handles `work.` + one-level names
    // fall back to the bare member (after any libref) for other librefs
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |d| return lib.find(name[d + 1 ..]);
    return null;
}

/// A 1-based index from user input (a dsid, obs number, or var number), bounded
/// to `[1, len]`. Returns the 0-based slice index, or null for a non-finite or
/// out-of-range value. This is the ONE guard that keeps `@intFromFloat` from
/// panicking: a NaN slips a plain `n < 1` (`NaN < 1` is false) → `@intFromFloat`
/// aborts, and a huge/inf value is "integer part out of bounds" (BUG-dsfnsclose).
/// `!(n >= 1)` catches NaN and `n < 1`; `n > len_f` catches huge/inf and past-end.
fn idx(n: f64, len: usize) ?usize {
    const len_f: f64 = @floatFromInt(len);
    if (!(n >= 1) or n > len_f) return null;
    return @as(usize, @intFromFloat(n)) - 1;
}

fn entry(dsid: f64) ?*OpenDs {
    const i = idx(dsid, opens.items.len) orelse return null;
    const o = &opens.items[i];
    return if (o.open) o else null;
}

const miss = std.math.nan(f64);

/// EXIST(member): 1 if the data set is in the library or on disk under a bound
/// libref (BUG-existdisk), else 0.
pub fn exist(name: []const u8) f64 {
    if (find(name) != null) return 1;
    return if (diskPath(name) != null) 1 else 0;
}

/// The DISK half of EXIST on its own: does `libref.member` have a file under a
/// bound libref? main's step-commit rule needs this WITHOUT `find`'s bare-member
/// fallback — a WORK data set of the same short name must not be mistaken for a
/// permanent member (GAP-errgatereplaces). Always false with no bound librefs
/// (a pure in-memory run has no disk semantics).
pub fn onDisk(name: []const u8) bool {
    return diskPath(name) != null;
}

/// OPEN(member): a positive dsid, or 0 if the table does not exist. A member
/// that lives only on disk under a bound libref (never SET) is lazy-loaded
/// (GAP-opendisk). ponytail: the load cache is per run (cleared on rebind);
/// a within-run DELETE then re-OPEN of the same disk member serves the cached
/// rows — evict on delete if a real program ever does that.
pub fn open(name: []const u8) f64 {
    const ds = find(name) orelse loadFromDisk(name) orelse return 0;
    opens.append(arena(), .{ .ds = ds }) catch return 0;
    return @floatFromInt(opens.items.len);
}

/// CLOSE(dsid): 0 on success (the id is retired), a non-zero SAS-ish error else.
pub fn close(dsid: f64) f64 {
    const o = entry(dsid) orelse return -1;
    o.open = false;
    o.row = null;
    return 0;
}

/// ATTRN(dsid, attr): a numeric attribute — NOBS/NLOBS (observations), NVARS
/// (variables), ANY (1 when the set has rows/vars). Missing for the unknown.
pub fn attrn(dsid: f64, attr: []const u8) f64 {
    const o = entry(dsid) orelse return miss;
    if (eqi(attr, "NOBS") or eqi(attr, "NLOBS")) return @floatFromInt(o.ds.rows.items.len);
    if (eqi(attr, "NVARS")) return @floatFromInt(o.ds.columns.items.len);
    if (eqi(attr, "ANY")) return if (o.ds.rows.items.len > 0 and o.ds.columns.items.len > 0) 1 else 0;
    return miss;
}

/// ATTRC(dsid, attr): a character attribute — currently MEMNAME (the table name).
pub fn attrc(dsid: f64, attr: []const u8) []const u8 {
    const o = entry(dsid) orelse return "";
    if (eqi(attr, "MEMNAME")) return o.ds.name;
    return "";
}

/// VARNUM(dsid, name): the 1-based position of variable `name`, or 0 if absent.
pub fn varnum(dsid: f64, name: []const u8) f64 {
    const o = entry(dsid) orelse return 0;
    return if (o.ds.indexOf(name)) |ix| @floatFromInt(ix + 1) else 0;
}

/// FETCH(dsid): read the next observation into the current row. 0 on success,
/// -1 at end of file.
pub fn fetch(dsid: f64) f64 {
    const o = entry(dsid) orelse return -1;
    if (o.cur >= o.ds.rows.items.len) {
        o.row = null;
        return -1;
    }
    o.cur += 1;
    o.row = o.ds.rows.items[o.cur - 1];
    return 0;
}

/// FETCHOBS(dsid, n): read the n-th (1-based) observation. 0 on success, -1 if
/// the observation number is out of range.
pub fn fetchobs(dsid: f64, n: f64) f64 {
    const o = entry(dsid) orelse return -1;
    const i = idx(n, o.ds.rows.items.len) orelse return -1;
    o.cur = i + 1;
    o.row = o.ds.rows.items[i];
    return 0;
}

/// CUROBS(dsid): the observation number of the current row, 0 if none is fetched.
pub fn curobs(dsid: f64) f64 {
    const o = entry(dsid) orelse return 0;
    return if (o.row == null) 0 else @floatFromInt(o.cur);
}

/// GETVARN(dsid, n): the n-th variable of the current row as a number (missing if
/// there is no current row, n is out of range, or the value is character).
pub fn getvarn(dsid: f64, n: f64) f64 {
    const o = entry(dsid) orelse return miss;
    const row = o.row orelse return miss;
    const i = idx(n, row.len) orelse return miss;
    return switch (row[i]) {
        .num => |x| x,
        .str => miss,
    };
}

/// GETVARC(dsid, n): the n-th variable of the current row as a string ("" if no
/// current row, out of range, or the value is numeric).
pub fn getvarc(dsid: f64, n: f64) []const u8 {
    const o = entry(dsid) orelse return "";
    const row = o.row orelse return "";
    const i = idx(n, row.len) orelse return "";
    return switch (row[i]) {
        .str => |s| s,
        .num => "",
    };
}

fn col(dsid: f64, n: f64) ?@import("dataset.zig").Column {
    const o = entry(dsid) orelse return null;
    const i = idx(n, o.ds.columns.items.len) orelse return null;
    return o.ds.columns.items[i];
}

/// VARNAME(dsid, n): the name of the n-th (1-based) variable, or "".
pub fn varname(dsid: f64, n: f64) []const u8 {
    return if (col(dsid, n)) |c| c.name else "";
}

/// VARLABEL(dsid, n): the n-th variable's label — its name, since the dataset
/// model carries no labels (SAS also falls back to the name for an unlabeled var).
pub fn varlabel(dsid: f64, n: f64) []const u8 {
    // CALL LABEL semantics: the LABEL, falling back to the variable NAME when none.
    const c = col(dsid, n) orelse return "";
    return c.label orelse varname(dsid, n);
}

/// VARLABEL() function semantics: the LABEL, or BLANK when none (BUG-sclmeta) —
/// unlike CALL LABEL, which falls back to the name.
pub fn varlabelRaw(dsid: f64, n: f64) []const u8 {
    const c = col(dsid, n) orelse return "";
    return c.label orelse "";
}

/// VARTYPE(dsid, n): "N" for a numeric variable, "C" for character, "" if absent.
pub fn vartype(dsid: f64, n: f64) []const u8 {
    const c = col(dsid, n) orelse return "";
    return if (c.type == .num) "N" else "C";
}

/// VARFMT(dsid, n): the n-th variable's display format, or "" if none is attached.
pub fn varfmt(dsid: f64, n: f64) []const u8 {
    const c = col(dsid, n) orelse return "";
    return c.format orelse "";
}

/// VARINFMT(dsid, n): the n-th variable's read informat, or "" if none is attached.
pub fn varinfmt(dsid: f64, n: f64) []const u8 {
    const c = col(dsid, n) orelse return "";
    return c.informat orelse "";
}

/// VARLEN(dsid, n): the n-th variable's storage length — 8 for a numeric, and the
/// widest stored value for a character (the model keeps no declared length).
pub fn varlen(dsid: f64, n: f64) f64 {
    const c = col(dsid, n) orelse return miss;
    if (c.type == .num) return 8;
    if (c.len) |l| return @floatFromInt(l); // declared LENGTH width (BUG-sclmeta)
    const o = entry(dsid).?;
    const ci: usize = @intFromFloat(n);
    var w: usize = 1;
    for (o.ds.rows.items) |row| switch (row[ci - 1]) {
        .str => |s| w = @max(w, s.len),
        .num => {},
    };
    return @floatFromInt(w);
}

/// CEXIST(entry): whether a catalog entry exists. ponytail: no catalog store, so
/// nothing is ever found — a safe conservative answer until catalogs land.
pub fn cexist(spec: []const u8) f64 {
    _ = spec;
    return 0;
}

// ── positional navigation: NOTE marks an observation, POINT returns to it ─────

/// NOTE(dsid): a marker for the current observation (its 1-based number), 0 when
/// none is current. Pass it to POINT to come back here later.
pub fn note(dsid: f64) f64 {
    const o = entry(dsid) orelse return 0;
    return if (o.row == null) 0 else @floatFromInt(o.cur);
}

/// POINT(dsid, marker): position so the NEXT fetch reads the noted observation.
/// 0 on success, -1 if the marker is out of range.
pub fn point(dsid: f64, marker: f64) f64 {
    const o = entry(dsid) orelse return -1;
    const i = idx(marker, o.ds.rows.items.len) orelse return -1;
    o.cur = i; // = n-1; next fetch increments back to n
    o.row = null;
    return 0;
}

/// REWIND(dsid): reposition before the first observation (next fetch reads obs 1).
pub fn rewind(dsid: f64) f64 {
    const o = entry(dsid) orelse return -1;
    o.cur = 0;
    o.row = null;
    return 0;
}

/// DROPNOTE(dsid, marker): release a marker. ponytail: markers are plain
/// observation numbers (nothing is allocated), so this just validates the id.
pub fn dropnote(dsid: f64, marker: f64) f64 {
    _ = marker;
    return if (entry(dsid) == null) -1 else 0;
}

/// DSNAME(dsid): the open data set's two-level name in upper case (the WORK
/// library when the stored name is one-level), or "" for a bad id.
pub fn dsname(dsid: f64) []const u8 {
    const o = entry(dsid) orelse return "";
    const a = arena();
    const up = std.ascii.allocUpperString(a, o.ds.name) catch return "";
    if (std.mem.indexOfScalar(u8, up, '.') != null) return up;
    return std.fmt.allocPrint(a, "WORK.{s}", .{up}) catch "";
}

fn eqi(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

// ── tests ────────────────────────────────────────────────────────────────────

const t = std.testing;

test "BUG-sclbind round-trip: open(work.t)->fetch->getvarn(varnum('x')) == 42" {
    var ga = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer ga.deinit();
    const a = ga.allocator();

    // exactly QA's scenario: a single numeric column x=42, two-level name work.t
    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "t");
    _ = try ds.addColumn("x", .num);
    try ds.appendRow(&.{.{ .num = 42 }});
    try lib.put("t", ds);
    bind(&lib);

    const dsid = open("work.t");
    try t.expect(dsid >= 1); // OPEN resolved (not 0)
    try t.expectEqual(@as(f64, 0), fetch(dsid)); // FETCH the row
    const vn = varnum(dsid, "x");
    try t.expectEqual(@as(f64, 1), vn); // x is variable 1
    const v = getvarn(dsid, vn);
    try t.expect(!std.math.isNan(v)); // NOT missing
    try t.expectEqual(@as(f64, 42), v); // the REAL stored value
    _ = close(dsid);
}

test "SCL positional: NOTE/POINT/REWIND/DROPNOTE + DSNAME (real values)" {
    var ga = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer ga.deinit();
    const a = ga.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "t");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 10, 20, 30 }) |v| try ds.appendRow(&.{.{ .num = v }});
    try lib.put("t", ds);
    bind(&lib);

    const id = open("work.t");
    try t.expect(id >= 1);
    // walk to obs 2, NOTE it, walk on, then POINT back and re-read the SAME value
    try t.expectEqual(@as(f64, 0), fetch(id)); // obs 1
    try t.expectEqual(@as(f64, 10), getvarn(id, 1));
    try t.expectEqual(@as(f64, 0), fetch(id)); // obs 2
    try t.expectEqual(@as(f64, 20), getvarn(id, 1));
    const marker = note(id);
    try t.expectEqual(@as(f64, 2), marker);
    try t.expectEqual(@as(f64, 0), fetch(id)); // obs 3
    try t.expectEqual(@as(f64, 30), getvarn(id, 1));
    // POINT back to the noted observation → next fetch re-reads obs 2 = 20
    try t.expectEqual(@as(f64, 0), point(id, marker));
    try t.expectEqual(@as(f64, 0), fetch(id));
    try t.expectEqual(@as(f64, 2), curobs(id));
    try t.expectEqual(@as(f64, 20), getvarn(id, 1)); // the REAL stored value

    // DROPNOTE releases the marker (no-op success)
    try t.expectEqual(@as(f64, 0), dropnote(id, marker));
    // REWIND → next fetch reads obs 1 again
    try t.expectEqual(@as(f64, 0), rewind(id));
    try t.expectEqual(@as(f64, 0), fetch(id));
    try t.expectEqual(@as(f64, 10), getvarn(id, 1));
    // POINT out of range fails
    try t.expectEqual(@as(f64, -1), point(id, 99));

    // DSNAME → the two-level upper-case name
    try t.expectEqualStrings("WORK.T", dsname(id));
    _ = close(id);
}

test "SCL engine: open/exist/attrn/varnum/fetch/getvar/curobs/fetchobs/close" {
    var ga = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer ga.deinit();
    const a = ga.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("name", .char);
    _ = try ds.addColumn("age", .num);
    try ds.appendRow(&.{ .{ .str = "Alice" }, .{ .num = 30 } });
    try ds.appendRow(&.{ .{ .str = "Bob" }, .{ .num = 25 } });
    try lib.put("have", ds);
    bind(&lib);

    // EXIST before OPEN
    try t.expectEqual(@as(f64, 1), exist("have"));
    try t.expectEqual(@as(f64, 1), exist("work.have"));
    try t.expectEqual(@as(f64, 0), exist("nope"));

    // OPEN → a positive dsid; metadata via ATTRN/ATTRC/VARNUM
    const id = open("work.have");
    try t.expect(id >= 1);
    try t.expectEqual(@as(f64, 2), attrn(id, "NOBS"));
    try t.expectEqual(@as(f64, 2), attrn(id, "NVARS"));
    try t.expectEqualStrings("have", attrc(id, "MEMNAME"));
    try t.expectEqual(@as(f64, 1), varnum(id, "name"));
    try t.expectEqual(@as(f64, 2), varnum(id, "age"));
    try t.expectEqual(@as(f64, 0), varnum(id, "missing"));

    // no row fetched yet → CUROBS 0, GETVAR* empty/missing
    try t.expectEqual(@as(f64, 0), curobs(id));
    try t.expect(std.math.isNan(getvarn(id, 2)));

    // FETCH the first row → read a char and a numeric variable
    try t.expectEqual(@as(f64, 0), fetch(id));
    try t.expectEqual(@as(f64, 1), curobs(id));
    try t.expectEqualStrings("Alice", getvarc(id, 1));
    try t.expectEqual(@as(f64, 30), getvarn(id, 2));

    // FETCH the second row
    try t.expectEqual(@as(f64, 0), fetch(id));
    try t.expectEqual(@as(f64, 2), curobs(id));
    try t.expectEqualStrings("Bob", getvarc(id, 1));
    try t.expectEqual(@as(f64, 25), getvarn(id, 2));

    // past the end → -1, current row cleared
    try t.expectEqual(@as(f64, -1), fetch(id));
    try t.expectEqual(@as(f64, 0), curobs(id));

    // FETCHOBS jumps to a specific observation
    try t.expectEqual(@as(f64, 0), fetchobs(id, 1));
    try t.expectEqualStrings("Alice", getvarc(id, 1));
    try t.expectEqual(@as(f64, -1), fetchobs(id, 9)); // out of range

    // getvarn on a char var (or getvarc on a numeric) yields missing/blank
    _ = fetchobs(id, 1);
    try t.expect(std.math.isNan(getvarn(id, 1))); // 'name' is char
    try t.expectEqualStrings("", getvarc(id, 2)); // 'age' is numeric

    // per-variable metadata: VARNAME / VARLABEL / VARTYPE / VARLEN / VARFMT
    try t.expectEqualStrings("name", varname(id, 1));
    try t.expectEqualStrings("age", varname(id, 2));
    try t.expectEqualStrings("age", varlabel(id, 2)); // no labels → the name
    try t.expectEqualStrings("C", vartype(id, 1));
    try t.expectEqualStrings("N", vartype(id, 2));
    try t.expectEqual(@as(f64, 8), varlen(id, 2)); // numeric → 8
    try t.expectEqual(@as(f64, 5), varlen(id, 1)); // char → widest value "Alice"
    try t.expectEqualStrings("", varfmt(id, 2)); // no format attached
    try t.expectEqualStrings("", varname(id, 9)); // out of range

    // CEXIST: no catalog store → 0
    try t.expectEqual(@as(f64, 0), cexist("work.fmts.myfmt.formatc"));

    // CLOSE retires the id; a closed id no longer resolves
    try t.expectEqual(@as(f64, 0), close(id));
    try t.expect(std.math.isNan(attrn(id, "NOBS"))); // closed → missing
    try t.expectEqual(@as(f64, -1), fetch(id)); // closed → EOF
}

test "GAP-opendisk: OPEN lazy-loads a disk-only member into the dsfns arena, not the Library" {
    var ga = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer ga.deinit();
    const a = ga.allocator();

    var lib = Library.init(a); // EMPTY — the member is never SET/preloaded
    bind(&lib);
    bindLibrefs(&.{.{ .name = "l", .dir = "tests/programs/sas7bdat_read/inputs" }});
    defer bindLibrefs(&.{});

    // upper-case member resolves the lower-case te.sas7bdat (EXIST's case-fallback)
    const id = open("l.TE");
    try t.expect(id >= 1);
    try t.expectEqual(@as(f64, 2), attrn(id, "NOBS"));
    try t.expectEqual(@as(f64, 6), attrn(id, "NVARS"));
    try t.expectEqual(@as(f64, 2), varnum(id, "DOMAIN")); // real column metadata
    // deliberately NOT loaded into the Library: writeLibOutputs must never see it
    try t.expect(lib.find("l.TE") == null and lib.find("te") == null);

    // a second OPEN hands out a fresh dsid but reuses the one cached load
    const id2 = open("l.te");
    try t.expect(id2 >= 1 and id2 != id);
    try t.expectEqual(@as(f64, 2), attrn(id2, "NOBS"));
    _ = close(id);
    _ = close(id2);

    // absent member / unbound libref still 0
    try t.expectEqual(@as(f64, 0), open("l.nope"));
    try t.expectEqual(@as(f64, 0), open("nolib.te"));
}
