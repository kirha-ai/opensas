//! STAT-ORTHOREG-001 kernel and cell-format tests (no spawned process).
const std = @import("std");
const o = @import("orthoreg.zig");

test "STAT-ORTHOREG-001 BESTD18.9 and BESTD12.9 cells match SAS PUT output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Expected strings: SAS 9.4 PUT(x, BESTD18.9) / PUT(x, BESTD12.9).
    const c18 = [_]struct { f64, []const u8 }{
        .{ 1.2345678901234567e-9, "1.2345678901235E-9" }, .{ 1.2345678901234567e-7, "0.000000123456789" },
        .{ 1.2345678901234567e-5, "0.000012345678901" },  .{ 1.2345678901234567e-4, "0.000123456789" },
        .{ 1.2345678901234567, "1.234567890123" },          .{ 1234.5678901234567, "1234.567890123450" },
        .{ 12345.678901234567, "12345.67890" },             .{ 123456789.01234567, "123456789.01235" },
        .{ 12345678901.234567, "12345678901.23450" },       .{ -1.9490713904123456e-9, "-1.949071390412E-9" },
        .{ -1949.0713904123456, "-1949.071390412340" },    .{ -0.5, "-0.500000000000" },
        .{ 185008826, "185008826" },                        .{ 185008826.0000001, "185008826.00000" },
        .{ 0, "0" },
    };
    for (c18) |c| try std.testing.expectEqualStrings(c[1], try o.bestd(a, c[0], 18));
    const c12 = [_]struct { f64, []const u8 }{
        .{ 1.2345678901234567e-6, "1.2345679E-6" }, .{ -1.9490713904123456e-9, "-1.949071E-9" },
        .{ 1.2345678901234567e-5, "0.0000123457" }, .{ 0.12345678901234567, "0.123456789" },
        .{ 0.012345678901234567, "0.0123456789" },  .{ -0.019490713904123456, "-0.019490714" },
        .{ 1.2345678901234567, "1.234567890" },     .{ 12345.678901234567, "12345.67890" },
        .{ 123456789.01234567, "123456789.0" },     .{ 1234567890.1234567, "1234567890" },
        .{ 12345678901.234567, "12345678901" },     .{ -19490713904.123456, "-19490713904" },
        .{ 185008826.0000001, "185008826.0" },
    };
    for (c12) |c| try std.testing.expectEqualStrings(c[1], try o.bestd(a, c[0], 12));
}

test "STAT-ORTHOREG-001 Givens fit reproduces a hand-solved weighted line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // x = 0,1,2,3; y = 1,3,2,5; w = 1,2,1,1. Hand solution of the weighted
    // normal equations: S_w=5, S_wx=7, S_wxx=15, S_wy=14, S_wxy=25 →
    // slope = (5*25-7*14)/(5*15-49) = 27/26, intercept = (14-7*27/26)/5 = 35/26.
    const rows = [_][]const f64{ &.{ 1, 0 }, &.{ 1, 1 }, &.{ 1, 2 }, &.{ 1, 3 } };
    const f = try o.fitGivens(a, &rows, &.{ 1, 3, 2, 5 }, &.{ 1, 2, 1, 1 }, 1e-12);
    try std.testing.expectApproxEqRel(27.0 / 26.0, f.beta[1], 1e-14);
    try std.testing.expectApproxEqRel(35.0 / 26.0, f.beta[0], 1e-14);
    // SSE = sum w (y - yhat)^2; SSM = weighted corrected SS - SSE.
    var sse: f64 = 0;
    for (rows, [_]f64{ 1, 3, 2, 5 }, [_]f64{ 1, 2, 1, 1 }) |r, y, w| {
        const e = y - (f.beta[0] + f.beta[1] * r[1]);
        sse += w * e * e;
    }
    try std.testing.expectApproxEqRel(sse, f.sse, 1e-12);
    try std.testing.expectApproxEqRel(83.0 / 26.0, f.sse, 1e-14);
    const css = (1.0 + 18.0 + 4.0 + 25.0) - 14.0 * 14.0 / 5.0; // 44/5
    try std.testing.expectApproxEqRel(css - sse, f.ssm, 1e-12);
    try std.testing.expectEqual(@as(usize, 2), f.df_error);
    // Var(slope) = MSE * S_w / det.
    const mse = sse / 2.0;
    try std.testing.expectApproxEqRel(@sqrt(mse * 5.0 / 26.0), f.se[1], 1e-12);
    try std.testing.expectError(error.Singular, o.fitGivens(a, &[_][]const f64{ &.{ 1, 2 }, &.{ 1, 2 }, &.{ 1, 2 } }, &.{ 1, 2, 3 }, &.{ 1, 1, 1 }, 1e-12));
}

