//! XPORT v5 (`.xpt`) reader — the openly-documented SAS Transport file format
//! (TS-140). A stream of 80-byte header records framing byte-packed descriptor
//! and observation data:
//!
//!   LIBRARY header  (80) + 2 real header records (160)
//!   MEMBER  header  (80)  — NAMESTR size (140) at offset 74
//!   DSCRPTR header  (80)
//!   member descriptor     (2 records, 160)
//!   NAMESTR header  (80)  — variable count at offset 54
//!   NAMESTR records       (nvars × 140 bytes, contiguous, padded to 80)
//!   OBS     header  (80)
//!   observations          (obs_len bytes each, to the next member header
//!                          or EOF, padded to 80)
//!
//! …and that MEMBER…OBS block may REPEAT — a transport file is a library.
//!
//! A NAMESTR gives each variable's type (1=numeric, 2=char), length, 8-char
//! name, 40-char label, and format/informat (8-char name + width + decimals):
//!   ntype 0 | nlng 4 | nname 8 | nlabel 16 | nform 56, nfl 64, nfd 66 |
//!   niform 72, nifl 80, nifd 82 | npos 84   (TS-140 v5 layout)
//! Char values are ASCII, blank-padded; numeric values are 8-byte IBM
//! System/360 hex floating point. Only the v5 single-member layout is handled
//! (the SDTM `.xpt` files here are one member each).

const std = @import("std");
const Dataset = @import("dataset.zig").Dataset;
const Value = @import("value.zig").Value;
const format = @import("format.zig");
const diag = @import("diag.zig");

const Var = struct {
    name: []const u8,
    is_char: bool,
    len: usize,
    label: []const u8, // trimmed, may be empty
    form: []const u8,
    nfl: u16,
    nfd: u16, // format name / width / decimals
    iform: []const u8,
    nifl: u16,
    nifd: u16, // informat name / width / decimals
};

/// ponytail: NotXport doubles as the writer's loud-refusal tag (a specific
/// ERROR is reported first) — main's write path switches on exactly these two.
pub const Error = error{ NotXport, OutOfMemory };

/// Parse an XPORT v5 file into a Dataset named `name`.
pub fn read(a: std.mem.Allocator, bytes: []const u8, name: []const u8) Error!*Dataset {
    if (bytes.len < 640 or !std.mem.startsWith(u8, bytes, "HEADER RECORD*******LIBRARY"))
        return error.NotXport;
    var p: usize = 240; // LIBRARY header + 2 real header records
    if (!std.mem.startsWith(u8, bytes[p..], "HEADER RECORD*******MEMBER"))
        return error.NotXport;
    const namestr_size = parseNum(bytes[p + 74 .. p + 78]) orelse 140;
    p += 80 + 80 + 160; // MEMBER header, DSCRPTR header, 2 descriptor records
    if (!std.mem.startsWith(u8, bytes[p..], "HEADER RECORD*******NAMESTR"))
        return error.NotXport;
    const nvars = parseNum(bytes[p + 54 .. p + 58]) orelse return error.NotXport;
    p += 80;

    // NAMESTR records — a contiguous stream of `nvars` × `namestr_size` bytes.
    const vars = try a.alloc(Var, nvars);
    var obs_len: usize = 0;
    for (0..nvars) |i| {
        const off = p + i * namestr_size;
        if (off + 16 > bytes.len) return error.NotXport;
        if (off + @max(namestr_size, 88) > bytes.len or namestr_size < 88) return error.NotXport;
        const ns = bytes[off..];
        vars[i] = .{
            .name = trimTrail(ns[8..16]),
            .is_char = be16(ns[0..2]) == 2,
            .len = be16(ns[4..6]),
            .label = trimTrail(ns[16..56]),
            .form = trimTrail(ns[56..64]),
            .nfl = be16(ns[64..66]),
            .nfd = be16(ns[66..68]),
            .iform = trimTrail(ns[72..80]),
            .nifl = be16(ns[80..82]),
            .nifd = be16(ns[82..84]),
        };
        obs_len += vars[i].len;
    }
    p = roundUp(p + nvars * namestr_size, 80); // NAMESTR section padded to 80
    p += 80; // OBS header

    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, name);
    for (vars) |v| {
        _ = try ds.addColumn(v.name, if (v.is_char) .char else .num);
        // restore the metadata the NAMESTR carries (BUG-xportmeta)
        if (v.is_char) ds.setLen(v.name, v.len); // declared char width
        if (v.label.len > 0) ds.setLabel(v.name, try a.dupe(u8, v.label));
        if (try fmtSpec(a, v.form, v.nfl, v.nfd)) |f| ds.setFormat(v.name, f);
        if (try fmtSpec(a, v.iform, v.nifl, v.nifd)) |f| ds.setInformat(v.name, f);
    }
    if (obs_len == 0) return ds;

    // F7(b): the observation section ends at the NEXT member's header. The V5
    // format is a LIBRARY — repeated MEMBER sections are legal — and sections
    // are 80-aligned, so a following member starts with a "HEADER RECORD***…"
    // signature on an 80-byte boundary. Without this bound the walk decoded
    // member 2's headers as garbage observations appended to member 1 (the
    // trailing blank padding is shorter than one obs record, so the all-blank
    // break never fired). Member 1 reads back with exactly its own rows;
    // exposing later members as datasets is not supported (one member per
    // libref file — the same line as the writer).
    var obs_end = bytes.len;
    var b = p;
    while (b + 20 <= bytes.len) : (b += 80) {
        if (std.mem.startsWith(u8, bytes[b..], "HEADER RECORD*******")) {
            obs_end = b;
            break;
        }
    }
    // Observations to the member boundary; the final all-blank record is
    // 80-boundary padding.
    var o = p;
    var broke_blank = false;
    while (o + obs_len <= obs_end) : (o += obs_len) {
        const rec = bytes[o .. o + obs_len];
        if (allBlank(rec)) {
            broke_blank = true;
            break;
        }
        const cells = try a.alloc(Value, nvars);
        var col: usize = 0;
        for (vars, 0..) |v, i| {
            const field = rec[col .. col + v.len];
            cells[i] = if (v.is_char) .{ .str = try a.dupe(u8, trimTrail(field)) } else ibmToValue(field);
            col += v.len;
        }
        try ds.rows.append(a, cells);
    }
    // GAP-xportio-low F13: a non-blank tail after the last full observation
    // is a TRUNCATED/damaged file — v5 carries no observation count, so a cut
    // landing exactly on a record boundary is format-undetectable, but a
    // partial trailing record is real damage. Fail LOUD (the libname load
    // path renders NotXport as "damaged or truncated", NOTE-truncreadmsg)
    // instead of silently returning the surviving rows. Basis: HOUSE RULE —
    // TS-140 is silent on truncation. The all-blank break stays unchecked:
    // an all-zero-numeric observation is all-zero bytes, genuinely ambiguous
    // with padding in v5 (ponytail ceiling, pre-existing).
    if (!broke_blank and o < obs_end and !allBlank(bytes[o..obs_end]))
        return error.NotXport;
    return ds;
}

