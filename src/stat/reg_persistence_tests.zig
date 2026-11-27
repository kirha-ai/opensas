//! Durable REG numerical contracts. References use exact rational source data,
//! never production output. See tests/fixtures/stat/reg/contracts.md.
const std = @import("std");
const reg = @import("reg.zig");
const qr = @import("reg_fit.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const Value = @import("../value.zig").Value;
const A = std.mem.Allocator;

// Cross-reduced exact fractions suffice for the tiny integer/decimal designs.
// Overflow is checked by Zig; no approximate solve can pass as an exact one.
const Q = struct {
    n: i256 = 0,
    d: i256 = 1,
    fn make(n: i256, d: i256) Q {
        std.debug.assert(d != 0);
        const g: i256 = @intCast(std.math.gcd(@abs(n), @abs(d)));
        const sign: i256 = if (d < 0) -1 else 1;
        return .{ .n = @divExact(n, g) * sign, .d = @divExact(d, g) * sign };
    }
    fn add(a: Q, b: Q) Q {
        const g: i256 = @intCast(std.math.gcd(@abs(a.d), @abs(b.d)));
        return make(a.n * @divExact(b.d, g) + b.n * @divExact(a.d, g), a.d * @divExact(b.d, g));
    }
    fn neg(a: Q) Q {
        return .{ .n = -a.n, .d = a.d };
    }
    fn sub(a: Q, b: Q) Q {
        return a.add(b.neg());
    }
    fn mul(a: Q, b: Q) Q {
        const g: i256 = @intCast(std.math.gcd(@abs(a.n), @abs(b.d)));
        const h: i256 = @intCast(std.math.gcd(@abs(b.n), @abs(a.d)));
        return make(@divExact(a.n, g) * @divExact(b.n, h), @divExact(a.d, h) * @divExact(b.d, g));
    }
    fn div(a: Q, b: Q) Q {
        return a.mul(make(b.d, b.n));
    }
    fn integerFloat(n: i256) f128 {
        const magnitude = @abs(n);
        const high: u128 = @intCast(magnitude >> 128);
        const low: u128 = @truncate(magnitude);
        const value = @as(f128, @floatFromInt(high)) * 0x1p128 + @as(f128, @floatFromInt(low));
        return if (n < 0) -value else value;
    }
    fn f(a: Q) f128 {
        return integerFloat(a.n) / integerFloat(a.d);
    }
};
fn gamma(k: usize) f128 {
    const v = @as(f128, @floatFromInt(k)) * 0x1p-53;
    return v / (1 - v);
}
fn read(a: A, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(1 << 20));
}
fn datalines(source: []const u8) ![]const u8 {
    const begin = (std.mem.indexOf(u8, source, "datalines;") orelse return error.MissingData) + 10;
    const end = std.mem.indexOfScalarPos(u8, source, begin, ';') orelse return error.MissingData;
    return source[begin..end];
}
fn inverse(matrix: [3][3]Q, p: usize) [3][3]Q {
    var m = matrix;
    var g = [_][3]Q{.{ .{}, .{}, .{} }} ** 3;
    for (0..p) |i| g[i][i] = Q.make(1, 1);
    for (0..p) |j| {
        var pivot = j;
        while (m[pivot][j].n == 0) : (pivot += 1) std.debug.assert(pivot + 1 < p);
        std.mem.swap([3]Q, &m[j], &m[pivot]);
        std.mem.swap([3]Q, &g[j], &g[pivot]);
        const scale = m[j][j];
        for (0..p) |k| {
            m[j][k] = m[j][k].div(scale);
            g[j][k] = g[j][k].div(scale);
        }
        for (0..p) |i| {
            if (i == j) continue;
            const factor = m[i][j];
            for (0..p) |k| {
                m[i][k] = m[i][k].sub(factor.mul(m[j][k]));
                g[i][k] = g[i][k].sub(factor.mul(g[j][k]));
            }
        }
    }
    return g;
}

