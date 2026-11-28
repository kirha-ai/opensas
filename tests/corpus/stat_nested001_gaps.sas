/* expect-rc: 2
 * STAT-NESTED-001: valid PROC NESTED requests outside the verified scope
 * must fail visibly with no listing: an unbalanced design (STAT-NESTED-003,
 * here produced by unsorted CLASS data, whose runs SAS treats as new levels)
 * and the analysis of covariation for two VAR variables without AOV
 * (STAT-NESTED-003). Invented data.
 */
options nosyntaxcheck;
data s; input a b y z @@; datalines;
2 1 3 1 1 1 5 2 1 2 4 4 1 2 8 3 2 1 6 5 2 1 7 7 2 2 2 6 2 2 4 9
;
proc nested data=s; class a b; var y; run;
data t; set s; if _n_ > 1; run;
proc nested data=t; class a b; var y z; run;