/// Serialize a Dataset to XPORT v5 bytes — the inverse of `read`, byte-compatible
/// with it (and with SAS PROC CIMPORT / the FDA submission format). A char var's
/// NAMESTR length is its DECLARED length (Column.len from a LENGTH statement);
/// with no declaration the widest value stands in (min 1, BUG-xportmeta). Label,
/// format and informat ride the NAMESTR too. Numerics are 8-byte IBM floats.
/// ponytail: fixed timestamp in the header records (the reader ignores it; no
/// clock on this path).
pub fn write(a: std.mem.Allocator, ds: *const Dataset) Error![]const u8 {
    return writeReport(a, ds, null);
}

/// `write` + a diagnostics sink for the writer's loud paths
/// (BUG-xportwritefidelity): truncation WARNINGs, the out-of-range NOTE and
/// the refusal ERRORs land in `diags` (tests capture the reporter); with null
/// they print to stderr, SAS-log style. A REFUSED write (name collision, char
/// length > 32767) reports the ERROR and returns NotXport — no partial file.
pub fn writeReport(a: std.mem.Allocator, ds: *const Dataset, diags: ?*diag.Diagnostics) Error![]const u8 {
    const nvars = ds.columns.items.len;
    // per-var length + position; numerics 8, chars = declared length (≥ data max)
    const lens = try a.alloc(usize, nvars);
    var obs_len: usize = 0;
    for (ds.columns.items, 0..) |c, i| {
        if (c.type == .num) {
            lens[i] = 8;
        } else {
            var mx: usize = 1;
            for (ds.rows.items) |row| if (row[i] == .str) {
                mx = @max(mx, trimTrail(row[i].str).len);
            };
            // declared char LENGTH wins (BUG-xportmeta); the data max can only
            // ever WIDEN it — a value wider than declared must not truncate.
            lens[i] = @max(c.len orelse 0, mx);
            // F5: nlng is a u16 NAMESTR field and SAS caps char vars at 32767 —
            // refuse LOUDLY instead of @intCast-panicking the process.
            if (lens[i] > 32767) {
                loud(diags, .err, "XPORT: variable '{s}' has length {d}, over the V5 transport maximum character length 32767", .{ c.name, lens[i] });
                return error.NotXport;
            }
        }
        obs_len += lens[i];
        // F3: names >8 truncate to the 8-char NAMESTR field — warn per
        // truncation, and REFUSE when two variables collapse to the same field
        // (the file would silently merge them; one var's data would vanish).
        // ponytail: O(n²) pair scan — nvars is a 4-digit field, tiny.
        if (c.name.len > 8)
            loud(diags, .warning, "XPORT: variable name '{s}' truncated to 8 characters ('{s}')", .{ c.name, c.name[0..8] });
        for (ds.columns.items[0..i]) |p| {
            if (std.ascii.eqlIgnoreCase(p.name[0..@min(8, p.name.len)], c.name[0..@min(8, c.name.len)])) {
                loud(diags, .err, "XPORT: variables '{s}' and '{s}' share the 8-character NAMESTR name '{s}' — refusing to write a file that would merge them", .{ p.name, c.name, c.name[0..@min(8, c.name.len)] });
                return error.NotXport;
            }
        }
    }

    var buf: std.ArrayList(u8) = .empty;
    const dt = "01JAN60:00:00:00"; // 16-char SAS datetime placeholder

    // LIBRARY header + 2 real header records (SAS/version/OS + timestamps)
    try rec80(a, &buf, "HEADER RECORD*******LIBRARY HEADER RECORD!!!!!!!000000000000000000000000000000  ");
    try rec80(a, &buf, "SAS     SAS     SASLIB  9.4     openSAS                          " ++ dt);
    try rec80(a, &buf, dt ++ (" " ** 64));

    // MEMBER header (NAMESTR size 0140 at offset 74) + DSCRPTR header + descriptor
    try rec80(a, &buf, "HEADER RECORD*******MEMBER  HEADER RECORD!!!!!!!000000000000000001600000000140  ");
    try rec80(a, &buf, "HEADER RECORD*******DSCRPTR HEADER RECORD!!!!!!!000000000000000000000000000000  ");
    var mem: [8]u8 = "        ".*; // member name, ≤8, blank-padded (case preserved)
    @memcpy(mem[0..@min(8, ds.name.len)], ds.name[0..@min(8, ds.name.len)]);
    if (ds.name.len > 8) // F3: same loud truncation pattern as variable names
        loud(diags, .warning, "XPORT: member name '{s}' truncated to 8 characters ('{s}')", .{ ds.name, mem[0..] });
    try rec80(a, &buf, try std.fmt.allocPrint(a, "SAS     {s}SASDATA 9.4     openSAS                          {s}", .{ mem, dt }));
    try rec80(a, &buf, dt ++ (" " ** 64));

    // NAMESTR header — 4-digit variable count at offset 54
    try rec80(a, &buf, try std.fmt.allocPrint(a, "HEADER RECORD*******NAMESTR HEADER RECORD!!!!!!!000000{d:0>4}00000000000000000000  ", .{nvars}));

    // NAMESTR records: 140 bytes each (type, length, name, label, format,
    // informat, position — the TS-140 offsets in the file-top comment)
    const namestr_start = buf.items.len;
    var pos: usize = 0;
    for (ds.columns.items, 0..) |c, i| {
        var ns = [_]u8{0} ** 140;
        // GAP-xportio-low F12: TS-140's text fields are blank-padded ASCII —
        // a REAL SAS 9.1 NAMESTR (tests/programs/xport_read/inputs/te.xpt,
        // XP_PRO) blank-pads nlabel/nform/niform even when unset; only the
        // 88..140 tail is NUL. We NUL-padded all three — readable here, but
        // strict validators (Pinnacle 21, the actual submission gate) can
        // flag NUL text fields. Seed the three text fields to blanks; the
        // value writes below overwrite them.
        @memset(ns[16..56], ' '); // nlabel
        @memset(ns[56..64], ' '); // nform
        @memset(ns[72..80], ' '); // niform
        putBe16(ns[0..2], if (c.type == .num) 1 else 2); // ntype
        putBe16(ns[4..6], @intCast(lens[i])); // nlng
        putBe16(ns[6..8], @intCast(i + 1)); // nvar0 (1-based)
        var nm: [8]u8 = "        ".*; // ≤8, blank-padded (case preserved)
        @memcpy(nm[0..@min(8, c.name.len)], c.name[0..@min(8, c.name.len)]);
        @memcpy(ns[8..16], &nm);
        if (c.label) |l| { // nlabel: ≤40, blank-padded (v5 truncates longer)
            @memcpy(ns[16 .. 16 + @min(40, l.len)], l[0..@min(40, l.len)]);
            // GAP-xportio-low F11: a >40 label truncates — format-forced (the
            // v5 nlabel field IS 40; SAS labels run to 256) — but never
            // silently: same loud WARNING pattern as F3 names. House rule:
            // TS-140 does not say whether CPORT warns, and silent alteration
            // is the worst failure class.
            if (l.len > 40)
                loud(diags, .warning, "XPORT: label of variable '{s}' truncated to 40 characters", .{c.name});
        }
        if (c.format) |f| {
            if (putFmt(ns[56..64], ns[64..66], ns[66..68], f))
                loud(diags, .warning, "XPORT: format name in '{s}' truncated to 8 characters", .{f});
        }
        if (c.informat) |inf| {
            if (putFmt(ns[72..80], ns[80..82], ns[82..84], inf))
                loud(diags, .warning, "XPORT: informat name in '{s}' truncated to 8 characters", .{inf});
        }
        putBe32(ns[84..88], @intCast(pos)); // npos
        try buf.appendSlice(a, &ns);
        pos += lens[i];
    }
    // pad the NAMESTR section to an 80-byte boundary
    for (0..roundUp(buf.items.len, 80) - buf.items.len) |_| try buf.append(a, ' ');
    _ = namestr_start;

    // OBS header + the observations (char blank-padded, numeric IBM float)
    try rec80(a, &buf, "HEADER RECORD*******OBS     HEADER RECORD!!!!!!!000000000000000000000000000000  ");
    var out_of_range: usize = 0; // F2: values the S/360 exponent can't hold
    for (ds.rows.items) |row| {
        for (ds.columns.items, 0..) |c, i| {
            if (c.type == .num) {
                var f: [8]u8 = undefined;
                if (valueToIbm(&f, row[i])) out_of_range += 1;
                try buf.appendSlice(a, &f);
            } else {
                const s = if (row[i] == .str) trimTrail(row[i].str) else "";
                const n = @min(s.len, lens[i]);
                try buf.appendSlice(a, s[0..n]);
                for (0..lens[i] - n) |_| try buf.append(a, ' '); // blank-pad to length
            }
        }
    }
    // F2: ONE note per file, not one per cell — the values rode out as plain
    // missing, never exponent-wrapped to the opposite extreme.
    if (out_of_range > 0)
        loud(diags, .note, "XPORT: {d} numeric value(s) outside the IBM S/360 float range were written as missing", .{out_of_range});
    // pad the observation section to an 80-byte boundary with blanks
    if (obs_len > 0) for (0..roundUp(buf.items.len, 80) - buf.items.len) |_| try buf.append(a, ' ');
    return buf.items;
}