test "REG persistence exact rational residual contract and seven corruption controls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try read(a, "tests/corpus/persist_reg_population.sas");
    // Verify both persisted CLI specifications exempt exactly these fields,
    // in the correct dependent/model/output-statistics context, and nothing else.
    for ([_][]const u8{ "tests/corpus/persist_reg_population.txt", "tests/corpus/persist_reg_reg001_statement_by.txt" }) |path| {
        const specification = try read(a, path);
        const tail = specification[std.mem.indexOf(u8, specification, "words ").? + 6 ..];
        const fields = try tokenize(a, tail[0..std.mem.indexOfScalar(u8, tail, '\n').?]);
        var model: []const u8 = "";
        var dependent: []const u8 = "";
        var statistics = false;
        var sums: usize = 0;
        var exemptions: usize = 0;
        for (fields, 0..) |field, i| {
            if (std.mem.eql(u8, field, "Model:")) {
                model = fields[i + 1];
                statistics = false;
            }
            if (std.mem.eql(u8, field, "Dependent") and std.mem.eql(u8, fields[i + 1], "Variable:")) dependent = fields[i + 2];
            if (std.mem.eql(u8, field, "Output") and std.mem.eql(u8, fields[i + 1], "Statistics")) statistics = true;
            if (std.mem.eql(u8, field, "Sum") and std.mem.eql(u8, fields[i + 1], "of") and std.mem.eql(u8, fields[i + 2], "Residuals")) {
                try std.testing.expect(sums < 2 and statistics);
                try std.testing.expectEqualStrings("Population", dependent);
                try std.testing.expectEqualStrings(if (sums == 0) "MODEL1" else "MODEL1.1", model);
                try std.testing.expectEqualStrings(if (sums == 0) "0~7.261130843592319e-11" else "0~1.7845359484002278e-09", fields[i + 3]);
                sums += 1;
            }
            if (std.mem.indexOfScalar(u8, field, '~') != null) exemptions += 1;
        }
        try std.testing.expectEqual(@as(usize, 2), sums);
        try std.testing.expectEqual(sums, exemptions);
    }
    // Pin the source transformations used by the independent data parser.
    for ([_][]const u8{ "retain Year 1780;", "Year = Year+10;", "YearSq = Year *Year;", "Population = Population/1000;" }) |s|
        try std.testing.expect(std.mem.indexOf(u8, source, s) != null);
    var y: [22]Q = undefined;
    var values = std.mem.tokenizeAny(u8, try datalines(source), " \r\n\t");
    for (&y) |*v| v.* = Q.make(try std.fmt.parseInt(i256, values.next().?, 10), 1000);
    try std.testing.expect(values.next() == null);
    for ([_]usize{ 2, 3 }, 0..) |p, order| {
        var x: [22][3]Q = undefined;
        var matrix = [_][3]Q{.{ .{}, .{}, .{} }} ** 3;
        var rhs = [_]Q{.{}} ** 3;
        for (&x, 0..) |*row, i| {
            const year: i256 = @intCast(1790 + 10 * i);
            row.* = .{ Q.make(1, 1), Q.make(year, 1), Q.make(year * year, 1) };
            for (0..p) |j| {
                rhs[j] = rhs[j].add(row[j].mul(y[i]));
                for (0..p) |k| matrix[j][k] = matrix[j][k].add(row[j].mul(row[k]));
            }
        }
        const g = inverse(matrix, p);
        var beta = [_]Q{.{}} ** 3;
        for (0..p) |j| for (0..p) |k| {
            beta[j] = beta[j].add(g[j][k].mul(rhs[k]));
        };
        var orthogonal = [_]Q{.{}} ** 3;
        var envelope: f128 = 0;
        var residual_l1: f128 = 0;
        var xf: [66]f64 = undefined;
        var yf: [22]f64 = undefined;
        for (x, y, 0..) |row, value, i| {
            var r = value;
            envelope += @abs(value.f());
            for (0..p) |j| {
                const term = row[j].mul(beta[j]);
                r = r.sub(term);
                envelope += @abs(term.f());
                xf[i * p + j] = @floatCast(row[j].f());
            }
            yf[i] = @floatCast(value.f());
            residual_l1 += @abs(r.f());
            for (0..p) |j| orthogonal[j] = orthogonal[j].add(row[j].mul(r));
        }
        for (orthogonal[0..p]) |q| try std.testing.expectEqual(@as(i256, 0), q.n);
        const evaluation = gamma(2 * p + 2) * envelope;
        const bound = evaluation + gamma(21) * (residual_l1 + evaluation);
        const persisted = [_]f128{ 7.261130843592319e-11, 1.7845359484002278e-9 };
        try std.testing.expectApproxEqRel(bound, persisted[order], 1e-15);
        var fit = try qr.fit(a, xf[0 .. 22 * p], &yf, 22, p, null);
        defer fit.deinit(a);
        var sum: f128 = 0;
        for (fit.residuals) |r| sum += r;
        try std.testing.expect(@abs(sum) <= bound);
    }
    const spec = try read(a, "tests/corpus/persist_reg_population.txt");
    const words = spec[std.mem.indexOf(u8, spec, "words ").? + 6 ..];
    const expected = words[0..std.mem.indexOfScalar(u8, words, '\n').?];
    var baseline: std.ArrayList(u8) = .empty;
    var tokens = std.mem.tokenizeScalar(u8, expected, ' ');
    while (tokens.next()) |t| {
        if (baseline.items.len > 0) try baseline.append(a, ' ');
        try baseline.appendSlice(a, if (std.mem.indexOfScalar(u8, t, '~')) |n| t[0..n] else t);
    }
    try std.testing.expect(matches(expected, baseline.items));
    const mutations = [_][2][]const u8{
        .{ "Sum of Residuals 0", "Sum of Residuals 1" },
        .{ "Sum of Residuals 0", "" },
        .{ "Intercept", "Intercept_changed" },
        .{ "7193.24912", "7193.24913" },
        .{ "Analysis of Variance", "" },
        .{ "Sum of Residuals 0", "Sum of Residuals ." },
    };
    for (mutations) |m| {
        try std.testing.expect(std.mem.indexOf(u8, baseline.items, m[0]) != null);
        const mutant = try std.mem.replaceOwned(u8, a, baseline.items, m[0], m[1]);
        try std.testing.expect(!matches(expected, mutant));
    }
    try std.testing.expect(!matches(expected, try std.fmt.allocPrint(a, "{s} Sum of Residuals 0", .{baseline.items})));
}

