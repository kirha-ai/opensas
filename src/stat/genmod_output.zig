//! PROC GENMOD OUTPUT statement statistics (SAS/STAT 15.4 ch.51, STAT-GENMOD-018)
//! for the model class genmod_fit.zig fits: Normal response, identity or log
//! link, no WEIGHT/FREQ/OFFSET (prior weight w = 1, variance function V = 1).
//!
//! Definitions ("Predicted Values of the Mean", "Residuals", "H | LEVERAGE"),
//! with phi = scale^2 the dispersion and g the link:
//!   XBETA     eta = x'beta                 PRED      mu = g^-1(eta)
//!   STDXBETA  s   = sqrt(x' Sigma x)       LOWER/UPPER  g^-1(eta -/+ z s)
//!   RESRAW    r   = y - mu
//!   RESCHI    r sqrt(w / V(mu))                        (= r here)
//!   RESDEV    sign(r) sqrt(d), d = (y-mu)^2 for Normal (= r here)
//!   we        = w / (phi V(mu) g'(mu)^2);  h = diag(We^.5 X (X'We X)^-1 X' We^.5)
//!   STDRESCHI r / sqrt(v (1-h)), v = phi V / w
//!   STDRESDEV sign(r) sqrt(d) / sqrt(phi (1-h))
//!   RESLIK    sign(r) sqrt((1-h) STDRESDEV^2 + h STDRESCHI^2)
//! phi cancels in h, so the leverage weight used here is 1/g'(mu)^2.
//!
//! ponytail: HESSWGT, the case-deletion keywords, PZERO and the GEE keywords
//! are loud gaps in genmod.zig — nothing here computes them.
const std = @import("std");
const fit = @import("genmod_fit.zig");
const A = std.mem.Allocator;

pub const Kind = enum { pred, xbeta, stdxbeta, lower, upper, resraw, reschi, resdev, stdreschi, stdresdev, reslik, leverage };
pub const Item = struct { kind: Kind, name: []const u8 };
pub const Request = struct { name: []const u8, items: []const Item = &.{} };

/// Keyword spellings of p.3557 for the statistics computed here.
pub fn kind(word: []const u8) ?Kind {
    const eq = std.ascii.eqlIgnoreCase;
    const table = [_]struct { []const u8, Kind }{
        .{ "predicted", .pred }, .{ "pred", .pred },         .{ "prob", .pred },           .{ "p", .pred },
        .{ "xbeta", .xbeta },    .{ "stdxbeta", .stdxbeta }, .{ "lower", .lower },         .{ "l", .lower },
        .{ "upper", .upper },    .{ "u", .upper },           .{ "resraw", .resraw },       .{ "reschi", .reschi },
        .{ "resdev", .resdev },  .{ "stdreschi", .stdreschi }, .{ "stdresdev", .stdresdev }, .{ "reslik", .reslik },
        .{ "h", .leverage },     .{ "leverage", .leverage },
    };
    for (table) |entry| if (eq(word, entry[0])) return entry[1];
    return null;
}

/// Keywords the section documents that are not computed here.
pub fn documentedGap(word: []const u8) bool {
    for ([_][]const u8{ "dfbeta", "dbeta", "dfbetas", "dbetas", "dobs", "cookd", "cooksd", "hesswgt", "pzero", "ch", "clusterh", "cleverage", "cluster", "dcls", "clustercookd", "clustercooksd", "dfbetac", "dbetac", "dfbetacs", "dbetacs", "mcls", "clusterdfit" }) |v|
        if (std.ascii.eqlIgnoreCase(word, v)) return true;
    return false;
}

fn dmu(link: fit.Link, mu: f64) f64 {
    // d mu / d eta = 1 / g'(mu).
    return switch (link) {
        .identity => 1,
        .log => mu,
    };
}

fn inverse(link: fit.Link, e: f64) f64 {
    return switch (link) {
        .identity => e,
        .log => @exp(e),
    };
}

/// Leverages of the fitted observations. `x` is the n*p row-major design that
/// was fitted, `mu` the fitted means. Null when X'WeX is not positive definite.
pub fn leverages(a: A, x: []const f64, mu: []const f64, p: usize, link: fit.Link) !?[]f64 {
    const m = try a.alloc(f64, p * p);
    @memset(m, 0);
    for (mu, 0..) |mi, i| {
        const w = dmu(link, mi) * dmu(link, mi);
        for (0..p) |j| for (0..p) |k| {
            m[j * p + k] += w * x[i * p + j] * x[i * p + k];
        };
    }
    if (!fit.cholesky(m, p)) return null;
    const h = try a.alloc(f64, mu.len);
    const v = try a.alloc(f64, p);
    for (mu, 0..) |mi, i| {
        @memcpy(v, x[i * p ..][0..p]);
        fit.choleskySolve(m, p, v);
        var q: f64 = 0;
        for (0..p) |j| q += x[i * p + j] * v[j];
        h[i] = dmu(link, mi) * dmu(link, mi) * q;
    }
    return h;
}

pub const Row = struct {
    /// Design row including the intercept; null when a covariate is missing.
    x: ?[]const f64,
    /// Response; NaN when missing.
    y: f64,
    /// Leverage; null when the observation was not used in the fit.
    h: ?f64,
};

const nan = std.math.nan(f64);

/// One statistic for one observation. `z` is the normal quantile for the
/// confidence limits. NaN is the SAS numeric missing value.
pub fn value(k: Kind, row: Row, r: fit.Fit, link: fit.Link, z: f64) f64 {
    const x = row.x orelse return nan;
    var eta: f64 = 0;
    for (x, r.beta) |xv, bv| eta += xv * bv;
    const mu = inverse(link, eta);
    switch (k) {
        .xbeta => return eta,
        .pred => return mu,
        .stdxbeta, .lower, .upper => {
            var q: f64 = 0;
            for (0..r.p) |j| for (0..r.p) |l| {
                q += x[j] * r.cov[j * r.p + l] * x[l];
            };
            const s = @sqrt(q);
            return switch (k) {
                .stdxbeta => s,
                .lower => inverse(link, eta - z * s),
                else => inverse(link, eta + z * s),
            };
        },
        else => {},
    }
    const h = row.h orelse return nan;
    if (std.math.isNan(row.y)) return nan;
    const raw = row.y - mu;
    const phi = r.scale * r.scale;
    // Normal: V = 1, w = 1, d = raw^2, so sign(raw) sqrt(d) = raw.
    const standardized = raw / @sqrt(phi * (1 - h));
    return switch (k) {
        .resraw, .reschi, .resdev => raw,
        .stdreschi, .stdresdev => standardized,
        .reslik => std.math.sign(raw) * @sqrt((1 - h) * standardized * standardized + h * standardized * standardized),
        .leverage => h,
        else => unreachable,
    };
}

test {
    _ = @import("genmod_output_tests.zig");
}