/// Append `s` as an exactly-80-byte record (truncated or blank-padded).
fn rec80(a: std.mem.Allocator, buf: *std.ArrayList(u8), s: []const u8) Error!void {
    const n = @min(s.len, 80);
    try buf.appendSlice(a, s[0..n]);
    for (0..80 - n) |_| try buf.append(a, ' ');
}

fn putBe16(b: []u8, v: u16) void {
    b[0] = @truncate(v >> 8);
    b[1] = @truncate(v);
}

/// Split an opensas format spec ("DOLLAR10.2", "$3.") into the NAMESTR triple:
/// 8-byte blank-padded name (char formats keep their `$`), width, decimals.
/// Names >8 chars truncate — the v5 field's own limit; returns true then so the
/// caller can WARN (F3).
fn putFmt(name_f: []u8, w_f: []u8, d_f: []u8, spec_text: []const u8) bool {
    const s = format.parseSpec(spec_text);
    @memset(name_f, ' ');
    var off: usize = 0;
    if (s.is_char and name_f.len > 0) {
        name_f[0] = '$';
        off = 1;
    }
    const n = @min(s.name.len, name_f.len - off);
    @memcpy(name_f[off .. off + n], s.name[0..n]);
    putBe16(w_f, @intCast(@min(s.w, 65535)));
    putBe16(d_f, @intCast(@min(s.d, 65535)));
    return s.name.len > n;
}

