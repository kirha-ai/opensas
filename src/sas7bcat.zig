//! sas7bcat (`.sas7bcat`) reader — the native SAS *format catalog*: the user
//! VALUE-format DEFINITIONS a program installs via `libname` + `OPTIONS
//! FMTSEARCH=`, so `put(x, YESNO.)` decodes to a label instead of failing loud
//! (GH#34). Same undocumented container family as sas7bdat (magic, header,
//! pages), so this reuses that header/32-bit-LE approach and diverges only in
//! the payload — a chain of value-label BLOCKS indexed by XLSR pointers. Ported
//! from readstat's readstat_sas7bcat_read.c (WizardMac/ReadStat, MIT License,
//! Copyright (c) 2013-2016 Evan Miller); every parsed
//! (name → {value:label}) is verified byte-exact against pyreadstat's
//! read_sas7bcat oracle for testdata/formats.sas7bcat (see the test below).
//!
//! Layout, top-down:
//!   header — shares sas7bdat's magic (one byte differs: +15 is 0x63 not 0x60),
//!     endianness/word-size flags, header_size/page_size/page_count.
//!   index — page index 1 carries XLSR records (one per format) at offset
//!     856+2·pad1; each XLSR whose byte[50+pad1]=='O' points (page,pos) at a block.
//!   block — a chain of segments across pages: a 16-byte link header
//!     (next_page@0, next_pos@4, seg_len@6) then seg_len payload bytes,
//!     concatenated until next_page/pos are 0.
//!   payload — at +8 the 8-char short NAME (`$`-prefixed ⇒ char keys); label
//!     count at +42(+pad); then `count` VALUE entries followed by `count` LABEL
//!     entries, cross-linked by a label-index u32 inside each value entry.
//!
//! Scope (ponytail: what real CDISC catalogs need): 32-bit, little-endian VALUE
//! formats only.
//!   - u64 (byte-32 == 0x33) / big-endian → error.Unsupported (mirrors sas7bdat.zig).
//!   - SAS "special missing" numeric keys (.A–.Z / ._ / plain .) decode to the
//!     matching missing Value — the stored double is the sas7bdat on-disk NaN
//!     (0xFFFF<~ascii>00…) bitwise-NOTed, so BE byte 2 is the ASCII letter
//!     itself; format.zig matches a missing value against such a key bit-exactly
//!     (NOTE-sas7bcatspecialmiss — was silently DROPPED, wrong label for .A–.Z).
//!   - PICTURE/INFORMAT/JUST entries carry no value-label payload here, so they
//!     simply contribute no entries — never mis-decoded.

const std = @import("std");
const format = @import("format.zig");
const Value = @import("value.zig").Value;

pub const Error = error{ NotSas7bcat, Unsupported, OutOfMemory };

// sas7bdat magic with byte 15 flipped 0x60 → 0x63 (the catalog marker).
const magic = [_]u8{
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0xc2, 0xea, 0x81, 0x63, 0xb3, 0x14, 0x11, 0xcf, 0xbd, 0x92, 0x08, 0x00,
    0x09, 0xc7, 0x31, 0x8c, 0x18, 0x1f, 0x10, 0x11,
};

