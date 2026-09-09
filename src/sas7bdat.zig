//! sas7bdat (`.sas7bdat`) reader — the native SAS dataset format. Undocumented
//! by SAS, but reverse-engineered by the sas7bdat R package (Shotwell) and
//! readstat/pyreadstat, which this ports. Layout:
//!
//! Portions ported from ReadStat (https://github.com/WizardMac/ReadStat),
//! MIT License, Copyright (c) 2013-2016 Evan Miller.
//!
//!   header (header_length bytes) — magic, endianness/word-size flags, then
//!     header_length / page_size / page_count.
//!   pages (page_count × page_size) — each a 16-byte page header (page type,
//!     block count, subheader-pointer count) followed by, in a META/MIX page, a
//!     downward-growing array of subheader pointers whose targets carry the
//!     schema, and, in a MIX/DATA page, fixed-width observation rows.
//!
//! Schema comes from four subheaders keyed by a 4-byte signature: ROW_SIZE
//! (row length + total row count), COL_SIZE (column count), COLUMN_TEXT (a
//! string pool), COLUMN_NAME ((pool, offset, len) per column) and COLUMN_ATTRS
//! (in-row offset, width, type per column — numerics are packed first, so the
//! per-column offset is authoritative, not declaration order). A char value is
//! blank/nul-padded bytes; a numeric is a little-endian IEEE double, optionally
//! truncated to `width < 8` high-order bytes; a SAS missing is a NaN.
//!
//! Scope (ponytail: what real CDISC/SDTM files need — verified byte-exact against
//! pyreadstat on real SDTM files): little-endian, uncompressed. Both bitnesses:
//!   - 32-bit (byte-32 == 0x22) and 64-bit/u64 (0x33) are both read. The u64 path
//!     widens page offsets, subheader-pointer entries and per-subheader field
//!     offsets (ported from readstat); verified byte-exact vs pyreadstat on a real
//!     64-bit file (testdata/test7.sas7bdat, all 10×100 cells). Every width-varying
//!     read routes through `rdw()` — one branch, not scattered inline `if`s — which
//!     both reads cleaner AND (load-bearing) keeps register pressure in `read()`
//!     low enough that the Zig 0.16 self-hosted x86_64 backend allocates it
//!     correctly; the scattered-ternary version miscompiled `a1` on that backend
//!     (green under -fllvm and on aarch64, red on self-hosted x86_64 — the CI arch).
//!   - RLE/RDC compression → not handled (the corpus is all uncompressed); a
//!     compressed row would decode as garbage. Upgrade: SASYZCRL/SASYZCR2.
//!   - read-only: variable labels ARE read (each COLUMN_FORMAT subheader's
//!     LABEL text-pool ref — GAP-sas7bdatlabelsubheader, verified byte-exact vs
//!     the labels in testdata/hadley.sas7bdat) but never WRITTEN in-file: the
//!     writer emits no COLUMN_FORMAT subheader, so opensas-authored datasets
//!     persist labels/formats via the .labels sidecar (io.zig), as they already
//!     did for formats (GH#30/#31). In-file writing stays a separate ticket — a
//!     wrong sas7bdat writer corrupts every read, and no real-SAS consumer is
//!     available here to verify one against.

const std = @import("std");
const Dataset = @import("dataset.zig").Dataset;
const Value = @import("value.zig").Value;

pub const Error = error{ NotSas7bdat, Unsupported, OutOfMemory, Damaged };

const magic = [_]u8{
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0xc2, 0xea, 0x81, 0x60, 0xb3, 0x14, 0x11, 0xcf, 0xbd, 0x92, 0x08, 0x00,
    0x09, 0xc7, 0x31, 0x8c, 0x18, 0x1f, 0x10, 0x11,
};

// 32-bit page-layout constants; the u64 (0x33) file widens these (see read()).
const page_header_len = 16; // page-type is at page_start + this
const sp_len = 12; // one subheader pointer

// Subheader signatures (4-byte LE ints).
const sig_row_size = 0xF7F7F7F7;
const sig_col_size = 0xF6F6F6F6;
const sig_col_text = 0xFFFFFFFD;
const sig_col_name = 0xFFFFFFFF;
const sig_col_attr = 0xFFFFFFFC;
const sig_col_format = 0xFFFFFBFE; // Column Format/Label subheader (one per column)

// Page types (low byte-pair, page_start+16).
const page_data = 0x0100;
const page_mix = 0x0200;

const Col = struct { off: usize, width: usize, is_char: bool, name: []const u8, format: []const u8 = "", label: []const u8 = "" };