// Independent strict token comparator for the mutation controls. The corpus
// runner separately exercises its own words/fieldMatches implementation.
fn matches(expected: []const u8, actual: []const u8) bool {
    var es = std.mem.tokenizeAny(u8, expected, " \t\r\n\x0c");
    var as = std.mem.tokenizeAny(u8, actual, " \t\r\n\x0c");
    while (es.next()) |e| {
        const v = as.next() orelse return false;
        if (std.mem.indexOfScalar(u8, e, '~')) |n| {
            const target = std.fmt.parseFloat(f128, e[0..n]) catch return false;
            const bound = std.fmt.parseFloat(f128, e[n + 1 ..]) catch return false;
            const value = std.fmt.parseFloat(f128, v) catch return false;
            if (!std.math.isFinite(value) or @abs(value - target) > bound) return false;
        } else if (!std.mem.eql(u8, e, v)) return false;
    }
    return as.next() == null;
}

const Common = struct {
    matrix: [3][3]Q,
    rhs: [3]Q,
    beta: [3]Q,
    cov: [3][3]Q,
    mse: Q,
    normal_budget: [3]f128,
    covariance_residual: [3][3]f128,
    mse_budget: f128,
    target: [4][4]f128, // rows PARMS/COV; columns RMSE, Intercept, x, z
    budget: [4][4]f128,
};

fn commonReference(x: [12][3]Q, y: [12]Q, w: [12]Q) !Common {
    const p = 3;
    const n = 12;
    var result: Common = undefined;
    result.matrix = [_][3]Q{.{ .{}, .{}, .{} }} ** 3;
    result.rhs = [_]Q{.{}} ** 3;
    for (x, y, w) |row, value, weight| for (0..p) |j| {
        result.rhs[j] = result.rhs[j].add(weight.mul(row[j]).mul(value));
        for (0..p) |k| result.matrix[j][k] = result.matrix[j][k].add(weight.mul(row[j]).mul(row[k]));
    };
    const g = inverse(result.matrix, p);
    result.beta = [_]Q{.{}} ** 3;
    for (0..p) |j| for (0..p) |k| {
        result.beta[j] = result.beta[j].add(g[j][k].mul(result.rhs[k]));
    };
    // These identities are EXACT fractions, including every inverse entry.
    for (0..p) |i| {
        var ab: Q = .{};
        for (0..p) |k| ab = ab.add(result.matrix[i][k].mul(result.beta[k]));
        try std.testing.expect(ab.sub(result.rhs[i]).n == 0);
        for (0..p) |j| {
            var ag: Q = .{};
            for (0..p) |k| ag = ag.add(result.matrix[i][k].mul(g[k][j]));
            try std.testing.expect(ag.sub(Q.make(if (i == j) 1 else 0, 1)).n == 0);
        }
    }
    var residual: [12]Q = undefined;
    var row_eval: [12]f128 = undefined;
    var sse: Q = .{};
    for (x, y, w, 0..) |row, value, weight, i| {
        var r = value;
        var envelope = @abs(value.f());
        for (0..p) |j| {
            const term = row[j].mul(result.beta[j]);
            r = r.sub(term);
            envelope += @abs(term.f());
        }
        residual[i] = r;
        row_eval[i] = gamma(6 * p + 2) * envelope;
        sse = sse.add(weight.mul(r).mul(r));
    }
    result.mse = sse.div(Q.make(n - p, 1));
    for (0..p) |i| for (0..p) |j| {
        result.cov[i][j] = result.mse.mul(g[i][j]);
    };
    // E_j budgets X'Wr; B=|G|E propagates the normal-equation defect.
    for (0..p) |j| {
        var evaluation: f128 = 0;
        var magnitude: f128 = 0;
        var exact: Q = .{};
        for (x, w, residual, row_eval) |row, weight, r, e| {
            const wx = weight.mul(row[j]);
            evaluation += @abs(wx.f()) * e;
            magnitude += @abs(wx.mul(r).f());
            exact = exact.add(wx.mul(r));
        }
        try std.testing.expectEqual(@as(i256, 0), exact.n);
        result.normal_budget[j] = evaluation + gamma(7 * n + 2) * (magnitude + evaluation);
    }
    var beta_budget = [_]f128{0} ** 3;
    for (0..p) |j| for (0..p) |k| {
        beta_budget[j] += @abs(g[j][k].f()) * result.normal_budget[k];
    };
    var quadratic: f128 = 0;
    for (0..p) |j| for (0..p) |k| {
        quadratic += beta_budget[j] * @abs(result.matrix[j][k].f()) * beta_budget[k];
    };
    var evaluation_ss: f128 = 0;
    for (x, w, residual, row_eval) |row, weight, r, e| {
        var prediction_budget: f128 = 0;
        for (0..p) |j| prediction_budget += @abs(row[j].f()) * beta_budget[j];
        evaluation_ss += weight.f() * (2 * (@abs(r.f()) + prediction_budget) * e + e * e);
    }
    const sse_budget = quadratic + evaluation_ss + gamma(8 * n + 2) * (sse.f() + quadratic + evaluation_ss);
    result.mse_budget = sse_budget / (n - p) + gamma(1) * result.mse.f();
    const rmse = @sqrt(result.mse.f());
    const rmse_budget = result.mse_budget / (rmse + @sqrt(result.mse.f() - result.mse_budget)) + gamma(1) * rmse;
    for (0..4) |i| {
        result.target[i][0] = rmse;
        result.budget[i][0] = rmse_budget;
    }
    for (0..p) |j| {
        result.target[0][j + 1] = result.beta[j].f();
        result.budget[0][j + 1] = beta_budget[j];
        for (0..p) |k| {
            var scale: f128 = if (k == j) result.mse.f() else 0;
            for (0..p) |l| scale += @abs(result.matrix[k][l].mul(result.cov[l][j]).f());
            result.covariance_residual[k][j] = gamma(6 * p + 2) * scale;
        }
        for (0..p) |i| {
            var budget = @abs(g[i][j].f()) * result.mse_budget + gamma(1) * @abs(result.cov[i][j].f());
            for (0..p) |k| budget += @abs(g[i][k].f()) * result.covariance_residual[k][j];
            result.target[i + 1][j + 1] = result.cov[i][j].f();
            result.budget[i + 1][j + 1] = budget;
        }
    }
    return result;
}