/// Parse a `.sas7bcat` catalog into the same `[]format.UserFmt` PROC FORMAT
/// produces, ready to hand to `format.setUserFormats`. Fails loud (error) on an
/// unsupported layout rather than returning half a catalog.
pub fn read(a: std.mem.Allocator, bytes: []const u8) Error![]const format.UserFmt {
    if (bytes.len < 288 or !std.mem.eql(u8, bytes[0..32], &magic)) return error.NotSas7bcat;
    if (bytes[32] == 0x33) return error.Unsupported; // u64 (64-bit) catalog
    if (bytes[37] != 0x01) return error.Unsupported; // big-endian
    const pad1: usize = if (bytes[35] == 0x33) 4 else 0;

    const header_size = rd32(bytes, 196 + pad1);
    const page_size = rd32(bytes, 200 + pad1);
    const page_count = rd32(bytes, 204 + pad1);
    if (page_size == 0 or header_size == 0) return error.NotSas7bcat;

    const xlsr_size: usize = 212 + pad1;
    const xlsr_offset: usize = 856 + 2 * pad1;
    const xlsr_o_off: usize = 50 + pad1;

    // Collect block pointers ((page<<32)|pos) from the XLSR index. The index
    // lives on page 1; later pages (from index 3) may hold more (marked "XLSR"
    // at +16) — the corpus catalog fits page 1, but the sweep is cheap.
    var bptrs: std.ArrayList(u64) = .empty;
    defer bptrs.deinit(a);
    {
        const idx = header_size + page_size; // page index 1
        if (idx + xlsr_offset <= bytes.len)
            try augment(a, bytes, idx + xlsr_offset, page_size - xlsr_offset, xlsr_size, xlsr_o_off, &bptrs);
    }
    for (3..page_count) |pg| {
        const base = header_size + pg * page_size;
        if (base + 20 > bytes.len) break;
        if (std.mem.eql(u8, bytes[base + 16 .. base + 20], "XLSR"))
            try augment(a, bytes, base + 16, page_size - 16, xlsr_size, xlsr_o_off, &bptrs);
    }

    var cats: std.ArrayList(format.UserFmt) = .empty;
    defer cats.deinit(a);
    for (bptrs.items) |bp| {
        const start_page: usize = @intCast(bp >> 32);
        const start_pos: usize = @intCast(bp & 0xFFFF);
        const block = try readBlock(a, bytes, header_size, page_size, page_count, start_page, start_pos);
        if (parseBlock(a, block) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.Unsupported, // malformed block — fail loud
        }) |uf| try cats.append(a, uf);
    }
    return cats.toOwnedSlice(a);
}

/// Walk XLSR records at `off`; each whose ownership byte is 'O' contributes a
/// (page,pos) block pointer. Some records carry 8 bytes of leading padding.
fn augment(a: std.mem.Allocator, b: []const u8, off: usize, len: usize, xlsr_size: usize, o_off: usize, out: *std.ArrayList(u64)) Error!void {
    var x = off;
    const end = off + len;
    while (x + xlsr_size <= end and x + xlsr_size <= b.len) {
        if (!std.mem.eql(u8, b[x .. x + 4], "XLSR")) x += 8;
        if (x + xlsr_size > b.len or !std.mem.eql(u8, b[x .. x + 4], "XLSR")) break;
        if (x + o_off < b.len and b[x + o_off] == 'O') {
            const page: u64 = rd32(b, x + 4);
            const pos: u64 = rd16(b, x + 8);
            try out.append(a, (page << 32) | pos);
        }
        x += xlsr_size;
    }
}

/// Follow a block's segment chain, concatenating each segment's payload (after
/// its 16-byte link header) into one buffer.
fn readBlock(a: std.mem.Allocator, b: []const u8, header_size: usize, page_size: usize, page_count: usize, start_page: usize, start_pos: usize) Error![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    var np = start_page;
    var npp = start_pos;
    var link: usize = 0;
    while (np > 0 and npp > 0 and np <= page_count and link < page_count) : (link += 1) {
        const seek = header_size + (np - 1) * page_size + npp;
        if (seek + 16 > b.len) break;
        const next_page = rd32(b, seek);
        const next_pos = rd16(b, seek + 4);
        const seg_len = rd16(b, seek + 6);
        const s = seek + 16;
        if (s + seg_len > b.len) break;
        try buf.appendSlice(a, b[s .. s + seg_len]);
        np = next_page;
        npp = next_pos;
    }
    return buf.toOwnedSlice(a);
}