/// Parse a `.sas7bdat` file into a Dataset named `name`.
pub fn read(a: std.mem.Allocator, bytes: []const u8, name: []const u8) Error!*Dataset {
    if (bytes.len < 288 or !std.mem.eql(u8, bytes[0..32], &magic)) return error.NotSas7bdat;
    if (bytes[37] != 0x01) return error.Unsupported; // big-endian
    const u64f = bytes[32] == 0x33; // 0x33 = 64-bit (u64) layout, 0x22 = 32-bit
    const a1: usize = if (bytes[35] == 0x33) 4 else 0;

    // Layout deltas 32-bit → u64 (ported from readstat). 32-bit values are those
    // this reader has always used. Width-varying reads all go through rdw(); only
    // a handful of offsets need naming. `w` = a pointer/signature field's width
    // (also the COLUMN_TEXT pool's signature gap): 8 in a u64 file, 4 in a 32-bit.
    const w: usize = if (u64f) 8 else 4;
    const phl: usize = if (u64f) 32 else 16; // page-header size (type @ base+phl)
    const spl: usize = if (u64f) 24 else 12; // one subheader-pointer entry
    const rs_len_off: usize = if (u64f) 40 else 20; // ROW_SIZE row_length
    const rs_cnt_off: usize = if (u64f) 48 else 24; // ROW_SIZE total_row_count
    const fmt_ref: usize = if (u64f) 46 else 34; // COL_FORMAT FORMAT text-ref (idx/off/len u16s); the LABEL ref is the triple at fmt_ref+6
    // COL_ATTR: entries start at soff+w+8, one entry is w+8 wide, its width field is
    // at e+w (a u32) and its type byte at e+w+6 (all derived from w, no extra locals).

    const header_len = rd32(bytes, 196 + a1);
    const page_size = rd32(bytes, 200 + a1);
    const page_count = rdw(bytes, 204 + a1, u64f);
    if (page_size == 0 or header_len == 0) return error.NotSas7bdat;

    // Pass 1: walk every non-DATA page's subheaders to build the schema. The
    // string pool (COLUMN_TEXT) may span subheaders, so index those first.
    var row_len: usize = 0;
    var row_count: usize = 0;
    var texts = std.ArrayList(usize).empty; // pool base = subheader start + w
    defer texts.deinit(a);
    var attrs = std.ArrayList(struct { off: usize, width: usize, is_char: bool }).empty;
    defer attrs.deinit(a);
    var names = std.ArrayList(struct { text: usize, off: usize, len: usize }).empty;
    defer names.deinit(a);
    // COLUMN_FORMAT, one per column: FORMAT ref + LABEL ref (text-pool triples).
    var formats = std.ArrayList(struct { text: usize, off: usize, len: usize, ltext: usize, loff: usize, llen: usize }).empty;
    defer formats.deinit(a);

    // First sweep: locate COLUMN_TEXT pools (referenced by name offsets). The pool
    // blob begins at soff + w (readstat's subheader+signature_size).
    for (0..page_count) |pg| {
        const base = header_len + pg * page_size;
        if (base + phl + 8 > bytes.len) break;
        if (rd16(bytes, base + phl) == page_data) continue;
        const nsub = rd16(bytes, base + phl + 4);
        for (0..nsub) |i| {
            const p = base + phl + 8 + i * spl;
            if (p + spl > bytes.len) break;
            const soff = base + rdw(bytes, p, u64f);
            const slen = rdw(bytes, p + w, u64f);
            if (slen < w or soff + w > bytes.len) continue;
            if (rd32(bytes, soff) == sig_col_text) try texts.append(a, soff + w);
        }
    }

    // Second sweep: the sizing + name + attribute subheaders. Field offsets widen
    // in the u64 layout; see the deltas above.
    for (0..page_count) |pg| {
        const base = header_len + pg * page_size;
        if (base + phl + 8 > bytes.len) break;
        if (rd16(bytes, base + phl) == page_data) continue;
        const nsub = rd16(bytes, base + phl + 4);
        for (0..nsub) |i| {
            const p = base + phl + 8 + i * spl;
            if (p + spl > bytes.len) break;
            const soff = base + rdw(bytes, p, u64f);
            const slen = rdw(bytes, p + w, u64f);
            if (slen < w or soff + slen > bytes.len) continue;
            switch (rd32(bytes, soff)) {
                sig_row_size => {
                    row_len = rdw(bytes, soff + rs_len_off, u64f);
                    row_count = rdw(bytes, soff + rs_cnt_off, u64f);
                },
                sig_col_attr => {
                    // (w+8)-byte header, then (w+8)-byte entries; width @ e+w (u32),
                    // type byte @ e+w+6. (32-bit: 12/12, +4, +10 — as always.)
                    var e = soff + w + 8;
                    while (e + w + 8 <= soff + slen) : (e += w + 8) {
                        try attrs.append(a, .{
                            .off = rdw(bytes, e, u64f),
                            .width = rd32(bytes, e + w),
                            .is_char = bytes[e + w + 6] == 2,
                        });
                    }
                },
                sig_col_name => {
                    // (w+8)-byte header, then 8-byte (text_idx, off, len, pad) entries.
                    var e = soff + w + 8;
                    while (e + 8 <= soff + slen) : (e += 8) {
                        const ln = rd16(bytes, e + 4);
                        if (ln == 0) continue;
                        try names.append(a, .{ .text = rd16(bytes, e), .off = rd16(bytes, e + 2), .len = ln });
                    }
                },
                sig_col_format => {
                    // One subheader per column, in column order (readstat's
                    // sas7bdat_parse_column_format_subheader). The FORMAT text-pool
                    // ref is (index, offset, length) u16s at soff + fmt_ref: +34
                    // (32-bit) or +46 (u64); the LABEL ref is the next triple,
                    // fmt_ref+6/+8/+10. Both verified byte-exact vs real SAS files
                    // (hadley.sas7bdat 32-bit, which carries both a format and a
                    // label triple; test7.sas7bdat u64) — the old
                    // +22/+24/+26 triple was a guess that only matched a hand-built
                    // buffer. A subheader too short to hold BOTH refs is an
                    // unrecognised shape: Damaged, never a silently-dropped label
                    // (GAP-sas7bdatlabelsubheader; real files are 52/64 bytes).
                    if (slen < fmt_ref + 12) return error.Damaged;
                    try formats.append(a, .{
                        .text = rd16(bytes, soff + fmt_ref),
                        .off = rd16(bytes, soff + fmt_ref + 2),
                        .len = rd16(bytes, soff + fmt_ref + 4),
                        .ltext = rd16(bytes, soff + fmt_ref + 6),
                        .loff = rd16(bytes, soff + fmt_ref + 8),
                        .llen = rd16(bytes, soff + fmt_ref + 10),
                    });
                },
                else => {},
            }
        }
    }

    // Attributes carry the true column count and per-column layout; names align
    // to them by order (COL_SIZE agrees but is redundant).
    const ncol = attrs.items.len;
    if (ncol == 0) return error.NotSas7bdat;
    const cols = try a.alloc(Col, ncol);
    for (cols, 0..) |*c, i| {
        const at = attrs.items[i];
        var nm: []const u8 = "";
        if (i < names.items.len) {
            const n = names.items[i];
            if (n.text < texts.items.len) {
                const s = texts.items[n.text] + n.off;
                if (s + n.len <= bytes.len) nm = std.mem.trimEnd(u8, bytes[s .. s + n.len], " \x00");
            }
        }
        var fmt: []const u8 = "";
        var lbl: []const u8 = "";
        if (i < formats.items.len) {
            const f = formats.items[i];
            if (f.len > 0 and f.text < texts.items.len) {
                const s = texts.items[f.text] + f.off;
                if (s + f.len <= bytes.len) fmt = std.mem.trimEnd(u8, bytes[s .. s + f.len], " \x00");
            }
            if (f.llen > 0 and f.ltext < texts.items.len) {
                const s = texts.items[f.ltext] + f.loff;
                if (s + f.llen <= bytes.len) lbl = std.mem.trimEnd(u8, bytes[s .. s + f.llen], " \x00");
            }
        }
        c.* = .{ .off = at.off, .width = at.width, .is_char = at.is_char, .name = nm, .format = fmt, .label = lbl };
    }

    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, name);
    for (cols) |c| {
        _ = try ds.addColumn(c.name, if (c.is_char) .char else .num);
        if (c.format.len > 0) ds.setFormat(c.name, c.format);
        // GAP-sas7bdatlabelsubheader PRECEDENCE (deliberate, not load order):
        // the in-file label is the BASE layer — what the file shipped with. A
        // sibling .labels sidecar (applied by the loader AFTER this read,
        // main.zig loadLibInputs) WINS on conflict: the sidecar records the
        // latest program state (LABEL statement / MODIFY). Pinned where the two
        // disagree by corpus sas7bdat_label_precedence.
        if (c.label.len > 0) ds.setLabel(c.name, c.label);
        // A char column's COLUMN_ATTR width IS its declared storage length (SAS
        // descriptor semantics — the writer stamped it from Column.len), so
        // restore it: a write→read round-trip keeps `length x $8` instead of
        // shrinking to the data-max width (BUG-libnamelenloss).
        if (c.is_char and c.width > 0) ds.setLen(c.name, c.width);
    }
    // BUG-sas7bdattruncread: columns parsed but no ROW_SIZE subheader = the
    // schema pages themselves were truncated mid-sweep — damaged, NOT a valid
    // empty dataset (a real 0-obs dataset still declares row_length > 0).
    if (row_len == 0) return error.Damaged;

    // Rows live in MIX (metadata + data) and DATA pages, in page order. A MIX
    // page's data begins after its subheader-pointer array (8-aligned); its row
    // count is block_count − subheader_count. A DATA page is all rows, starting
    // right after the page header. Stop at the declared total.
    var read_rows: usize = 0;
    for (0..page_count) |pg| {
        if (read_rows >= row_count) break;
        const base = header_len + pg * page_size;
        if (base + phl + 4 > bytes.len) break;
        const ptype = rd16(bytes, base + phl);
        const block = rd16(bytes, base + phl + 2);
        var start: usize = undefined;
        var nrows: usize = undefined;
        if (ptype == page_mix) {
            const nsub = rd16(bytes, base + phl + 4);
            start = std.mem.alignForward(usize, phl + 8 + nsub * spl, 8);
            nrows = block - nsub;
        } else if (ptype == page_data) {
            start = phl + 8;
            nrows = block;
        } else continue;

        for (0..nrows) |r| {
            if (read_rows >= row_count) break;
            const ro = base + start + r * row_len;
            if (ro + row_len > bytes.len) break;
            const cells = try a.alloc(Value, ncol);
            for (cols, 0..) |c, i| {
                const field = bytes[ro + c.off .. ro + c.off + c.width];
                cells[i] = if (c.is_char)
                    // Slice the (arena-owned, program-lived) file buffer directly
                    // instead of duping every cell — a 340MB source is millions of
                    // char cells, and the per-cell dupe dominated load time, tripping
                    // the benchmark watchdog on the largest domains (BUG-clinhang). `bytes` is
                    // allocated with the same `a` as the Dataset, so it outlives it.
                    .{ .str = std.mem.trimEnd(u8, field, " \x00") }
                else
                    readNumber(field);
            }
            try ds.rows.append(a, cells);
            read_rows += 1;
        }
    }
    // BUG-sas7bdattruncread: the declared row_count is authoritative. Walking off
    // EOF first means the file was truncated on disk — fail loud (the member then
    // fails to load and the step ERRORs) instead of returning a silently-partial
    // study, the clinical worst case. A complete file reads exactly row_count.
    if (read_rows < row_count) return error.Damaged;
    return ds;
}

