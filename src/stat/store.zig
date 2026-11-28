//! Shared STORE contract, S154 physical pp.543–545. The native envelope below
//! is explicitly OpenSAS, NOT a SAS proprietary ITEMSTOR binary implementation.
//! Format 1: magic, LE version/u64 payload length, SHA-256, UTF-8 JSON payload.
//! The checksum detects damaged content; it is not an authenticity signature.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const eq = std.ascii.eqlIgnoreCase;
const A = std.mem.Allocator;
const magic = "OpenSAS.ItemStore";
const header_size = magic.len + 4 + 8 + 32;
const max_bytes = 64 * 1024 * 1024;
pub const extension = ".opensasitem";
pub const Request = struct { name: []const u8, label: []const u8 = "", line: usize = 0 };
pub const Level = struct { number: ?f64 = null, text: ?[]const u8 = null, label: []const u8 };
pub const Class = struct { name: []const u8, levels: []const Level };
pub const Factor = struct { name: []const u8, class_index: ?usize = null };
pub const Effect = struct { name: []const u8, start: usize, len: usize, factors: []const Factor };
pub const Covariate = struct { name: []const u8, mean: f64 };
pub const Model = struct {
    procedure: []const u8,
    input: []const u8,
    response: []const u8,
    label: []const u8,
    created_unix_seconds: i64,
    coding: []const u8 = "sum-to-zero",
    family: []const u8 = "normal",
    link: []const u8 = "identity",
    intercept: bool,
    effects: []const Effect,
    classes: []const Class,
    covariates: []const Covariate,
    coefficients: []const f64,
    /// MSE-scaled covariance in the explicitly saved parameter basis.
    covariance: []const f64,
    df_error: usize,
    mse: f64,
    n_used: usize,
};
fn nameValid(name: []const u8, max: usize) bool {
    if (name.len == 0 or name.len > max or !(std.ascii.isAlphabetic(name[0]) or name[0] == '_')) return false;
    for (name[1..]) |c| if (!(std.ascii.isAlphanumeric(c) or c == '_')) return false;
    return true;
}
fn canonical(a: A, name: []const u8) ![]const u8 {
    const dot = std.mem.indexOfScalar(u8, name, '.');
    if (dot) |i| {
        if (!nameValid(name[0..i], 8) or !nameValid(name[i + 1 ..], 32)) return error.InvalidName;
        return std.ascii.allocLowerString(a, name);
    }
    if (!nameValid(name, 32)) return error.InvalidName;
    return std.fmt.allocPrint(a, "work.{s}", .{try std.ascii.allocLowerString(a, name)});
}
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
/// Tokens after STORE and before the terminating semicolon; accepts both the
/// ordinary lexer tokens and main's already-coalesced two-level names.
pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Request {
    var i: usize = 0;
    if (at(t, i, .name) and eq(t[i].text, "out") and at(t, i + 1, .eq)) i += 2;
    const line = if (t.len > 0) t[0].line else 0;
    if (!at(t, i, .name)) return cx.diags.fail(error.ParseError, line, "STORE: expected an item-store name", .{});
    var name = t[i].text;
    i += 1;
    if (at(t, i, .dot)) {
        if (!at(t, i + 1, .name)) return cx.diags.fail(error.ParseError, line, "STORE: expected a member name", .{});
        name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name, t[i + 1].text });
        i += 2;
    }
    const normalized = canonical(cx.arena, name) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return cx.diags.fail(error.ParseError, line, "STORE: invalid one- or two-level item-store name", .{});
    };
    var label: []const u8 = "";
    if (i < t.len) {
        if (!at(t, i, .slash) or !at(t, i + 1, .name) or !eq(t[i + 1].text, "label") or !at(t, i + 2, .eq) or !at(t, i + 3, .string) or i + 4 != t.len) return cx.diags.fail(error.ParseError, line, "STORE: expected / LABEL='label'", .{});
        label = t[i + 3].text;
        i += 4;
    }
    if (i != t.len) return cx.diags.fail(error.ParseError, line, "STORE: unexpected trailing tokens", .{});
    return .{ .name = normalized, .label = label, .line = line };
}