fn quantum(token: []const u8) f128 {
    const e = std.mem.indexOfAny(u8, token, "eE") orelse token.len;
    const exponent = if (e < token.len) std.fmt.parseInt(i32, token[e + 1 ..], 10) catch return std.math.inf(f128) else 0;
    const decimals: i32 = if (std.mem.indexOfScalar(u8, token[0..e], '.')) |dot| @intCast(e - dot - 1) else 0;
    var power = exponent - decimals;
    var result: f128 = 0.5;
    while (power > 0) : (power -= 1) result *= 10;
    while (power < 0) : (power += 1) result /= 10;
    return result;
}
const Cells = [4][4][]const u8;
fn commonValid(ref: Common, declared: Cells, candidate: Cells) bool {
    var nums: [4][4]f128 = undefined;
    var quanta: [4][4]f128 = undefined;
    for (0..4) |i| for (0..4) |j| {
        const v = std.fmt.parseFloat(f128, candidate[i][j]) catch return false;
        const q = quantum(declared[i][j]);
        if (!std.math.isFinite(v) or (v != ref.target[i][j] and quantum(candidate[i][j]) > q * (1 + 1e-30))) return false;
        if (@abs(v - ref.target[i][j]) > ref.budget[i][j] + q) return false;
        nums[i][j] = v;
        quanta[i][j] = q;
    };
    // Independently certify A beta=b and A C=m I using the printed values.
    // The tiny f128 evaluation error is negligible beside binary64 budgets.
    for (0..3) |i| {
        var defect = -ref.rhs[i].f();
        var bound = ref.normal_budget[i];
        for (0..3) |j| {
            defect += ref.matrix[i][j].f() * nums[0][j + 1];
            bound += @abs(ref.matrix[i][j].f()) * quanta[0][j + 1];
        }
        if (@abs(defect) > bound) return false;
        for (0..3) |j| {
            defect = if (i == j) -ref.mse.f() else 0;
            bound = ref.covariance_residual[i][j] + (if (i == j) ref.mse_budget else @as(f128, 0));
            for (0..3) |k| {
                defect += ref.matrix[i][k].f() * nums[k + 1][j + 1];
                bound += @abs(ref.matrix[i][k].f()) * quanta[k + 1][j + 1];
            }
            if (@abs(defect) > bound) return false;
        }
    }
    return true;
}
fn tokenize(a: A, text: []const u8) ![][]const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeAny(u8, text, " \r\n\t\x0c");
    while (it.next()) |t| try result.append(a, t);
    return result.items;
}