/// Parse one block into a UserFmt (null if it carries no value labels).
fn parseBlock(a: std.mem.Allocator, data: []const u8) Error!?format.UserFmt {
    const payload_base: usize = 106; // 32-bit
    if (data.len < payload_base) return null;
    const flags = rd16(data, 2);
    var pad: usize = if (flags & 0x08 != 0) 4 else 0;
    const cap = rd32(data, 38 + pad);
    const used = rd32(data, 42 + pad);
    // short name at +8 (8 bytes).
    var name = std.mem.trimEnd(u8, std.mem.sliceTo(data[8..16], 0), " ");
    if (pad != 0) pad += 16;
    // Long-name (flags & 0x80): the real 32-byte name lives at payload_base+pad
    // (readstat sas7bcat_parse_block), and the value/label region is pushed 32
    // bytes further. Char formats keep their leading `$` here too.
    if (flags & 0x80 != 0) {
        if (data.len < payload_base + pad + 32) return null;
        name = std.mem.trimEnd(u8, std.mem.sliceTo(data[payload_base + pad ..][0..32], 0), " ");
        pad += 32;
    }
    if (used == 0) return null;

    const vs_off = payload_base + pad;
    if (vs_off > data.len) return null;
    return try parseValueLabels(a, data[vs_off..], used, cap, name);
}

/// The value+label region: `cap` VALUE entries then `used` LABEL entries. Each
/// value entry stores, at +14 (for pad1=4), the index of its paired label.
fn parseValueLabels(a: std.mem.Allocator, vs: []const u8, used: usize, cap: usize, name: []const u8) Error!format.UserFmt {
    const is_char = name.len > 0 and name[0] == '$';
    const base_name = if (is_char) name[1..] else name; // UserFmt name has no `$`

    // Pass 1: record each value entry's byte offset, keyed by its label index.
    const value_off = try a.alloc(usize, used);
    var p: usize = 0;
    for (0..cap) |i| {
        if (p + 4 > vs.len) return error.Unsupported;
        if (i < used) {
            if (p + 14 + 4 > vs.len) return error.Unsupported;
            const lpos = rd32(vs, p + 14); // 10 + pad1(=4)
            if (lpos >= used) return error.Unsupported;
            value_off[lpos] = p;
        }
        p += 6 + rd16(vs, p + 2);
    }
    var lbp2 = p; // labels region begins where the value entries end

    var entries: std.ArrayList(format.UserFmtEntry) = .empty;
    for (0..used) |i| {
        const p1 = value_off[i];
        var e: format.UserFmtEntry = .{ .label = "" };
        if (is_char) {
            if (p1 + 4 > vs.len) return error.Unsupported;
            const vel = 6 + rd16(vs, p1 + 2); // value entry length; key = last 16 bytes
            if (p1 + vel > vs.len or vel < 16) return error.Unsupported;
            e.skey = try a.dupe(u8, std.mem.trimEnd(u8, std.mem.sliceTo(vs[p1 + vel - 16 .. p1 + vel], 0), " "));
        } else {
            if (p1 + 30 > vs.len) return error.Unsupported;
            // Doubles are stored big-endian AND negated (readstat).
            const raw = std.mem.readInt(u64, vs[p1 + 22 ..][0..8], .big);
            if ((raw | 0xFF0000000000) == 0xFFFFFFFFFFFF) {
                // SAS special-missing key: the sas7bdat on-disk NaN
                // (0xFFFF<~ascii>00…, see sas7bdat.zig readNumber) bitwise-NOTed,
                // so BE byte 2 is the ASCII letter itself (readstat renders the
                // key '.'+letter the same way). 0/any other byte → plain missing.
                const c: u8 = @truncate(raw >> 40);
                const m = switch (c) {
                    'A'...'Z', '_' => Value.specialMissing(c).num,
                    else => Value.missing.num,
                };
                e.lo = m;
                e.hi = m;
            } else {
                const d = -@as(f64, @bitCast(raw));
                e.lo = d;
                e.hi = d;
            }
        }
        // Paired label: [len16 @ +8][string @ +10].
        if (lbp2 + 10 > vs.len) return error.Unsupported;
        const llen = rd16(vs, lbp2 + 8);
        if (lbp2 + 10 + llen > vs.len) return error.Unsupported;
        e.label = try a.dupe(u8, vs[lbp2 + 10 .. lbp2 + 10 + llen]);
        lbp2 += 8 + 2 + llen + 1;
        try entries.append(a, e);
    }
    return .{ .name = try a.dupe(u8, base_name), .is_char = is_char, .entries = try entries.toOwnedSlice(a) };
}

