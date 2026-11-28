/* expect-rc: 2
 * STAT-NESTED-001: valid PROC NESTED requests outside the verified scope
 * must fail visibly with no listing: an unbalanced design (STAT-NESTED-003,
 * here produced by unsorted CLASS data, whose runs SAS treats as new levels)
 * and the analysis of covariation for two VAR variables without AOV
 * (STAT-NESTED-003); a CLASS variable listed twice, which SAS 15.4 lists
 * as a factor with zero degrees of freedom and missing cells, and a default
 * VAR list that takes in the numeric BY variable, whose zero mean squares
 * leave the F tests missing (both STAT-NESTED-004 degenerate cases).
 * Invented data.
 */
options nosyntaxcheck;
data s; input a b y z @@; datalines;
2 1 3 1 1 1 5 2 1 2 4 4 1 2 8 3 2 1 6 5 2 1 7 7 2 2 2 6 2 2 4 9
;
proc nested data=s; class a b; var y; run;
data t; set s; if _n_ > 1; run;
proc nested data=t; class a b; var y z; run;
proc nested data=s; class a b; class a; var y; run;
data v; input g a b y @@; datalines;
1 1 1 3 1 1 1 5 1 1 2 4 1 1 2 8 1 2 1 6 1 2 1 7 1 2 2 2 1 2 2 4
;
proc nested data=v aov; by g; class a b; run;