test "COMMON004 persistence BEST32 precision covariance identities and mutation controls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try read(a, "tests/corpus/persist_reg_common004_weighted_linear_moments.sas");
    const input = try tokenize(a, try datalines(source));
    try std.testing.expectEqual(@as(usize, 72), input.len);
    var x: [12][3]Q = undefined;
    var y: [12]Q = undefined;
    var w: [12]Q = undefined;
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    var ds = Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "z", "y", "weight" }) |name| _ = try ds.addColumn(name, .num);
    for (0..12) |i| {
        x[i] = .{ Q.make(1, 1), Q.make(try std.fmt.parseInt(i256, input[i * 6], 10), 1), Q.make(try std.fmt.parseInt(i256, input[i * 6 + 1], 10), 1) };
        y[i] = Q.make(try std.fmt.parseInt(i256, input[i * 6 + 2], 10), 1);
        w[i] = Q.make(try std.fmt.parseInt(i256, input[i * 6 + 4], 10), 1);
        try ds.appendRow(&.{ .{ .num = @floatCast(x[i][1].f()) }, .{ .num = @floatCast(x[i][2].f()) }, .{ .num = @floatCast(y[i].f()) }, .{ .num = @floatCast(w[i].f()) } });
    }
    const ref = try commonReference(x, y, w);
    try lib.put("sample", &ds);
    var listing: std.ArrayList(u8) = .empty;
    const start = std.mem.indexOf(u8, source, "proc reg data=sample").?;
    const end = std.mem.indexOf(u8, source[start..], "proc print").? + start;
    try reg.run(.{ .arena = a, .lib = &lib, .diags = &d }, &listing, try @import("../lexer.zig").tokenize(a, source[start..end], &d));
    try std.testing.expectEqual(@as(usize, 0), d.list.items.len);
    const expected = try tokenize(a, try read(a, "tests/fixtures/stat/reg/common004_original.txt"));
    const actual_prefix = try tokenize(a, listing.items);
    try std.testing.expectEqual(@as(usize, 94), actual_prefix.len);
    for (expected[0..94], actual_prefix) |e, v| try std.testing.expectEqualStrings(e, v);
    const est = lib.find("est").?;
    try std.testing.expectEqual(@as(usize, 4), est.rows.items.len);
    try std.testing.expectEqual(@as(usize, 9), est.columns.items.len);
    // Panel 1: six headers, PARMS has one blank NAME cell; then three COV
    // rows. Panel 2: x,z,y header and four complete rows. No tokens omitted.
    var declared: Cells = undefined;
    var actual: Cells = undefined;
    var indices: [4][4]usize = undefined;
    var offset: usize = 100;
    for (0..4) |i| {
        const width: usize = if (i == 0) 5 else 6;
        indices[i][0] = offset + width - 2;
        indices[i][1] = offset + width - 1;
        offset += width;
    }
    offset += 3;
    for (0..4) |i| {
        indices[i][2] = offset;
        indices[i][3] = offset + 1;
        offset += 3;
    }
    try std.testing.expectEqual(expected.len, offset);
    for (0..4) |i| for ([_][]const u8{ "_RMSE_", "Intercept", "x", "z" }, 0..) |name, j| {
        declared[i][j] = expected[indices[i][j]];
        actual[i][j] = std.mem.trim(u8, try @import("../format.zig").apply(a, est.rows.items[i][est.indexOf(name).?], "best32."), " ");
    };
    try std.testing.expect(commonValid(ref, declared, declared));
    try std.testing.expect(commonValid(ref, declared, actual));
    var mutant = actual;
    mutant[1][1] = "0.51268508035062";
    try std.testing.expect(!commonValid(ref, declared, mutant));
    mutant = actual;
    mutant[1][1] = "1";
    try std.testing.expect(!commonValid(ref, declared, mutant));
    // Precision may not be weakened even if rounded value is within B+q.
    mutant = actual;
    mutant[0][1] = "1.456081081081";
    try std.testing.expect(!commonValid(ref, declared, mutant));
    for (0..3) |i| for (0..3) |j| {
        mutant = actual;
        mutant[i + 1][j + 1] = "0";
        try std.testing.expect(!commonValid(ref, declared, mutant));
    };
    const spec = try read(a, "tests/corpus/persist_reg_common004_weighted_linear_moments.txt");
    const rest = spec[std.mem.indexOf(u8, spec, "words ").? + 6 ..];
    const rule = rest[0..std.mem.indexOfScalar(u8, rest, '\n').?];
    const original = try read(a, "tests/fixtures/stat/reg/common004_original.txt");
    try std.testing.expect(matches(rule, original));
    for ([_][2][]const u8{ .{ "MODEL1", "MODEL2" }, .{ "COV", "WRONG" }, .{ "COV", "" } }) |m|
        try std.testing.expect(!matches(rule, try std.mem.replaceOwned(u8, a, original, m[0], m[1])));
    // Pin every persisted tolerance to this independently rederived budget.
    const rules = try tokenize(a, rule);
    for (0..4) |i| for (0..4) |j| {
        const token = rules[indices[i][j]];
        const tilde = std.mem.indexOfScalar(u8, token, '~').?;
        const target = try std.fmt.parseFloat(f128, token[0..tilde]);
        const bound = try std.fmt.parseFloat(f128, token[tilde + 1 ..]);
        try std.testing.expectApproxEqRel(ref.target[i][j], target, 1e-30);
        try std.testing.expectApproxEqRel(ref.budget[i][j] + quantum(declared[i][j]), bound, 1e-30);
    };
}