test "STAT-ORTHOREG-001 Longley cells: opensas vs SAS vs exact least squares" {
    // Justifies the four estimate cells where tests/corpus/stat_orthoreg_
    // {longley,by}.txt differ from the SAS 9.4 reference listing.
    //
    // Exact: the least-squares solution of the double-precision quadratic
    // Longley design (each x and x*x rounded to f64, as SAS reads/computes
    // them), solved in exact rational arithmetic (Python fractions.Fraction,
    // Gauss-Jordan on X'X | X'y, printed to 30 digits) — a different method
    // from the f128 Givens fit under test.
    // Bound: first-order componentwise (Skeel) condition of beta_k under
    // relative data perturbations of size u = 2^-53, cond_k = (sum_o
    // |X+_ko y_o| + sum_oj |X+_ko| |x_oj| |beta_j|) / |beta_k|, computed with
    // the same exact X+ = (X'X)^-1 X'. Any backward-stable double-precision
    // solver may land within cond_k * u of the exact solution (residual term
    // neglected, first order); SAS's printed cells lie well inside it, so the
    // SAS digits are an admissible double-precision answer, not a better one.
    // Strict inequality disclosed: SAS's printed cell != the exact solution in
    // the same format, for all four cells; opensas's cell == it.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const raw = [16][7]f64{
        .{ 60323, 83.0, 234289, 2356, 1590, 107608, 1947 }, .{ 61122, 88.5, 259426, 2325, 1456, 108632, 1948 },
        .{ 60171, 88.2, 258054, 3682, 1616, 109773, 1949 }, .{ 61187, 89.5, 284599, 3351, 1650, 110929, 1950 },
        .{ 63221, 96.2, 328975, 2099, 3099, 112075, 1951 }, .{ 63639, 98.1, 346999, 1932, 3594, 113270, 1952 },
        .{ 64989, 99.0, 365385, 1870, 3547, 115094, 1953 }, .{ 63761, 100.0, 363112, 3578, 3350, 116219, 1954 },
        .{ 66019, 101.2, 397469, 2904, 3048, 117388, 1955 }, .{ 67857, 104.6, 419180, 2822, 2857, 118734, 1956 },
        .{ 68169, 108.4, 442769, 2936, 2798, 120445, 1957 }, .{ 66513, 110.8, 444546, 4681, 2637, 121950, 1958 },
        .{ 68655, 112.6, 482704, 3813, 2552, 123366, 1959 }, .{ 69564, 114.2, 502601, 3931, 2514, 125368, 1960 },
        .{ 69331, 115.7, 518173, 4806, 2572, 127852, 1961 }, .{ 70551, 116.9, 554894, 4007, 2827, 130081, 1962 },
    };
    var rows: [16][]const f64 = undefined;
    var y: [16]f64 = undefined;
    const w = [_]f64{1} ** 16;
    for (raw, 0..) |r, ob| {
        const x = try a.alloc(f64, 13);
        x[0] = 1;
        for (0..6) |v| {
            x[1 + 2 * v] = r[1 + v];
            x[2 + 2 * v] = r[1 + v] * r[1 + v];
        }
        rows[ob] = x;
        y[ob] = r[0];
    }
    const f = try o.fitGivens(a, &rows, &y, &w, 1e-12);
    const u = std.math.pow(f64, 2, -53);
    const Cell = struct { k: usize, exact: f64, cond: f64, sas: []const u8, ours: []const u8 };
    const cells = [_]Cell{
        .{ .k = 1, .exact = 1324.50679362472876759382097167, .cond = 591.0 + 7.079e6, .sas = "1324.506793624790", .ours = "1324.506793624720" },
        .{ .k = 4, .exact = 3.13695692862161322641731613675e-8, .cond = 2384.0 + 2.849e7, .sas = "3.1369569286211E-8", .ours = "3.1369569286216E-8" },
        .{ .k = 7, .exact = 4.91162014560820710888485751767, .cond = 363.4 + 4.310e6, .sas = "4.911620145609", .ours = "4.911620145608" },
        .{ .k = 12, .exact = 50.8067603538259464476943822072, .cond = 726.8 + 8.577e6, .sas = "50.806760353824", .ours = "50.806760353826" },
    };
    for (cells) |c| {
        // opensas: the f128 Givens estimate agrees with the exact solution to
        // double rounding, and prints exactly the exact solution's cell.
        try std.testing.expect(@abs(f.beta[c.k] - c.exact) <= 4 * u * @abs(c.exact));
        try std.testing.expectEqualStrings(c.ours, try o.bestd(a, f.beta[c.k], 18));
        try std.testing.expectEqualStrings(c.ours, try o.bestd(a, c.exact, 18));
        // SAS: differs from the exact cell (strict), but within the derived bound.
        try std.testing.expect(!std.mem.eql(u8, c.sas, c.ours));
        const sas = try std.fmt.parseFloat(f64, c.sas);
        const rel = @abs(sas - c.exact) / @abs(c.exact);
        try std.testing.expect(rel > 0 and rel <= c.cond * u);
        // ... and the observed SAS deviation (<= 2e-13) is far below the bound.
        try std.testing.expect(rel < 2e-13);
    }
}