/// NAMESTR format triple → opensas spec text ("DOLLAR10.2", "$3.", "8.2"),
/// or null when no format is attached (blank name and zero width).
fn fmtSpec(a: std.mem.Allocator, name: []const u8, w: u16, d: u16) Error!?[]const u8 {
    if (name.len == 0 and w == 0) return null;
    if (d > 0) return try std.fmt.allocPrint(a, "{s}{d}.{d}", .{ name, w, d });
    if (w > 0) return try std.fmt.allocPrint(a, "{s}{d}.", .{ name, w });
    return try std.fmt.allocPrint(a, "{s}.", .{name});
}

fn putBe32(b: []u8, v: u32) void {
    b[0] = @truncate(v >> 24);
    b[1] = @truncate(v >> 16);
    b[2] = @truncate(v >> 8);
    b[3] = @truncate(v);
}

/// One loud diagnostic from the writer: into `diags` when a reporter is
/// threaded (tests capture it — never spawn an aborting process in a test),
/// else to stderr SAS-log style (main renders its own diags there too, and the
/// corpus diffs stdout only). Never silent.
fn loud(diags: ?*diag.Diagnostics, sev: diag.Severity, comptime fmt: []const u8, args: anytype) void {
    if (diags) |d| {
        d.report(sev, 0, fmt, args) catch {};
    } else {
        std.debug.print("{s}: " ++ fmt ++ "\n", .{sev.tag()} ++ args);
    }
}