/// Write `ds` as a minimal 32-bit little-endian uncompressed sas7bdat that our own
/// `read` round-trips (E-sas7write). Layout: the standard 32-byte magic + header
/// fields, then page 0 = a schema-only MIX page carrying ROW_SIZE/COL_TEXT/
/// COL_NAME/COL_ATTR subheaders (block == subheader count → 0 data rows), then
/// N DATA pages of fixed-width rows. Numerics are full 8-byte IEEE doubles (NaN =
/// missing); char columns are space-padded to their max width.
/// ponytail: not the full SAS on-disk layout (no COL_FORMAT/labels — those
/// persist via the .labels sidecar, io.zig — no compression, no page checksums)
/// — just enough that our reader reconstructs the same dataset.
/// NOTE: engine hookup (libname writing .sas7bdat) lives in io.zig — not wired here
/// (dev1 owns io.zig this tick); this is the standalone writer it will call.
pub fn write(a: std.mem.Allocator, ds: *const Dataset) Error![]u8 {
    const ncol = ds.columns.items.len;
    if (ncol == 0) return error.Unsupported;
    const nrows = ds.rowCount();

    // per-column byte width (numeric = 8; char = max cell length, min 1) and the
    // column's offset within a fixed-width row.
    const widths = try a.alloc(usize, ncol);
    const offs = try a.alloc(usize, ncol);
    var row_len: usize = 0;
    for (ds.columns.items, 0..) |c, i| {
        var w: usize = 8;
        if (c.type == .char) {
            w = @max(c.len orelse 0, 1); // honor a declared LENGTH; never below the widest value
            for (ds.rows.items) |r| switch (r[i]) {
                .str => |s| w = @max(w, s.len),
                .num => {},
            };
        }
        offs[i] = row_len;
        widths[i] = w;
        row_len += w;
    }

    // COLUMN_TEXT string pool: names concatenated; record each (offset, length).
    var pool: std.ArrayList(u8) = .empty;
    defer pool.deinit(a);
    const name_off = try a.alloc(usize, ncol);
    const name_len = try a.alloc(usize, ncol);
    for (ds.columns.items, 0..) |c, i| {
        name_off[i] = pool.items.len;
        name_len[i] = c.name.len;
        try pool.appendSlice(a, c.name);
    }

    // Subheader layout inside page 0 (offsets relative to the page base).
    const sp_start = page_header_len + 8; // 24: subheader-pointer array
    const nsub: usize = 4;
    const text_off = align8(sp_start + nsub * sp_len);
    const text_len = 4 + pool.items.len;
    const rowsize_off = align8(text_off + text_len);
    const rowsize_len: usize = 28; // reader reads row_len@+20, row_count@+24
    const attr_off = align8(rowsize_off + rowsize_len);
    const attr_len = 12 + 12 * ncol;
    const cname_off = align8(attr_off + attr_len);
    const cname_len = 12 + 8 * ncol;
    const schema_end = cname_off + cname_len;

    const header_len: usize = 512;
    // A page must hold the schema page AND at least one full row on a data page.
    const page_size = align8(@max(schema_end, @max(sp_start + row_len, 4096)));
    const rows_per_page = @min((page_size - sp_start) / @max(row_len, 1), 65535);
    const data_pages = if (nrows == 0) 0 else (nrows + rows_per_page - 1) / rows_per_page;
    const page_count = 1 + data_pages;

    var buf = try a.alloc(u8, header_len + page_count * page_size);
    @memset(buf, 0);
    @memcpy(buf[0..32], &magic);
    buf[32] = 0x22; // 32-bit (not 0x33)
    buf[35] = 0x00; // a1 = 0
    buf[37] = 0x01; // little-endian
    wr32(buf, 196, header_len);
    wr32(buf, 200, page_size);
    wr32(buf, 204, page_count);

    // Page 0 — MIX, schema only (block == nsub ⇒ reader reads 0 rows here).
    const p0 = header_len;
    wr16(buf, p0 + 16, page_mix);
    wr16(buf, p0 + 18, nsub); // block count
    wr16(buf, p0 + 20, nsub); // subheader count
    const sps = [_][2]usize{
        .{ rowsize_off, rowsize_len },
        .{ text_off, text_len }, // COLUMN_TEXT collected first by the reader
        .{ cname_off, cname_len },
        .{ attr_off, attr_len },
    };
    for (sps, 0..) |s, i| {
        const p = p0 + sp_start + i * sp_len;
        wr32(buf, p, s[0]); // offset within page
        wr32(buf, p + 4, s[1]); // length
    }
    // ROW_SIZE
    wr32(buf, p0 + rowsize_off, sig_row_size);
    wr32(buf, p0 + rowsize_off + 20, row_len);
    wr32(buf, p0 + rowsize_off + 24, nrows);
    // COLUMN_TEXT (pool base = subheader start + 4)
    wr32(buf, p0 + text_off, sig_col_text);
    @memcpy(buf[p0 + text_off + 4 ..][0..pool.items.len], pool.items);
    // COLUMN_NAME (12-byte header, then 8-byte entries: text_idx, off, len, pad)
    wr32(buf, p0 + cname_off, sig_col_name);
    for (0..ncol) |i| {
        const e = p0 + cname_off + 12 + i * 8;
        wr16(buf, e, 0); // text pool index (only one pool)
        wr16(buf, e + 2, name_off[i]);
        wr16(buf, e + 4, name_len[i]);
    }
    // COLUMN_ATTR (12-byte header, then 12-byte entries: off, width, …, type@+10)
    wr32(buf, p0 + attr_off, sig_col_attr);
    for (ds.columns.items, 0..) |c, i| {
        const e = p0 + attr_off + 12 + i * 12;
        wr32(buf, e, offs[i]);
        wr32(buf, e + 4, widths[i]);
        buf[e + 10] = if (c.type == .char) 2 else 1;
    }

    // Data pages — fixed-width rows starting right after the page header (+24).
    var written: usize = 0;
    for (0..data_pages) |dp| {
        const base = header_len + (1 + dp) * page_size;
        const on_page = @min(rows_per_page, nrows - written);
        wr16(buf, base + 16, page_data);
        wr16(buf, base + 18, on_page); // block count = rows on this page
        for (0..on_page) |r| {
            const ro = base + sp_start + r * row_len;
            const row = ds.rows.items[written + r];
            for (ds.columns.items, 0..) |c, ci| {
                const co = ro + offs[ci];
                if (c.type == .char) {
                    const s = switch (row[ci]) {
                        .str => |v| v,
                        .num => "",
                    };
                    const n = @min(s.len, widths[ci]);
                    @memcpy(buf[co..][0..n], s[0..n]);
                    @memset(buf[co + n ..][0 .. widths[ci] - n], ' ');
                } else {
                    const x: f64 = switch (row[ci]) {
                        .num => |v| v,
                        .str => std.math.nan(f64),
                    };
                    std.mem.writeInt(u64, buf[co..][0..8], encodeNumber(x), .little);
                }
            }
        }
        written += on_page;
    }
    return buf;
}