fn numeric(ds: *const Dataset, row: usize, name: []const u8) f64 {
    return ds.rows.items[row][ds.indexOf(name).?].num;
}

test "REG005 persistence original ridge OUTEST rows and five graph data objects" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try read(a, "tests/fixtures/stat/reg/ridge_original.sas");
    const values = try tokenize(a, try datalines(source));
    try std.testing.expectEqual(@as(usize, 64), values.len);
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    var ds = Dataset.init(a, "acetyl");
    for ([_][]const u8{ "x1", "x2", "x3", "x4", "x1x2", "x1x1" }) |name| _ = try ds.addColumn(name, .num);
    for (0..16) |i| {
        var row: [6]Value = undefined;
        for (0..4) |j| row[j] = .{ .num = try std.fmt.parseFloat(f64, values[i * 4 + j]) };
        row[4] = .{ .num = row[0].num * row[1].num };
        row[5] = .{ .num = row[0].num * row[0].num };
        try ds.appendRow(&row);
    }
    try lib.put("acetyl", &ds);
    var graphics = @import("graphics_svg.zig").Session{ .arena = a, .io = std.testing.io, .diags = &d, .enabled = true };
    var listing: std.ArrayList(u8) = .empty;
    var cursor: usize = 0;
    for (0..2) |run| {
        const begin = std.mem.indexOfPos(u8, source, cursor, "proc reg ").?;
        const end = std.mem.indexOfPos(u8, source, begin, "run;").? + 4;
        cursor = end;
        try reg.run(.{ .arena = a, .lib = &lib, .diags = &d, .graphics = &graphics }, &listing, try @import("../lexer.zig").tokenize(a, source[begin..end], &d));
        const est = lib.find("b").?;
        try std.testing.expectEqual(@as(usize, if (run == 0) 23 else 12), est.rows.items.len);
        try std.testing.expectEqual(@as(usize, 13), est.columns.items.len);
        for (est.rows.items) |row| {
            try std.testing.expectEqualStrings("MODEL1", row[est.indexOf("_MODEL_").?].str);
            try std.testing.expectEqualStrings("x4", row[est.indexOf("_DEPVAR_").?].str);
            try std.testing.expectEqual(@as(f64, -1), row[est.indexOf("x4").?].num);
            try std.testing.expect(std.math.isNan(row[est.indexOf("_PCOMIT_").?].num));
        }
        try std.testing.expectEqualStrings("PARMS", est.rows.items[0][est.indexOf("_TYPE_").?].str);
        const graph = graphics.prepared.items[if (run == 0) 0 else 3].bytes;
        const mb = std.mem.indexOf(u8, graph, "<metadata>").? + 10;
        const me = std.mem.indexOf(u8, graph, "</metadata>").?;
        const json = try std.mem.replaceOwned(u8, a, graph[mb..me], "&quot;", "\"");
        const Metadata = struct { procedure: []const u8, kind: []const u8, predictors: []const []const u8, points: []const @import("reg_ridge.zig").Point, vif_log: bool, ridge_log: bool };
        const parsed = try std.json.parseFromSlice(Metadata, a, json, .{});
        const meta = parsed.value;
        try std.testing.expectEqualStrings("REG", meta.procedure);
        try std.testing.expectEqualStrings("ridge", meta.kind);
        try std.testing.expectEqual(@as(usize, 11), meta.points.len);
        try std.testing.expectEqual(run == 1, meta.vif_log);
        try std.testing.expect(!meta.ridge_log);
        const predictors = [_][]const u8{ "x1", "x2", "x3", "x1x2", "x1x1" };
        try std.testing.expectEqual(predictors.len, meta.predictors.len);
        for (predictors, meta.predictors) |want, got| try std.testing.expectEqualStrings(want, got);
        for (meta.points, 0..) |point, i| {
            const row = 1 + i * @as(usize, if (run == 0) 2 else 1) + @as(usize, if (run == 0) 1 else 0);
            try std.testing.expectApproxEqAbs(@as(f64, @floatFromInt(i)) * 0.002, point.k, 1e-17);
            try std.testing.expectEqual(point.k, numeric(est, row, "_RIDGE_"));
            try std.testing.expectEqualStrings("RIDGE", est.rows.items[row][est.indexOf("_TYPE_").?].str);
            try std.testing.expectEqual(@as(usize, 6), point.coefficients.len);
            try std.testing.expectEqual(@as(usize, 5), point.standardized.len);
            try std.testing.expectEqual(@as(usize, 5), point.vif.len);
            try std.testing.expectEqual(point.coefficients[0], numeric(est, row, "Intercept"));
            try std.testing.expectEqual(point.rmse, numeric(est, row, "_RMSE_"));
            // Independently evaluate every stored coefficient vector on source
            // rows: RMSE^2 = SSE/(16-6). This detects corrupt graph/OUTEST data.
            var sse: f128 = 0;
            for (ds.rows.items) |input| {
                var residual: f128 = input[3].num - @as(f128, point.coefficients[0]);
                for (predictors, 0..) |name, j| residual -= @as(f128, input[ds.indexOf(name).?].num) * point.coefficients[j + 1];
                sse += residual * residual;
            }
            try std.testing.expectApproxEqRel(sse, @as(f128, point.sse), 1e-10);
            try std.testing.expectApproxEqRel(@sqrt(sse / 10), @as(f128, point.rmse), 1e-10);
            for (predictors, 0..) |name, j| {
                try std.testing.expectEqual(point.coefficients[j + 1], numeric(est, row, name));
                try std.testing.expect(std.math.isFinite(point.standardized[j]) and std.math.isFinite(point.vif[j]) and point.vif[j] >= 0);
                if (run == 0) {
                    try std.testing.expectEqualStrings("RIDGEVIF", est.rows.items[row - 1][est.indexOf("_TYPE_").?].str);
                    try std.testing.expectEqual(point.vif[j], numeric(est, row - 1, name));
                    try std.testing.expect(std.math.isNan(numeric(est, row - 1, "_RMSE_")));
                }
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 0), d.list.items.len);
    try std.testing.expectEqual(@as(usize, 5), graphics.prepared.items.len);
    const kinds = [_][]const u8{ "ridge-panel", "diagnostics", "residuals", "vif", "ridge" };
    const panels = [_]usize{ 2, 9, 5, 1, 1 };
    for (graphics.prepared.items, kinds, panels) |artifact, kind, count| {
        try std.testing.expectEqualStrings(kind, artifact.kind);
        try std.testing.expectEqual(count, std.mem.count(u8, artifact.bytes, "data-panel="));
        try std.testing.expect(std.mem.startsWith(u8, artifact.bytes, "<svg "));
        try std.testing.expect(std.mem.endsWith(u8, artifact.bytes, "</svg>"));
    }
    try std.testing.expectEqual(@as(usize, 10), std.mem.count(u8, graphics.prepared.items[0].bytes, "<polyline data-series="));
    try std.testing.expectEqual(@as(usize, 80), std.mem.count(u8, graphics.prepared.items[2].bytes, "<circle data-x="));
    for (graphics.prepared.items[3..]) |graph| try std.testing.expectEqual(@as(usize, 5), std.mem.count(u8, graph.bytes, "<polyline data-series="));
}