/// f64 → 8-byte IBM System/360 hex float (the inverse of `ibmToValue`). A missing
/// value writes its TS-140 indicator in byte 0 with a zero mantissa — `.` for a
/// plain missing, the `_`/`A`–`Z` letter of a special missing (F1; the reader
/// already decodes these). 0 is all-zero bytes. Returns true when `v` falls
/// outside the S/360 range (biased exponent 0..127) — byte 0 is then `.`
/// (missing) and the caller logs ONE note per file (F2): masking the exponent
/// would silently wrap 1e300 into 5.5e-9 baked into the file.
fn valueToIbm(out: *[8]u8, v: Value) bool {
    @memset(out, 0);
    const x = switch (v) {
        .num => |n| n,
        .str => return false, // char field never routed here
    };
    if (std.math.isNan(x)) {
        const c = Value.missingChar(x); // '.' plain, 'A'–'Z'/'_' special
        out[0] = if (c == '_' or (c >= 'A' and c <= 'Z')) c else '.';
        return false;
    }
    if (x == 0) return false; // all-zero bytes
    if (!std.math.isFinite(x)) { // ±Inf — outside the S/360 range (F2)
        out[0] = '.';
        return true;
    }
    var ax = @abs(x);
    var e: i32 = 0; // value = frac · 16^e, frac ∈ [1/16, 1)
    while (ax >= 1.0) : (e += 1) ax /= 16.0;
    while (ax < 1.0 / 16.0) : (e -= 1) ax *= 16.0;
    var mant: u64 = @intFromFloat(@round(ax * 72057594037927936.0)); // 2^56
    if (mant >> 56 != 0) { // rounded up to 1.0 → carry into the exponent
        mant >>= 4;
        e += 1;
    }
    const biased = e + 64;
    if (biased < 0 or biased > 127) { // F2: guard BEFORE the field write — never mask
        out[0] = '.';
        return true;
    }
    const exp_field: u8 = @intCast(biased);
    out[0] = exp_field | (if (x < 0) @as(u8, 0x80) else 0);
    var i: usize = 7;
    while (i >= 1) : (i -= 1) {
        out[i] = @truncate(mant);
        mant >>= 8;
    }
    return false;
}

fn be16(b: []const u8) u16 {
    return (@as(u16, b[0]) << 8) | b[1];
}

fn parseNum(s: []const u8) ?usize {
    return std.fmt.parseInt(usize, std.mem.trim(u8, s, " "), 10) catch null;
}

fn trimTrail(s: []const u8) []const u8 {
    return std.mem.trimEnd(u8, s, " \x00");
}

fn roundUp(n: usize, m: usize) usize {
    return (n + m - 1) / m * m;
}

fn allBlank(rec: []const u8) bool {
    for (rec) |c| if (c != ' ' and c != 0) return false;
    return true;
}

/// IBM System/360 hex float (8 bytes, big-endian) → f64: sign · mantissa/2^56 ·
/// 16^(exp−64). A missing indicator (`.`/`_`/`A`-`Z`) in byte 0 with a zero
/// mantissa is a SAS missing; all-zero bytes are 0.
fn ibmToValue(f: []const u8) Value {
    var rest_zero = true;
    for (f[1..8]) |b| {
        if (b != 0) rest_zero = false;
    }
    if (rest_zero) {
        if (f[0] == '.') return Value.missing;
        if (f[0] == '_' or (f[0] >= 'A' and f[0] <= 'Z')) return Value.specialMissing(f[0]);
        if (f[0] == 0) return .{ .num = 0 };
    }
    const sign: f64 = if (f[0] & 0x80 != 0) -1 else 1;
    const exp: i32 = @as(i32, @intCast(f[0] & 0x7f)) - 64;
    var mant: u64 = 0;
    for (f[1..8]) |b| mant = (mant << 8) | b;
    const frac = @as(f64, @floatFromInt(mant)) / 72057594037927936.0; // 2^56
    return .{ .num = sign * frac * std.math.pow(f64, 16, @as(f64, @floatFromInt(exp))) };
}

test "XPORT write → read round-trips columns, char/numeric values, and missing" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var ds = Dataset.init(a, "x");
    _ = try ds.addColumn("id", .num);
    _ = try ds.addColumn("name", .char);
    _ = try ds.addColumn("val", .num);
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .str = "Alice" }, .{ .num = 3.5 } });
    try ds.appendRow(&.{ .{ .num = 2 }, .{ .str = "Bob" }, .{ .num = -0.25 } });
    try ds.appendRow(&.{ .{ .num = 3 }, .{ .str = "Cy" }, Value.missing });

    const bytes = try write(a, &ds);
    try t.expect(bytes.len % 80 == 0); // every section is 80-aligned
    const back = try read(a, bytes, "x2");

    try t.expectEqual(@as(usize, 3), back.columns.items.len);
    try t.expectEqualStrings("id", back.columns.items[0].name);
    try t.expectEqualStrings("name", back.columns.items[1].name);
    try t.expectEqualStrings("val", back.columns.items[2].name);
    try t.expect(back.columns.items[0].type == .num and back.columns.items[1].type == .char);
    try t.expectEqual(@as(usize, 3), back.rows.items.len);
    try t.expectEqual(@as(f64, 1), back.rows.items[0][0].num);
    try t.expectEqualStrings("Alice", back.rows.items[0][1].str);
    try t.expectEqual(@as(f64, 3.5), back.rows.items[0][2].num);
    try t.expectEqual(@as(f64, -0.25), back.rows.items[1][2].num);
    try t.expectEqualStrings("Cy", back.rows.items[2][1].str);
    try t.expect(back.rows.items[2][2].isMissing()); // numeric missing round-trips
}