fn align8(x: usize) usize {
    return std.mem.alignForward(usize, x, 8);
}
fn wr16(b: []u8, o: usize, v: usize) void {
    std.mem.writeInt(u16, b[o..][0..2], @intCast(v), .little);
}
fn wr32(b: []u8, o: usize, v: usize) void {
    std.mem.writeInt(u32, b[o..][0..4], @intCast(v), .little);
}

fn rd16(b: []const u8, o: usize) usize {
    return std.mem.readInt(u16, b[o..][0..2], .little);
}
fn rd32(b: []const u8, o: usize) usize {
    return std.mem.readInt(u32, b[o..][0..4], .little);
}
/// Read an unsigned little-endian field whose width follows the file's bitness:
/// 8 bytes in a u64 (0x33) file, 4 in a 32-bit (0x22) file. One branch, reused at
/// every width-varying call site — this concentration (vs an inline `if (u64f)
/// rd64 else rd32` at each site) is load-bearing: it keeps read()'s live-value
/// count low enough that Zig 0.16's self-hosted x86_64 backend register-allocates
/// it correctly. Callers guard o+8 ≤ b.len (u64) / o+4 (32-bit) before calling.
fn rdw(b: []const u8, o: usize, u64f: bool) usize {
    return if (u64f) @intCast(std.mem.readInt(u64, b[o..][0..8], .little)) else rd32(b, o);
}

/// A SAS numeric: an IEEE double stored little-endian, truncated to its `width`
/// high-order bytes (low bytes dropped). Reconstruct into the top of an 8-byte
/// buffer, low bytes zero. A NaN result is a SAS missing.
///
/// On-disk special missing (.A–.Z, ._, plain .) is a negative NaN whose big-endian
/// high two bytes are 0xFFFF and whose THIRD BE byte is the tag = bitwise-NOT of
/// the ASCII char: ~'A'=0xBE, ~'Z'=0xA5, ~'.'=0xD1, ~'_'=0xA0 (verified byte-exact
/// vs pyreadstat on testdata/tagged_na.sas7bdat and the plain-. in hadley.sas7bdat).
/// So the tag decodes as `char = 0xFF ^ tag`. Any OTHER NaN (no 0xFFFF prefix — an
/// arithmetic NaN, or opensas's own 0x7FF8|code write encoding) stays plain missing.
/// `encodeNumber` (below) is the write-side inverse, so write→read now round-trips.
fn readNumber(field: []const u8) Value {
    var buf = [_]u8{0} ** 8;
    const w = @min(field.len, 8);
    @memcpy(buf[8 - w ..], field[0..w]);
    const x: f64 = @bitCast(std.mem.readInt(u64, &buf, .little));
    if (!std.math.isNan(x)) return .{ .num = x };
    const bits: u64 = @bitCast(x);
    if (bits >> 48 == 0xFFFF) {
        const c: u8 = 0xFF ^ @as(u8, @truncate(bits >> 40));
        switch (c) {
            'A'...'Z', '_' => return Value.specialMissing(c),
            else => {}, // plain '.' (tag 0xD1) and any unknown tag → plain missing
        }
    }
    return Value.missing;
}