// Independent f128 normal-equation reference, not the production augmented QR.
// Inputs are parsed as decimal f128 from the durable public example; it never
// reads the temporary reference tree. The precision budgets below are functions
// of source dimensions, crossproducts and conditioning, not observed errors.
fn inverse5(input: [5][5]f128) [5][5]f128 {
    var matrix = input;
    var inv = [_][5]f128{.{0} ** 5} ** 5;
    for (0..5) |i| inv[i][i] = 1;
    for (0..5) |j| {
        var pivot = j;
        for (j + 1..5) |i| if (@abs(matrix[i][j]) > @abs(matrix[pivot][j])) {
            pivot = i;
        };
        std.mem.swap([5]f128, &matrix[j], &matrix[pivot]);
        std.mem.swap([5]f128, &inv[j], &inv[pivot]);
        const scale = matrix[j][j];
        for (0..5) |k| {
            matrix[j][k] /= scale;
            inv[j][k] /= scale;
        }
        for (0..5) |i| {
            if (i == j) continue;
            const factor = matrix[i][j];
            for (0..5) |k| {
                matrix[i][k] -= factor * matrix[j][k];
                inv[i][k] -= factor * inv[j][k];
            }
        }
    }
    return inv;
}

fn bounded(reference: f128, actual: f64, bound: f128) !void {
    try std.testing.expect(std.math.isFinite(actual) and std.math.isFinite(bound) and bound >= 0);
    try std.testing.expect(@abs(reference - actual) <= bound);
    // A corruption larger than this independently derived accuracy budget must
    // be rejected, even where a broad fixed relative tolerance would pass.
    try std.testing.expect(@abs(reference - (reference + 4 * bound)) > bound);
}