test "XPORT round-trip keeps label/format/informat/declared char length (BUG-xportmeta)" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var ds = Dataset.init(a, "m");
    _ = try ds.addColumn("name", .char);
    _ = try ds.addColumn("grp", .char);
    _ = try ds.addColumn("wt", .num);
    ds.setLen("name", 20); // declared $20, data only needs 5
    ds.setLen("grp", 3);
    ds.setLabel("name", "Full Name");
    ds.setLabel("wt", "Weight (kg)");
    ds.setInformat("name", "$20.");
    ds.setFormat("wt", "8.2");
    try ds.appendRow(&.{ .{ .str = "Alice" }, .{ .str = "A" }, .{ .num = 45.5 } });

    const back = try read(a, try write(a, &ds), "m2");
    const cols = back.columns.items;
    try t.expectEqual(@as(?usize, 20), cols[0].len); // declared, not the data max 5
    try t.expectEqual(@as(?usize, 3), cols[1].len);
    try t.expectEqualStrings("Full Name", cols[0].label.?);
    try t.expectEqualStrings("Weight (kg)", cols[2].label.?);
    try t.expectEqualStrings("$20.", cols[0].informat.?);
    try t.expectEqualStrings("8.2", cols[2].format.?);
    try t.expect(cols[1].format == null and cols[1].label == null); // unset stays unset
    try t.expectEqualStrings("Alice", back.rows.items[0][0].str); // data still right
    try t.expectEqual(@as(f64, 45.5), back.rows.items[0][2].num);
}

test "XPORT write keeps special missings .A–.Z/._ on WRITE (BUG-xportwritefidelity F1)" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    try ds.appendRow(&.{Value.specialMissing('A')});
    try ds.appendRow(&.{Value.specialMissing('_')});
    try ds.appendRow(&.{Value.specialMissing('Z')});
    try ds.appendRow(&.{Value.missing});

    var diags = diag.Diagnostics.init(a);
    const back = try read(a, try writeReport(a, &ds, &diags), "d2");
    try t.expectEqual(@as(usize, 0), diags.count()); // clean write, nothing loud
    try t.expectEqual(@as(u8, 'A'), Value.missingChar(back.rows.items[0][0].num));
    try t.expectEqual(@as(u8, '_'), Value.missingChar(back.rows.items[1][0].num));
    try t.expectEqual(@as(u8, 'Z'), Value.missingChar(back.rows.items[2][0].num));
    try t.expectEqual(@as(u8, '.'), Value.missingChar(back.rows.items[3][0].num)); // plain stays plain
}

test "XPORT write: in-range IBM floats stay exact, out-of-range NOTE + missing (F2)" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // in-range precision LOCK (tick220-verified, must not regress): write →
    // read is bit-exact across the whole S/360 exponent range
    const keep = [_]f64{ 0.1, 1.0 / 3.0, 9007199254740991.0, 1e70, 5.4e-79, 7e75, -0.1, -7e75 };
    for (keep) |x| {
        var f: [8]u8 = undefined;
        try t.expect(!valueToIbm(&f, .{ .num = x }));
        try t.expectEqual(@as(u64, @bitCast(x)), @as(u64, @bitCast(ibmToValue(&f).num)));
    }
    // known encode vectors (the exact inverse of the ibmToValue decode test)
    var f: [8]u8 = undefined;
    try t.expect(!valueToIbm(&f, .{ .num = 1 }));
    try t.expectEqual([8]u8{ 0x41, 0x10, 0, 0, 0, 0, 0, 0 }, f);
    try t.expect(!valueToIbm(&f, .{ .num = 0.5 }));
    try t.expectEqual([8]u8{ 0x40, 0x80, 0, 0, 0, 0, 0, 0 }, f);

    // out-of-range: flagged, written as plain missing — never exponent-wrapped
    for ([_]f64{ 1e300, -1e300, 1e-300, std.math.inf(f64), -std.math.inf(f64) }) |x| {
        try t.expect(valueToIbm(&f, .{ .num = x }));
        try t.expectEqual([8]u8{ '.', 0, 0, 0, 0, 0, 0, 0 }, f);
    }

    // end-to-end: 1e300 in a file → ONE NOTE, read-back missing (not 5.5e-9)
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    try ds.appendRow(&.{.{ .num = 1e300 }});
    try ds.appendRow(&.{.{ .num = 2.5 }});
    var diags = diag.Diagnostics.init(a);
    const back = try read(a, try writeReport(a, &ds, &diags), "d2");
    try t.expectEqual(@as(usize, 1), diags.count());
    try t.expect(diags.list.items[0].severity == .note);
    try t.expect(std.mem.indexOf(u8, diags.list.items[0].message, "outside the IBM S/360 float range") != null);
    try t.expect(back.rows.items[0][0].isMissing());
    try t.expectEqual(@as(f64, 2.5), back.rows.items[1][0].num); // in-range neighbor unharmed
}