/// Inverse of `readNumber`'s special-missing decode: emit the SAS on-disk bits so
/// a write→read round-trips .A–.Z/._. A special missing is a negative NaN whose BE
/// high two bytes are 0xFFFF and whose third BE byte is the tag = ~ascii (0xFF^c).
/// opensas's own 0x7FF8|code NaN would otherwise collapse to plain missing on read.
/// Plain missing and present numbers pass through unchanged.
fn encodeNumber(x: f64) u64 {
    if (std.math.isNan(x)) {
        const c = Value.missingChar(x);
        if (c != '.') return (@as(u64, 0xFFFF) << 48) | (@as(u64, 0xFF ^ c) << 40);
    }
    return @bitCast(x);
}

test "encodeNumber ∘ readNumber round-trips special missing .A–.Z/._ (SAS7BDAT-writespecialmissing)" {
    const t = std.testing;
    var le: [8]u8 = undefined;
    for ("ABKZ_") |c| {
        std.mem.writeInt(u64, &le, encodeNumber(Value.specialMissing(c).num), .little);
        const back = readNumber(&le);
        try t.expect(back.isMissing());
        try t.expectEqual(c, Value.missingChar(back.num));
    }
    // the on-disk bytes match SAS's convention (.A → BE ffffbe…, .Z → ffffa5…)
    std.mem.writeInt(u64, &le, encodeNumber(Value.specialMissing('A').num), .little);
    try t.expectEqualSlices(u8, &.{ 0, 0, 0, 0, 0, 0xbe, 0xff, 0xff }, &le);
    // plain missing and present numbers are untouched
    try t.expectEqual(@as(u64, @bitCast(@as(f64, 3.5))), encodeNumber(3.5));
    try t.expect(readNumber(blk: {
        std.mem.writeInt(u64, &le, encodeNumber(Value.missing.num), .little);
        break :blk &le;
    }).isMissing());
}

test "readNumber: full, truncated, and missing" {
    const t = std.testing;
    // 1.0 = 0x3FF0000000000000 → LE bytes 00 00 00 00 00 00 f0 3f
    try t.expectEqual(@as(f64, 1), readNumber(&.{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xf0, 0x3f }).num);
    // 991.0 (DDDY, dd.sas7bdat row 0), byte-exact from the file
    try t.expectEqual(@as(f64, 991), readNumber(&.{ 0x00, 0x00, 0x00, 0x00, 0x00, 0xf8, 0x8e, 0x40 }).num);
    // 1.0 truncated to 3 high bytes (00 f0 3f) rehydrates to 1.0
    try t.expectEqual(@as(f64, 1), readNumber(&.{ 0x00, 0xf0, 0x3f }).num);
    // a quiet NaN is a SAS missing
    try t.expect(readNumber(&.{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xf8, 0x7f }).isMissing());
    // on-disk special missing: BE ffff<tag>… , tag = ~ascii → .A/.Z/._ ; plain . (0xD1)
    try t.expectEqual(@as(u8, 'A'), Value.missingChar(readNumber(&.{ 0, 0, 0, 0, 0, 0xbe, 0xff, 0xff }).num));
    try t.expectEqual(@as(u8, 'Z'), Value.missingChar(readNumber(&.{ 0, 0, 0, 0, 0, 0xa5, 0xff, 0xff }).num));
    try t.expectEqual(@as(u8, '_'), Value.missingChar(readNumber(&.{ 0, 0, 0, 0, 0, 0xa0, 0xff, 0xff }).num));
    try t.expectEqual(@as(u8, '.'), Value.missingChar(readNumber(&.{ 0, 0, 0, 0, 0, 0xd1, 0xff, 0xff }).num));
    try t.expect(readNumber(&.{ 0, 0, 0, 0, 0, 0xd1, 0xff, 0xff }).isMissing());
}

test "read tagged_na.sas7bdat: numeric special missing .A/.H/.Z (GH#54)" {
    // A REAL SAS-authored file (haven test data): one numeric col x = 1 2 3 4 5 .A .H .Z.
    // Oracle (pyreadstat, user_missing=True): [1,2,3,4,5,'A','H','Z']. Asserts on the
    // decoded VALUE (present number / special-missing letter), not formatted output —
    // the column carries a user format XFMT absent from any catalog, irrelevant here.
    const t = std.testing;
    const bytes = @embedFile("testdata/tagged_na.sas7bdat");
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const ds = try read(arena.allocator(), bytes, "work.tn");

    try t.expectEqual(@as(usize, 1), ds.columns.items.len);
    try t.expectEqualStrings("x", ds.columns.items[0].name);
    try t.expectEqual(@as(usize, 8), ds.rowCount());
    // rows 0..4: present 1..5
    for (0..5) |i| try t.expectEqual(@as(f64, @floatFromInt(i + 1)), ds.row(i)[0].num);
    // rows 5..7: special missing .A .H .Z (NaN != NaN → compare via missingChar)
    try t.expect(ds.row(5)[0].isMissing() and ds.row(6)[0].isMissing() and ds.row(7)[0].isMissing());
    try t.expectEqual(@as(u8, 'A'), Value.missingChar(ds.row(5)[0].num));
    try t.expectEqual(@as(u8, 'H'), Value.missingChar(ds.row(6)[0].num));
    try t.expectEqual(@as(u8, 'Z'), Value.missingChar(ds.row(7)[0].num));
}