fn rd16(b: []const u8, o: usize) usize {
    return std.mem.readInt(u16, b[o..][0..2], .little);
}
fn rd32(b: []const u8, o: usize) usize {
    return std.mem.readInt(u32, b[o..][0..4], .little);
}

test "read formats.sas7bcat: matches pyreadstat oracle exactly (GH#34)" {
    // Oracle (pyreadstat.read_sas7bcat): $GENDER {f:Female, m:Male},
    // WORKSHOP {1.0:R, 2.0:SAS}. A REAL haven-authored catalog — it cannot share
    // a wrong offset assumption with this reader (the sas7bdat GH#31 lesson).
    const t = std.testing;
    const bytes = @embedFile("testdata/formats.sas7bcat");
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const cats = try read(arena.allocator(), bytes);

    try t.expectEqual(@as(usize, 2), cats.len);

    // $GENDER — char keys.
    const g = cats[0];
    try t.expectEqualStrings("GENDER", g.name);
    try t.expect(g.is_char);
    try t.expectEqual(@as(usize, 2), g.entries.len);
    try t.expectEqualStrings("f", g.entries[0].skey);
    try t.expectEqualStrings("Female", g.entries[0].label);
    try t.expectEqualStrings("m", g.entries[1].skey);
    try t.expectEqualStrings("Male", g.entries[1].label);

    // WORKSHOP — numeric keys (1→R, 2→SAS), stored big-endian & negated.
    const w = cats[1];
    try t.expectEqualStrings("WORKSHOP", w.name);
    try t.expect(!w.is_char);
    try t.expectEqual(@as(usize, 2), w.entries.len);
    try t.expectEqual(@as(f64, 1), w.entries[0].lo);
    try t.expectEqual(@as(f64, 1), w.entries[0].hi);
    try t.expectEqualStrings("R", w.entries[0].label);
    try t.expectEqual(@as(f64, 2), w.entries[1].lo);
    try t.expectEqualStrings("SAS", w.entries[1].label);
}

test "rejects non-catalog and u64 layout" {
    const t = std.testing;
    try t.expectError(error.NotSas7bcat, read(t.allocator, "not a catalog!!"));
    var hdr = [_]u8{0} ** 288;
    @memcpy(hdr[0..32], &magic);
    hdr[32] = 0x33; // u64 marker
    try t.expectError(error.Unsupported, read(t.allocator, &hdr));
}

test "NOTE-sas7bcatspecialmiss: a special-missing numeric key decodes to its missing Value (was silently dropped)" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // One value entry (30 bytes) + one label "see". The .C key is the sas7bdat
    // on-disk NaN (0xFFFF<~'C'>00…) bitwise-NOTed: BE bytes 00 00 'C' FF×5.
    var vs = [_]u8{0} ** 44;
    std.mem.writeInt(u16, vs[2..4], 24, .little); // value-entry length field → 6+24=30 bytes
    // label index u32 @14 = 0 (already zero)
    vs[24] = 'C'; // BE byte 2 of the 8-byte key @22
    for (vs[25..30]) |*b| b.* = 0xFF;
    std.mem.writeInt(u16, vs[38..40], 3, .little); // label length @lbp2+8
    @memcpy(vs[40..43], "see");

    const uf = try parseValueLabels(a, &vs, 1, 1, "MISSF");
    try t.expectEqualStrings("MISSF", uf.name);
    try t.expectEqual(@as(usize, 1), uf.entries.len); // NOT dropped
    try t.expectEqualStrings("see", uf.entries[0].label);
    try t.expectEqual(@as(u8, 'C'), Value.missingChar(uf.entries[0].lo));
    try t.expectEqual(@as(u64, @bitCast(uf.entries[0].lo)), @as(u64, @bitCast(uf.entries[0].hi)));

    // Plain-'.' key (letter byte 0) decodes to plain missing.
    var vs2 = vs;
    vs2[24] = 0;
    const uf2 = try parseValueLabels(a, &vs2, 1, 1, "MISSF");
    try t.expectEqual(@as(u8, '.'), Value.missingChar(uf2.entries[0].lo));
}
