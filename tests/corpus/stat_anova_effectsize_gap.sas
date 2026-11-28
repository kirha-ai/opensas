/* expect-rc: 2 */
/* STAT-ANOVA-003 loud gap: EFFECTSIZE for an F of about 3E10 (SAS prints
 * overflowed F, E-notation estimates and `.` limits; switch points not pinned).
 * The listing stops at the ERROR, before any F or effect-size number. */
data h; input g y @@; datalines;
1 1 1 1.001 1 0.999 2 100 2 100.001 2 99.999 3 200 3 200.002 3 199.998 4 300 4 300 4 300.001
;
proc anova data=h; class g; model y = g / effectsize; run;