fn validate(m: Model) !void {
    if (!eq(m.procedure, "GLM") or !std.mem.eql(u8, m.coding, "sum-to-zero") or !std.mem.eql(u8, m.family, "normal") or !std.mem.eql(u8, m.link, "identity")) return error.IncompatibleModel;
    const p = m.coefficients.len;
    if (p == 0 or p > 2048 or m.covariance.len != p * p or m.df_error == 0 or (m.n_used < p or m.df_error != m.n_used - p) or !std.math.isFinite(m.mse) or m.mse < 0 or !nameValid(m.response, 32)) return error.CorruptStore;
    for (m.coefficients) |v| if (!std.math.isFinite(v)) return error.CorruptStore;
    for (m.covariance, 0..) |v, i| {
        if (!std.math.isFinite(v) or v != m.covariance[(i % p) * p + i / p]) return error.CorruptStore;
        if (i / p == i % p and v < 0) return error.CorruptStore;
    }
    for (m.classes, 0..) |c, ci| {
        if (!nameValid(c.name, 32)) return error.CorruptStore;
        for (m.classes[0..ci]) |other| if (eq(c.name, other.name)) return error.CorruptStore;
        for (c.levels, 0..) |level, k| {
            if ((level.number == null) == (level.text == null)) return error.CorruptStore;
            if ((level.number != null) != (c.levels[0].number != null)) return error.CorruptStore;
            if (level.number) |number| if (!std.math.isFinite(number)) return error.CorruptStore;
            for (c.levels[0..k]) |other| {
                if (level.number) |number| {
                    if (number == other.number.?) return error.CorruptStore;
                } else if (std.mem.eql(u8, std.mem.trimEnd(u8, level.text.?, " "), std.mem.trimEnd(u8, other.text.?, " "))) return error.CorruptStore;
            }
        }
    }
    for (m.covariates, 0..) |v, i| {
        if (!nameValid(v.name, 32) or !std.math.isFinite(v.mean)) return error.CorruptStore;
        for (m.covariates[0..i]) |other| if (eq(v.name, other.name)) return error.CorruptStore;
        for (m.classes) |c| if (eq(v.name, c.name)) return error.CorruptStore;
    }
    var next: usize = if (m.intercept) 1 else 0;
    for (m.effects) |effect| {
        if (effect.name.len == 0 or effect.factors.len == 0 or effect.start != next or effect.len > p - next) return error.CorruptStore;
        var width: usize = 1;
        for (effect.factors) |factor| {
            if (!nameValid(factor.name, 32)) return error.CorruptStore;
            if (factor.class_index) |ci| {
                if (ci >= m.classes.len or m.classes[ci].levels.len == 0 or !eq(factor.name, m.classes[ci].name)) return error.CorruptStore;
                width = std.math.mul(usize, width, m.classes[ci].levels.len - 1) catch return error.CorruptStore;
            } else {
                var found = false;
                for (m.covariates) |v| {
                    found = found or eq(v.name, factor.name);
                }
                if (!found) return error.CorruptStore;
            }
        }
        if (width != effect.len) return error.CorruptStore;
        next += effect.len;
    }
    if (next != p) return error.CorruptStore;
}
pub fn encode(a: A, model: Model) ![]const u8 {
    try validate(model);
    const payload = try std.json.Stringify.valueAlloc(a, model, .{});
    defer a.free(payload);
    if (payload.len > max_bytes - header_size) return error.CorruptStore;
    const result = try a.alloc(u8, header_size + payload.len);
    @memcpy(result[0..magic.len], magic);
    std.mem.writeInt(u32, result[magic.len..][0..4], 1, .little);
    std.mem.writeInt(u64, result[magic.len + 4 ..][0..8], payload.len, .little);
    std.crypto.hash.sha2.Sha256.hash(payload, result[magic.len + 12 ..][0..32], .{});
    @memcpy(result[header_size..], payload);
    return result;
}
pub fn decode(a: A, bytes: []const u8) !Model {
    if (bytes.len < header_size or bytes.len > max_bytes) return error.CorruptStore;
    if (!std.mem.eql(u8, bytes[0..magic.len], magic)) return error.IncompatibleStore;
    if (std.mem.readInt(u32, bytes[magic.len..][0..4], .little) != 1) return error.VersionMismatch;
    if (std.mem.readInt(u64, bytes[magic.len + 4 ..][0..8], .little) != bytes.len - header_size) return error.CorruptStore;
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes[header_size..], &hash, .{});
    if (!std.mem.eql(u8, &hash, bytes[magic.len + 12 ..][0..32])) return error.CorruptStore;
    // Allocate always: the restored model never borrows the file buffer/session.
    const model = std.json.parseFromSliceLeaky(Model, a, bytes[header_size..], .{ .allocate = .alloc_always }) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return error.CorruptStore;
    };
    try validate(model);
    return model;
}
fn path(cx: proc.ProcCtx, name: []const u8) diag.Error!?[]const u8 {
    const dot = std.mem.indexOfScalar(u8, name, '.').?;
    if (eq(name[0..dot], "work")) return null;
    const dir = @import("../dsfns.zig").librefDir(name[0..dot]) orelse return cx.diags.fail(error.ExecError, 0, "STORE: library {s} is not assigned", .{name[0..dot]});
    return try std.fmt.allocPrint(cx.arena, "{s}/{s}{s}", .{ dir, name[dot + 1 ..], extension });
}
fn writeAtomic(file_path: []const u8, bytes: []const u8) !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    var file = try std.Io.Dir.cwd().createFileAtomic(io, file_path, .{ .replace = true });
    defer file.deinit(io);
    try file.file.writeStreamingAll(io, bytes);
    try file.replace(io);
}
pub fn save(cx: proc.ProcCtx, original_request: Request, model: Model) diag.Error!void {
    var request = original_request;
    request.name = canonical(cx.arena, request.name) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return cx.diags.fail(error.ParseError, request.line, "STORE: invalid item-store name", .{});
    };
    if (cx.lib.readonlyOut(request.name)) return cx.diags.fail(error.ExecError, request.line, "STORE: library is read-only for {s}", .{request.name});
    const bytes = encode(cx.arena, model) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return cx.diags.fail(error.ExecError, request.line, "STORE: invalid model state ({s})", .{@errorName(err)});
    };
    if (try path(cx, request.name)) |file_path| {
        writeAtomic(file_path, bytes) catch return cx.diags.fail(error.ExecError, request.line, "STORE: cannot write {s}", .{file_path});
    } else try cx.lib.item_stores.put(cx.arena, try cx.arena.dupe(u8, request.name), bytes);
    try cx.diags.report(.note, request.line, "PROC {s} generated OpenSAS native model item store {s} (format 1; not SAS binary ITEMSTOR).", .{ model.procedure, request.name });
}
pub fn restore(cx: proc.ProcCtx, name: []const u8) diag.Error!Model {
    const key = canonical(cx.arena, name) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return cx.diags.fail(error.ParseError, 0, "STORE: invalid item-store name", .{});
    };
    const bytes = if (try path(cx, key)) |file_path|
        std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), file_path, cx.arena, .limited(max_bytes)) catch return cx.diags.fail(error.ExecError, 0, "STORE: cannot read item store {s}", .{key})
    else
        cx.lib.item_stores.get(key) orelse return cx.diags.fail(error.ExecError, 0, "STORE: item store {s} does not exist in this session", .{key});
    return decode(cx.arena, bytes) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        // A foreign binary is a compatibility gap, not an assertion that SAS's
        // file is corrupt. Native corrupt bytes/version mismatches are explicit.
        if (err == error.IncompatibleStore or err == error.IncompatibleModel or err == error.VersionMismatch) return proc.failGap(cx.diags, 0, "STORE: {s} is incompatible ({s}); only OpenSAS native format 1 GLM models are supported", .{ key, @errorName(err) });
        return cx.diags.fail(error.ExecError, 0, "STORE: corrupt item store {s}", .{key});
    };
}
/// Constructs exactly the saved basis. Unknown/missing values produce a
/// missing prediction rather than being silently treated as a reference level.
pub fn row(a: A, m: Model, ds: *const Dataset, cells: []const Value) !?[]const f64 {
    if (cells.len != ds.columns.items.len) return error.InvalidRow;
    const class_levels = try a.alloc(usize, m.classes.len);
    // Validate even zero-width CLASS effects (one observed level).
    for (m.classes, class_levels, 0..) |c, *selected, class_index| {
        var used = false;
        for (m.effects) |effect| for (effect.factors) |factor| {
            used = used or (factor.class_index != null and factor.class_index.? == class_index);
        };
        if (!used) continue;
        const ci = ds.indexOf(c.name) orelse return error.MissingVariable;
        const value = cells[ci];
        if (value.isMissing()) return null;
        var found: ?usize = null;
        for (c.levels, 0..) |level, l| {
            const raw: Value = if (level.number) |n| .{ .num = n } else .{ .str = level.text.? };
            if (std.meta.activeTag(raw) != std.meta.activeTag(value)) return error.VariableTypeMismatch;
            if (proc.cmpValue(raw, value) == .eq) {
                found = l;
                break;
            }
        }
        selected.* = found orelse return null;
    }
    const x = try a.alloc(f64, m.coefficients.len);
    @memset(x, 0);
    if (m.intercept) x[0] = 1;
    for (m.effects) |effect| {
        for (0..effect.len) |j| {
            var radix = j;
            var product: f64 = 1;
            for (effect.factors) |factor| {
                const ci = ds.indexOf(factor.name) orelse return error.MissingVariable;
                const value = cells[ci];
                if (value.isMissing()) return null;
                if (factor.class_index) |k| {
                    const levels = m.classes[k].levels;
                    const l = class_levels[k];
                    const term = radix % (levels.len - 1);
                    radix /= levels.len - 1;
                    product *= if (l == levels.len - 1) @as(f64, -1) else if (l == term) 1 else 0;
                } else {
                    if (value != .num) return error.VariableTypeMismatch;
                    if (!std.math.isFinite(value.num)) return null;
                    product *= value.num;
                }
            }
            if (!std.math.isFinite(product)) return null;
            x[effect.start + j] = product;
        }
    }
    return x;
}
pub const Prediction = struct { estimate: f64, variance: f64 };
pub fn evaluate(m: Model, x: []const f64) !Prediction {
    const p = m.coefficients.len;
    if (x.len != p) return error.InvalidFunction;
    var estimate: f64 = 0;
    var variance: f64 = 0;
    for (x, 0..) |v, j| {
        if (!std.math.isFinite(v)) return error.InvalidFunction;
        estimate += v * m.coefficients[j];
        for (x, 0..) |u, k| variance += v * m.covariance[j * p + k] * u;
    }
    if (!std.math.isFinite(estimate) or !std.math.isFinite(variance) or variance < -1e-10) return error.InvalidFunction;
    return .{ .estimate = estimate, .variance = @max(0, variance) };
}

test {
    _ = @import("store_tests.zig");
}