test "XPORT write: 8-char name truncation warns, collision refuses (F3)" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // collision: longname01/longname02 → both NAMESTR 'longname' → loud ERROR,
    // NO file (a duplicate-name file would silently merge the two vars)
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("longname01", .num);
    _ = try ds.addColumn("longname02", .num);
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 2 } });
    var diags = diag.Diagnostics.init(a);
    try t.expectError(error.NotXport, writeReport(a, &ds, &diags));
    try t.expect(diags.hasErrors());
    try t.expect(std.mem.indexOf(u8, diags.list.items[diags.count() - 1].message, "merge") != null);

    // truncation alone: WARNING, the write still succeeds — no merge
    var ds2 = Dataset.init(a, "d");
    _ = try ds2.addColumn("longname01", .num);
    _ = try ds2.addColumn("ok", .num);
    try ds2.appendRow(&.{ .{ .num = 1 }, .{ .num = 2 } });
    var diags2 = diag.Diagnostics.init(a);
    const back = try read(a, try writeReport(a, &ds2, &diags2), "d2");
    try t.expectEqual(@as(usize, 1), diags2.count());
    try t.expect(diags2.list.items[0].severity == .warning);
    try t.expect(std.mem.indexOf(u8, diags2.list.items[0].message, "truncated") != null);
    try t.expectEqual(@as(usize, 2), back.columns.items.len);
    try t.expectEqual(@as(f64, 1), back.rows.items[0][0].num);
}

test "XPORT write: member and format names > 8 chars warn (F3)" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var ds = Dataset.init(a, "verylongmember");
    _ = try ds.addColumn("x", .num);
    ds.setFormat("x", "MYSUPERLONGFMT8.");
    try ds.appendRow(&.{.{ .num = 1 }});
    var diags = diag.Diagnostics.init(a);
    _ = try writeReport(a, &ds, &diags);
    try t.expectEqual(@as(usize, 2), diags.count()); // member + format
    try t.expect(diags.list.items[0].severity == .warning);
    try t.expect(diags.list.items[1].severity == .warning);
}

test "XPORT write: char length > 32767 refuses loudly, never panics (F5)" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("big", .char);
    ds.setLen("big", 70000); // over the SAS 32767 char cap — was an @intCast panic
    try ds.appendRow(&.{.{ .str = "x" }});
    var diags = diag.Diagnostics.init(a);
    try t.expectError(error.NotXport, writeReport(a, &ds, &diags));
    try t.expect(diags.hasErrors());
    try t.expect(std.mem.indexOf(u8, diags.list.items[0].message, "32767") != null);
}

test "XPORT read stops at the member boundary — member 1 exact, no garbage rows (F7)" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // A multi-member stream: two single-member files concatenated (`cat a b`),
    // the doc-finder's repro. Member 1 = 100 rows; member 2's headers must NOT
    // decode as extra observations (they appended 9 garbage rows before).
    var m1 = Dataset.init(a, "big");
    _ = try m1.addColumn("i", .num);
    _ = try m1.addColumn("v", .num);
    for (1..101) |i| try m1.appendRow(&.{ .{ .num = @floatFromInt(i) }, .{ .num = @floatFromInt(i * 10) } });
    var m2 = Dataset.init(a, "two");
    _ = try m2.addColumn("w", .num);
    try m2.appendRow(&.{.{ .num = 99 }});
    const cat = try std.fmt.allocPrint(a, "{s}{s}", .{ try write(a, &m1), try write(a, &m2) });

    const back = try read(a, cat, "big");
    try t.expectEqual(@as(usize, 100), back.rows.items.len); // exactly member 1
    try t.expectEqual(@as(f64, 1), back.rows.items[0][0].num);
    try t.expectEqual(@as(f64, 1000), back.rows.items[99][1].num);

    // a 1-row member 1: its trailing pad is shorter than one obs record, so
    // the boundary scan (not the all-blank break) is what stops the walk
    var m3 = Dataset.init(a, "one");
    _ = try m3.addColumn("x", .num);
    try m3.appendRow(&.{.{ .num = 7 }});
    const cat2 = try std.fmt.allocPrint(a, "{s}{s}", .{ try write(a, &m3), try write(a, &m2) });
    const back2 = try read(a, cat2, "one");
    try t.expectEqual(@as(usize, 1), back2.rows.items.len);
    try t.expectEqual(@as(f64, 7), back2.rows.items[0][0].num);
}

