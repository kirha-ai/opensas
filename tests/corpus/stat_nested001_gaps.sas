/* expect-rc: 2
 * STAT-NESTED-001: valid PROC NESTED requests outside the verified scope
 * must fail visibly with no listing: a CLASS variable name longer than 8
 * characters (SAS re-flows the ANOVA headers; layout owned by
 * STAT-NESTED-005). The degenerate designs formerly listed here (a repeated
 * CLASS variable, zero mean squares from a BY variable in the default VAR
 * list) are implemented by STAT-NESTED-004 (stat_nested004_* fixtures).
 * Invented data.
 */
options nosyntaxcheck;
data s; input longclass9 b y @@; datalines;
2 1 3 1 1 5 1 2 4 1 2 8 2 1 6 2 1 7 2 2 2 2 2 4
;
proc nested data=s; class longclass9 b; var y; run;