test "multi-page: rows accumulate across separate DATA pages (E-sas7read)" {
    // Real CDISC domains spread rows over hundreds of DATA pages; but
    // every committed real file keeps its rows on page 0, so craft a minimal file with
    // one numeric column, a schema-only MIX page, then two DATA pages holding one
    // row each — proving the page walk reads rows from BOTH data pages, not just the
    // first. (Real multi-hundred-page files are verified out of tree.)
    const t = std.testing;
    const hlen = 512;
    const psize = 512;
    var buf = [_]u8{0} ** (hlen + 3 * psize);
    @memcpy(buf[0..32], &magic);
    buf[32] = 0x22; // 32-bit
    buf[35] = 0x00; // a1 = 0 (no header-field shift)
    buf[37] = 0x01; // little-endian
    std.mem.writeInt(u32, buf[196..][0..4], hlen, .little);
    std.mem.writeInt(u32, buf[200..][0..4], psize, .little);
    std.mem.writeInt(u32, buf[204..][0..4], 3, .little); // page_count

    // page 0: MIX carrying ROW_SIZE + COL_ATTR subheaders and zero rows.
    const p0 = hlen;
    std.mem.writeInt(u16, buf[p0 + 16 ..][0..2], page_mix, .little);
    std.mem.writeInt(u16, buf[p0 + 18 ..][0..2], 2, .little); // block == nsub → 0 rows
    std.mem.writeInt(u16, buf[p0 + 20 ..][0..2], 2, .little); // nsub
    const sp = p0 + 24; // subheader-pointer array
    std.mem.writeInt(u32, buf[sp..][0..4], 48, .little); // ROW_SIZE @ +48
    std.mem.writeInt(u32, buf[sp + 4 ..][0..4], 32, .little);
    std.mem.writeInt(u32, buf[sp + 12 ..][0..4], 80, .little); // COL_ATTR @ +80
    std.mem.writeInt(u32, buf[sp + 16 ..][0..4], 24, .little);
    std.mem.writeInt(u32, buf[p0 + 48 ..][0..4], sig_row_size, .little);
    std.mem.writeInt(u32, buf[p0 + 48 + 20 ..][0..4], 8, .little); // row_len
    std.mem.writeInt(u32, buf[p0 + 48 + 24 ..][0..4], 2, .little); // row_count
    std.mem.writeInt(u32, buf[p0 + 80 ..][0..4], sig_col_attr, .little);
    std.mem.writeInt(u32, buf[p0 + 80 + 12 ..][0..4], 0, .little); // col offset
    std.mem.writeInt(u32, buf[p0 + 80 + 16 ..][0..4], 8, .little); // col width
    buf[p0 + 80 + 12 + 10] = 1; // type byte: 1 = numeric (2 would be char)

    // pages 1 and 2: one DATA row each (42.0, then 99.0).
    const p1 = hlen + psize;
    std.mem.writeInt(u16, buf[p1 + 16 ..][0..2], page_data, .little);
    std.mem.writeInt(u16, buf[p1 + 18 ..][0..2], 1, .little);
    std.mem.writeInt(u64, buf[p1 + 24 ..][0..8], @bitCast(@as(f64, 42)), .little);
    const p2 = hlen + 2 * psize;
    std.mem.writeInt(u16, buf[p2 + 16 ..][0..2], page_data, .little);
    std.mem.writeInt(u16, buf[p2 + 18 ..][0..2], 1, .little);
    std.mem.writeInt(u64, buf[p2 + 24 ..][0..8], @bitCast(@as(f64, 99)), .little);

    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const ds = try read(arena.allocator(), &buf, "work.mp");
    try t.expectEqual(@as(usize, 1), ds.columns.items.len);
    try t.expectEqual(@as(usize, 2), ds.rowCount());
    try t.expectEqual(@as(f64, 42), ds.row(0)[0].num); // page 1
    try t.expectEqual(@as(f64, 99), ds.row(1)[0].num); // page 2 — the multi-page proof
}

test "reader attaches a COLUMN_FORMAT name (GH#30)" {
    // opensas's own write() emits no format subheader, so hand-craft a minimal
    // 32-bit LE file whose schema page carries a COLUMN_FORMAT subheader at the
    // real readstat offsets (format text-pool ref @+22/+24/+26), proving the
    // reader parses the attached FORMAT name off a real-SAS layout.
    const t = std.testing;
    const hlen = 512;
    const psize = 512;
    var buf = [_]u8{0} ** (hlen + psize);
    @memcpy(buf[0..32], &magic);
    buf[32] = 0x22; // 32-bit
    buf[35] = 0x00; // a1 = 0
    buf[37] = 0x01; // little-endian
    std.mem.writeInt(u32, buf[196..][0..4], hlen, .little);
    std.mem.writeInt(u32, buf[200..][0..4], psize, .little);
    std.mem.writeInt(u32, buf[204..][0..4], 1, .little); // page_count

    // page 0: MIX, 5 subheaders, zero rows (block == nsub).
    const p0 = hlen;
    std.mem.writeInt(u16, buf[p0 + 16 ..][0..2], page_mix, .little);
    std.mem.writeInt(u16, buf[p0 + 18 ..][0..2], 5, .little);
    std.mem.writeInt(u16, buf[p0 + 20 ..][0..2], 5, .little);
    const sp = p0 + 24;
    const subs = [_][2]u32{ // (offset-in-page, length)
        .{ 112, 28 }, // ROW_SIZE
        .{ 88, 24 }, // COL_TEXT
        .{ 140, 20 }, // COL_NAME
        .{ 160, 24 }, // COL_ATTR
        .{ 184, 52 }, // COL_FORMAT
    };
    for (subs, 0..) |s, i| {
        std.mem.writeInt(u32, buf[sp + i * sp_len ..][0..4], s[0], .little);
        std.mem.writeInt(u32, buf[sp + i * sp_len + 4 ..][0..4], s[1], .little);
    }
    // COL_TEXT pool (base = subheader + 4): "X" (name), "BEST12." (format),
    // "In File X" (label).
    std.mem.writeInt(u32, buf[p0 + 88 ..][0..4], sig_col_text, .little);
    @memcpy(buf[p0 + 92 ..][0..17], "XBEST12.In File X");
    // ROW_SIZE: row_len@+20, row_count@+24 (both irrelevant here → 8, 0).
    std.mem.writeInt(u32, buf[p0 + 112 ..][0..4], sig_row_size, .little);
    std.mem.writeInt(u32, buf[p0 + 112 + 20 ..][0..4], 8, .little);
    // COL_NAME: one entry (text 0, off 0, len 1 → "X").
    std.mem.writeInt(u32, buf[p0 + 140 ..][0..4], sig_col_name, .little);
    std.mem.writeInt(u16, buf[p0 + 140 + 12 + 4 ..][0..2], 1, .little); // len
    // COL_ATTR: one numeric column (off 0, width 8, type 1).
    std.mem.writeInt(u32, buf[p0 + 160 ..][0..4], sig_col_attr, .little);
    std.mem.writeInt(u32, buf[p0 + 160 + 12 + 4 ..][0..4], 8, .little); // width
    buf[p0 + 160 + 12 + 10] = 1; // numeric
    // COL_FORMAT: format ref index@+34=0, offset@+36=1, length@+38=7 → "BEST12.";
    // label ref index@+40=0 (zero-filled), offset@+42=8, length@+44=9 → "In File X".
    std.mem.writeInt(u32, buf[p0 + 184 ..][0..4], sig_col_format, .little);
    std.mem.writeInt(u16, buf[p0 + 184 + 36 ..][0..2], 1, .little); // pool offset
    std.mem.writeInt(u16, buf[p0 + 184 + 38 ..][0..2], 7, .little); // length
    std.mem.writeInt(u16, buf[p0 + 184 + 42 ..][0..2], 8, .little); // label pool offset
    std.mem.writeInt(u16, buf[p0 + 184 + 44 ..][0..2], 9, .little); // label length

    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const ds = try read(arena.allocator(), &buf, "work.f");
    try t.expectEqual(@as(usize, 1), ds.columns.items.len);
    try t.expectEqualStrings("X", ds.columns.items[0].name);
    try t.expect(ds.columns.items[0].format != null);
    try t.expectEqualStrings("BEST12.", ds.columns.items[0].format.?);
    try t.expectEqualStrings("In File X", ds.columns.items[0].label.?);
}