test "REG005 entire acetylene ridge path independent normal equations and VIF covariance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const values = try tokenize(a, try datalines(try read(a, "tests/fixtures/stat/reg/ridge_original.sas")));
    var x: [16][5]f128 = undefined;
    var y: [16]f128 = undefined;
    var means = [_]f128{0} ** 5;
    var ym: f128 = 0;
    var xf: [80]f64 = undefined;
    var yf: [16]f64 = undefined;
    for (0..16) |i| {
        for (0..3) |j| x[i][j] = try std.fmt.parseFloat(f128, values[4 * i + j]);
        y[i] = try std.fmt.parseFloat(f128, values[4 * i + 3]);
        x[i][3] = x[i][0] * x[i][1];
        x[i][4] = x[i][0] * x[i][0];
        for (0..5) |j| {
            means[j] += x[i][j] / 16;
            xf[i * 5 + j] = @floatCast(x[i][j]);
        }
        ym += y[i] / 16;
        yf[i] = @floatCast(y[i]);
    }
    var scales = [_]f128{0} ** 5;
    var yss: f128 = 0;
    for (x, y) |row, value| {
        for (0..5) |j| scales[j] += (row[j] - means[j]) * (row[j] - means[j]);
        yss += (value - ym) * (value - ym);
    }
    for (&scales) |*v| v.* = @sqrt(v.*);
    const ys = @sqrt(yss);
    var c = [_][5]f128{.{0} ** 5} ** 5;
    var rhs = [_]f128{0} ** 5;
    for (x, y) |row, value| for (0..5) |j| {
        const zj = (row[j] - means[j]) / scales[j];
        rhs[j] += zj * (value - ym);
        for (0..5) |k| c[j][k] += zj * ((row[k] - means[k]) / scales[k]);
    };
    var constants: [11]f64 = undefined;
    for (&constants, 0..) |*k, i| k.* = @as(f64, @floatFromInt(i)) / 500;
    const actual = try @import("reg_ridge.zig").compute(a, &xf, &yf, 5, null, &constants, 10);
    // Binary64 acceptance contract: N accounts for centering/scaling (8np),
    // factorization/crossproducts (16p²), and final conversions (32).
    // Allow elementwise |dC|<=e (unit-norm columns), |dRHS|<=e*||yc||₂.
    // Inverse perturbations propagate through |G|, retaining conditioning.
    const e = gamma(8 * 16 * 5 + 16 * 5 * 5 + 32);
    for (actual.points, 0..) |point, index| {
        var matrix = c;
        const k = @as(f128, @floatFromInt(index)) / 500;
        for (0..5) |j| matrix[j][j] += k;
        const inv = inverse5(matrix);
        var max_row: f128 = 0;
        for (inv) |row| {
            var norm: f128 = 0;
            for (row) |v| norm += @abs(v);
            max_row = @max(max_row, norm);
        }
        const contraction = 5 * e * max_row;
        try std.testing.expect(contraction < 1);
        var g = [_]f128{0} ** 5;
        var beta: [6]f128 = undefined;
        var budget: [6]f128 = undefined;
        var dg = [_][5]f128{.{0} ** 5} ** 5;
        for (0..5) |j| for (0..5) |l| {
            g[j] += inv[j][l] * rhs[l];
            for (0..5) |m| for (0..5) |q| {
                dg[j][l] += @abs(inv[j][m]) * e * @abs(inv[q][l]) / (1 - contraction);
            };
        };
        var g_abs: f128 = 0;
        for (g) |v| g_abs += @abs(v);
        beta[0] = ym;
        budget[0] = e * @abs(ym);
        for (0..5) |j| {
            beta[j + 1] = g[j] / scales[j];
            var gamma_budget: f128 = 0;
            for (0..5) |l| gamma_budget += @abs(inv[j][l]) * e * (ys + g_abs) / (1 - contraction);
            budget[j + 1] = gamma_budget / scales[j] + e * @abs(beta[j + 1]);
            beta[0] -= means[j] * beta[j + 1];
            budget[0] += @abs(means[j]) * budget[j + 1] + e * @abs(means[j] * beta[j + 1]);
            try bounded(g[j] / ys, point.standardized[j], gamma_budget / ys + e * @abs(g[j] / ys));
            var variance: f128 = 0;
            var variance_budget: f128 = 0;
            for (0..5) |l| for (0..5) |m| {
                variance += inv[j][l] * c[l][m] * inv[m][j];
                variance_budget += (@abs(inv[j][l]) + dg[j][l]) * (@abs(c[l][m]) + e) * (@abs(inv[m][j]) + dg[m][j]) - @abs(inv[j][l] * c[l][m] * inv[m][j]);
            };
            try bounded(variance, point.vif[j], variance_budget + e * @abs(variance));
        }
        for (beta, budget, point.coefficients) |want, tolerance, got| try bounded(want, got, tolerance);
        var sse: f128 = 0;
        var sse_budget: f128 = 0;
        for (x, y) |row, value| {
            var residual = value - beta[0];
            var prediction_budget = budget[0] + e * (@abs(value) + @abs(beta[0]));
            for (0..5) |j| {
                residual -= row[j] * beta[j + 1];
                prediction_budget += @abs(row[j]) * budget[j + 1] + e * @abs(row[j] * beta[j + 1]);
            }
            sse += residual * residual;
            sse_budget += 2 * @abs(residual) * prediction_budget + prediction_budget * prediction_budget;
        }
        sse_budget += e * sse;
        try bounded(sse, point.sse, sse_budget);
        const rmse = @sqrt(sse / 10);
        try bounded(rmse, point.rmse, sse_budget / (10 * (rmse + @sqrt((sse - sse_budget) / 10))) + e * rmse);
    }
}
