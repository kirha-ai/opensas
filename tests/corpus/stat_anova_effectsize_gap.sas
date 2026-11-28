/* expect-rc: 2 */
/* STAT-ANOVA-003 loud gap: MODEL / EFFECTSIZE (S154 p.1129) is valid SAS but
 * its effect-size tables are not implemented; nothing may print. */
data n; input A y @@; datalines;
1 10 1 12 1 15 2 20 2 18 2 22
;
proc anova data=n; class A; model y = A / effectsize; run;