test "read hadley.sas7bdat: real-file COLUMN_FORMAT names (GH#31, non-circular)" {
    // A REAL, externally-authored 32-bit SAS file (tidyverse/haven test data). It
    // cannot share a wrong offset assumption with the reader — that is the whole
    // point vs the hand-built GH#30 self-test. pyreadstat's oracle:
    //   original_variable_types = {id:None, workshop:'WORKSHOP', gender:'$GENDER',
    //                              q1..q4: None}
    const t = std.testing;
    const bytes = @embedFile("testdata/hadley.sas7bdat");
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const ds = try read(arena.allocator(), bytes, "work.hadley");

    const want_names = [_][]const u8{ "id", "workshop", "gender", "q1", "q2", "q3", "q4" };
    try t.expectEqual(want_names.len, ds.columns.items.len);
    for (want_names, 0..) |n, i| try t.expectEqualStrings(n, ds.columns.items[i].name);

    // workshop → WORKSHOP, gender → $GENDER, everything else no format.
    try t.expectEqualStrings("WORKSHOP", ds.columns.items[1].format.?);
    try t.expectEqualStrings("$GENDER", ds.columns.items[2].format.?);
    for ([_]usize{ 0, 3, 4, 5, 6 }) |i| try t.expect(ds.columns.items[i].format == null);
}

test "real files carry variable LABELS in-file: hadley q1–q4 (GAP-sas7bdatlabelsubheader, non-circular)" {
    // The other half of GH#31's evidence class: a REAL, externally-authored 32-bit
    // SAS file whose COLUMN_FORMAT subheaders carry LABEL text-pool refs (the
    // triple at fmt_ref+6). It cannot share a wrong offset assumption with the
    // reader. hadley.sas7bdat labels the four survey questions and nothing else.
    // The u64 label offsets (fmt_ref+6 = +52/+54/+56) compose two verified deltas
    // (u64 widening via test7's formats, the fmt→label +6 via this 32-bit file):
    // no committed real u64 file carries labels.
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const hadley = try read(a, @embedFile("testdata/hadley.sas7bdat"), "work.hadley");
    for ([_]usize{ 0, 1, 2 }) |i| try t.expect(hadley.columns.items[i].label == null);
    const q_labels = [_][]const u8{
        "The instructor was well prepared",
        "The instructor communicated well",
        "The course material was helpful",
        "Overall, I found the workhsop useful", // [sic] — the file's own spelling
    };
    for (q_labels, 3..) |l, i| try t.expectEqualStrings(l, hadley.columns.items[i].label.?);

    // No label anywhere in the u64 test7 file → every label ref decodes empty.
    const t7 = try read(a, @embedFile("testdata/test7.sas7bdat"), "work.t7");
    for (t7.columns.items) |c| try t.expect(c.label == null);
}

test "write → read round-trips a mixed num/char dataset incl. missing (E-sas7write)" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var src = Dataset.init(a, "work.out");
    _ = try src.addColumn("ID", .num);
    _ = try src.addColumn("NAME", .char);
    _ = try src.addColumn("AMT", .num);
    try src.appendRow(&.{ .{ .num = 1 }, .{ .str = "Alice" }, .{ .num = 100.5 } });
    try src.appendRow(&.{ .{ .num = 2 }, .{ .str = "Bo" }, Value.missing }); // missing numeric
    try src.appendRow(&.{ .{ .num = 3 }, .{ .str = "Charlie" }, .{ .num = -7 } });

    const bytes = try write(a, &src);
    const back = try read(a, bytes, "work.rt");

    try t.expectEqual(@as(usize, 3), back.columns.items.len);
    try t.expectEqualStrings("ID", back.columns.items[0].name);
    try t.expectEqualStrings("NAME", back.columns.items[1].name);
    try t.expectEqualStrings("AMT", back.columns.items[2].name);
    try t.expect(back.columns.items[0].type == .num);
    try t.expect(back.columns.items[1].type == .char);

    try t.expectEqual(@as(usize, 3), back.rowCount());
    try t.expectEqual(@as(f64, 1), back.row(0)[0].num);
    try t.expectEqualStrings("Alice", back.row(0)[1].str);
    try t.expectEqual(@as(f64, 100.5), back.row(0)[2].num);
    try t.expectEqualStrings("Bo", back.row(1)[1].str);
    try t.expect(back.row(1)[2].isMissing()); // missing survived
    try t.expectEqual(@as(f64, 3), back.row(2)[0].num);
    try t.expectEqualStrings("Charlie", back.row(2)[1].str);
    try t.expectEqual(@as(f64, -7), back.row(2)[2].num);
}

test "write → read preserves a char column's DECLARED length over the data max (BUG-libnamelenloss)" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // `length code $8; code='AB';` — declared 8, widest value 2. The writer
    // stores 8 as the COLUMN_ATTR width; the reader must restore it as
    // Column.len, not shrink to the data max 2 (SDTM controlled metadata).
    var src = Dataset.init(a, "work.d");
    _ = try src.addColumn("code", .char);
    src.setLen("code", 8);
    try src.appendRow(&.{.{ .str = "AB" }});
    try src.appendRow(&.{.{ .str = "CD" }});

    const back = try read(a, try write(a, &src), "work.rt");
    try t.expectEqual(@as(?usize, 8), back.columns.items[0].len);
    try t.expectEqualStrings("AB", back.row(0)[0].str);
}

test "write → read: multi-page rows (more than one DATA page) (E-sas7write)" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var src = Dataset.init(a, "work.big");
    _ = try src.addColumn("V", .num);
    // 2000 rows × 8 bytes = 16000B > one 4096B page's row area → forces >1 DATA page
    for (0..2000) |i| try src.appendRow(&.{.{ .num = @floatFromInt(i) }});

    const back = try read(a, try write(a, &src), "work.rt");
    try t.expectEqual(@as(usize, 2000), back.rowCount());
    try t.expectEqual(@as(f64, 0), back.row(0)[0].num);
    try t.expectEqual(@as(f64, 1999), back.row(1999)[0].num);
}

