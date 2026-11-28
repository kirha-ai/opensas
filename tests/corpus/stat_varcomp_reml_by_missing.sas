/* expect-rc: 2
 * STAT-VARCOMP-001: BY groups and missing values. The Hemmerle and Hartley
 * (1973) data of the guide's Example 130.1 (PDF p.10730) form two BY groups;
 * group 1 adds one observation with a missing response and one with a
 * missing CLASS value, which are read but not used (Missing Values, p.10721).
 * Bar notation a|b with FIXED=1 makes a fixed and b, a*b random; Var(a*b)
 * starts at zero and re-enters. Expected values: guide Output 130.1.4.
 * The REML Iterations table is a loud D-009 gap (rc 2).
 * Strict equality with the guide is FALSE for two covariance cells: SAS
 * prints the covariance at its EPSILON=1E-8 stopping iterate, opensas at
 * the optimum. Tolerances are the derived bound sum_k |dCov/dtheta_k|
 * sqrt(eps Cov_kk) plus half a print unit (2510.53 -> 2511 for Var(b),
 * 0.15419 -> 0.155 for Var(b) x Var(Error)), computed and asserted in the
 * Zig test "STAT-VARCOMP-001 Output 130.1.4 covariance" in
 * src/stat/varcomp_fit.zig. The Var(b) x Var(Error) residual (1.9E-5) is not
 * explained by the stopping point.
 */
data a;
input grp a b y @@;
datalines;
1 1 1 237   1 1 1 254   1 1 1 246   1 1 2 178   1 1 2 179
1 2 1 208   1 2 1 178   1 2 1 187   1 2 2 146   1 2 2 145   1 2 2 141
1 3 1 186   1 3 1 183   1 3 2 142   1 3 2 125   1 3 2 136
1 3 2 .     1 . 1 150
2 1 1 237   2 1 1 254   2 1 1 246   2 1 2 178   2 1 2 179
2 2 1 208   2 2 1 178   2 2 1 187   2 2 2 146   2 2 2 145   2 2 2 141
2 3 1 186   2 3 1 183   2 3 2 142   2 3 2 125   2 3 2 136
;
proc varcomp method=reml data=a;
by grp;
class a b;
model y=a|b / fixed=1;
run;
