/* STAT-NESTED-001: PROC NESTED roles on invented data (D-011): AOV with two
 * VAR variables, BY groups, CLASS names of 2 to 8
 * characters, negative variance components (0 percent, excluded from the
 * total) and observations omitted for a missing CLASS or VAR value. The
 * expected listing is a SAS 15.4 reference run of the same procedures on
 * the same data without the three rows that carry missing values; the
 * blank line SAS writes before each new page title is dropped (opensas
 * starts pages without it).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title 'T';
data d; input Grp Plantxyz Lf Measurement Z @@; datalines;
1 1 1 3 1 1 1 1 5 2 1 1 2 4 4 1 1 2 8 3 1 2 1 6 5 1 2 1 7 7 1 2 2 2 6 1 2 2 4 9
1 2 2 . . 1 . . 5 5
2 1 1 9 1 2 1 1 5 0 2 1 2 6 4 2 1 2 6 2 2 2 1 1 5 2 2 1 3 3 2 2 2 7 6 2 2 2 5 1
2 . . 5 1
;
proc nested data=d aov; class Plantxyz Lf; var Measurement Z; run;
proc nested data=d; by Grp; class Plantxyz Lf; var Measurement; run;
data e; set d; rename Plantxyz=Plantxy Lf=Leafnumb; run;
proc nested data=e(where=(Grp=1)); class Plantxy Leafnumb; var Z; run;
proc nested data=e; class Grp Plantxy; var Z; run;