test "XPORT read: a truncated file's partial trailing record is LOUD, never partial rows (GAP-xportio-low F13)" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // 100 rows × 2 numerics → obs_len 16, 1600 bytes (80-aligned, no padding).
    // The bytes are our own writer's — truncating VALID bytes cannot mirror a
    // writer bug; the assertion is purely about the reader refusing a cut.
    var ds = Dataset.init(a, "big");
    _ = try ds.addColumn("i", .num);
    _ = try ds.addColumn("v", .num);
    for (1..101) |k| try ds.appendRow(&.{ .{ .num = @floatFromInt(k) }, .{ .num = @floatFromInt(k * 10) } });
    const bytes = try write(a, &ds);
    const obs_start = bytes.len - 1600;

    // cut 5 bytes INTO the 100th observation (its IBM-float bytes are
    // non-blank): the whole READ fails — the surviving 99 rows are never
    // silently returned as if complete (the audit's repro: 100 rows cut to
    // 2/3 → 45 rows, exit 0).
    try t.expectError(error.NotXport, read(a, bytes[0 .. obs_start + 99 * 16 + 5], "big"));

    // a cut exactly on a record boundary is format-undetectable (v5 has no
    // observation count) — pinned as the known ceiling, not a feature
    const back = try read(a, bytes[0 .. obs_start + 99 * 16], "big");
    try t.expectEqual(@as(usize, 99), back.rows.items.len);

    // and the whole file still reads whole (control)
    try t.expectEqual(@as(usize, 100), (try read(a, bytes, "big")).rows.items.len);
}

test "XPORT write: unset NAMESTR text fields are blank-padded like a real SAS NAMESTR (GAP-xportio-low F12)" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Byte basis: tests/programs/xport_read/inputs/te.xpt — a REAL SAS 9.1
    // (XP_PRO) transport file, not our own writer's output: unset
    // nlabel/nform/niform are BLANK-padded, only the 88..140 tail is NUL.
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num); // no label, no format, no informat
    try ds.appendRow(&.{.{ .num = 1 }});
    const bytes = try write(a, &ds);
    const ns = bytes[640 .. 640 + 140]; // first NAMESTR (the offset read() uses)
    try t.expectEqualStrings("x       ", ns[8..16]); // name, blank-padded
    for (ns[16..56]) |b| try t.expectEqual(@as(u8, ' '), b); // nlabel blanks
    for (ns[56..64]) |b| try t.expectEqual(@as(u8, ' '), b); // nform blanks
    for (ns[72..80]) |b| try t.expectEqual(@as(u8, ' '), b); // niform blanks
    for (ns[88..140]) |b| try t.expectEqual(@as(u8, 0), b); // tail stays NUL
    // …and it still READS back clean (our reader tolerates either pad)
    const back = try read(a, bytes, "d2");
    try t.expect(back.columns.items[0].label == null and back.columns.items[0].format == null);
}

test "XPORT write: label > 40 chars warns and truncates at exactly 40 (GAP-xportio-low F11)" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    ds.setLabel("x", "A label that is definitely longer than forty characters total"); // 61
    try ds.appendRow(&.{.{ .num = 1 }});
    var diags = diag.Diagnostics.init(a);
    const back = try read(a, try writeReport(a, &ds, &diags), "d2");
    try t.expectEqual(@as(usize, 1), diags.count()); // loud, never silent
    try t.expect(diags.list.items[0].severity == .warning);
    try t.expect(std.mem.indexOf(u8, diags.list.items[0].message, "truncated to 40") != null);
    try t.expectEqual(@as(usize, 40), back.columns.items[0].label.?.len); // at the field
    try t.expectEqualStrings("A label that is definitely longer than f", back.columns.items[0].label.?);

    // a 40-char label is exactly at the field: no warning, kept whole
    var ds2 = Dataset.init(a, "d");
    _ = try ds2.addColumn("x", .num);
    ds2.setLabel("x", "A label that is definitely longer than f"); // 40
    try ds2.appendRow(&.{.{ .num = 1 }});
    var diags2 = diag.Diagnostics.init(a);
    const back2 = try read(a, try writeReport(a, &ds2, &diags2), "d2");
    try t.expectEqual(@as(usize, 0), diags2.count());
    try t.expectEqualStrings("A label that is definitely longer than f", back2.columns.items[0].label.?);
}

test "IBM hex float decode: known values and missings" {
    const t = std.testing;
    try t.expectEqual(@as(f64, 1), ibmToValue(&.{ 0x41, 0x10, 0, 0, 0, 0, 0, 0 }).num);
    try t.expectEqual(@as(f64, 2), ibmToValue(&.{ 0x41, 0x20, 0, 0, 0, 0, 0, 0 }).num);
    try t.expectEqual(@as(f64, -1), ibmToValue(&.{ 0xC1, 0x10, 0, 0, 0, 0, 0, 0 }).num);
    try t.expectEqual(@as(f64, 0), ibmToValue(&.{ 0, 0, 0, 0, 0, 0, 0, 0 }).num);
    try t.expect(ibmToValue(&.{ '.', 0, 0, 0, 0, 0, 0, 0 }).isMissing());
    // 0.5 = 8 · 16^-1 → 0x40 0x80 …
    try t.expectEqual(@as(f64, 0.5), ibmToValue(&.{ 0x40, 0x80, 0, 0, 0, 0, 0, 0 }).num);
}