test "write → read: special missing .A/.Z/._ survive the round-trip (SAS7BDAT-writespecialmissing)" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var src = Dataset.init(a, "work.sm");
    _ = try src.addColumn("V", .num);
    try src.appendRow(&.{.{ .num = 42 }}); // present number, control
    try src.appendRow(&.{Value.specialMissing('A')});
    try src.appendRow(&.{Value.specialMissing('Z')});
    try src.appendRow(&.{Value.specialMissing('_')});
    try src.appendRow(&.{Value.missing}); // plain missing

    const back = try read(a, try write(a, &src), "work.rt");
    try t.expectEqual(@as(usize, 5), back.rowCount());
    try t.expectEqual(@as(f64, 42), back.row(0)[0].num);
    try t.expectEqual(@as(u8, 'A'), Value.missingChar(back.row(1)[0].num));
    try t.expectEqual(@as(u8, 'Z'), Value.missingChar(back.row(2)[0].num));
    try t.expectEqual(@as(u8, '_'), Value.missingChar(back.row(3)[0].num));
    try t.expect(back.row(4)[0].isMissing());
    try t.expectEqual(@as(u8, '.'), Value.missingChar(back.row(4)[0].num));
}

test "truncated file fails loud: read rows < declared row_count → Damaged (BUG-sas7bdattruncread)" {
    // The clinical worst case: a sas7bdat truncated on disk used to return a
    // SILENTLY-PARTIAL dataset (50 of 100 rows, no error). Now: error.Damaged.
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var src = Dataset.init(a, "work.t");
    _ = try src.addColumn("V", .num);
    for (0..100) |i| try src.appendRow(&.{.{ .num = @floatFromInt(i) }});
    const bytes = try write(a, &src);

    // Control: the COMPLETE file still reads all 100 declared rows.
    const full = try read(a, bytes, "work.rt");
    try t.expectEqual(@as(usize, 100), full.rowCount());
    try t.expectEqual(@as(f64, 99), full.row(99)[0].num);

    // Cut mid-data: header + schema page + 50 of the 100 rows' bytes. The page
    // walk runs out of bytes at row 50 — Damaged, not a 50-row dataset.
    const hlen = rd32(bytes, 196);
    const psize = rd32(bytes, 200);
    const mid_data = hlen + psize + 24 + 50 * 8;
    try t.expectError(error.Damaged, read(a, bytes[0..mid_data], "work.rt"));

    // Data page entirely absent (schema intact, declares 100, EOF at page 1).
    try t.expectError(error.Damaged, read(a, bytes[0 .. hlen + psize], "work.rt"));

    // Schema itself damaged (ROW_SIZE subheader unparseable → row_len 0) with
    // columns present: also loud, never a silently-empty dataset. (Pure
    // truncation can't reach this branch — our writer lays ROW_SIZE below
    // COL_ATTR — so clobber the signature instead; same sweep-skip shape.)
    const mut = try a.dupe(u8, bytes);
    const sig_at = std.mem.indexOf(u8, mut, &[_]u8{ 0xF7, 0xF7, 0xF7, 0xF7 }).?;
    @memset(mut[sig_at..][0..4], 0);
    try t.expectError(error.Damaged, read(a, mut, "work.rt"));

    // No false alarm: a valid EMPTY dataset (0 declared, 0 read) still reads.
    var empty = Dataset.init(a, "work.e");
    _ = try empty.addColumn("V", .num);
    const eds = try read(a, try write(a, &empty), "work.re");
    try t.expectEqual(@as(usize, 0), eds.rowCount());
}

test "rejects non-sas7bdat and big-endian" {
    const t = std.testing;
    try t.expectError(error.NotSas7bdat, read(t.allocator, "not a sas file at all!!", "x"));
    // big-endian (byte 37 != 0x01) is unsupported on both bitnesses.
    var hdr = [_]u8{0} ** 288;
    @memcpy(hdr[0..32], &magic);
    hdr[37] = 0x00; // big-endian marker
    try t.expectError(error.Unsupported, read(t.allocator, &hdr, "x"));
}

test "read test7.sas7bdat: real 64-bit (u64) file (SAS7BDAT-u64, non-circular vs pyreadstat)" {
    // A REAL 64-bit sas7bdat (byte 32 == 0x33) from pandas' public test suite
    // (BSD-licensed). Oracle = pyreadstat: 10 rows × 100 cols, Column1..Column100;
    // Column1 numeric, Column2 $9 char, Column4 MMDDYY10 date. Values below are
    // pyreadstat's, so wrong u64 offsets cannot silently pass (the #31/#34 lesson).
    // Exercises the u64 page/subheader/attr/name/format layout end to end. This is
    // ALSO the arch guard: the reader miscompiled the 32-bit fixtures on the
    // self-hosted x86_64 backend before rdw() concentrated the width branch — the
    // corpus runs on aarch64 and CI on x86_64, so both must stay green.
    const t = std.testing;
    const bytes = @embedFile("testdata/test7.sas7bdat");
    try t.expectEqual(@as(u8, 0x33), bytes[32]); // this IS a 64-bit file
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const ds = try read(arena.allocator(), bytes, "work.t7");

    try t.expectEqual(@as(usize, 100), ds.columns.items.len);
    try t.expectEqual(@as(usize, 10), ds.rowCount());
    try t.expectEqualStrings("Column1", ds.columns.items[0].name);
    try t.expectEqualStrings("Column2", ds.columns.items[1].name);
    try t.expectEqualStrings("Column100", ds.columns.items[99].name);
    try t.expect(ds.columns.items[0].type == .num);
    try t.expect(ds.columns.items[1].type == .char);
    try t.expect(ds.columns.items[3].type == .num); // MMDDYY10 date is numeric

    // row 0: Column1=0.636, Column2="pear", Column3=84, Column4=2170, Column6="apple"
    try t.expectEqual(@as(f64, 0.636), ds.row(0)[0].num);
    try t.expectEqualStrings("pear", ds.row(0)[1].str);
    try t.expectEqual(@as(f64, 84), ds.row(0)[2].num);
    try t.expectEqual(@as(f64, 2170), ds.row(0)[3].num);
    try t.expectEqualStrings("apple", ds.row(0)[5].str);
    // row 1: Column1=0.283, Column2="dog"
    try t.expectEqual(@as(f64, 0.283), ds.row(1)[0].num);
    try t.expectEqualStrings("dog", ds.row(1)[1].str);

    // Attached FORMAT parses off the u64 COLUMN_FORMAT layout (GH#30/#31/#34). The
    // reader stores the base format NAME only (width/decimal are a separate field it
    // doesn't read, same as the 32-bit path), so "MMDDYY10." surfaces as "MMDDYY".
    try t.expectEqualStrings("MMDDYY", ds.columns.items[3].format.?);
}
