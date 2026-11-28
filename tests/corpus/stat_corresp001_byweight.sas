/* STAT-CORRESP-001: VAR input without ID (Row<obs> labels counted within the
 * BY group), BY boundaries, WEIGHT scaling (weight 2 and 0.5), and the
 * documented exclusions (pp.2592, 2601): a missing cell, a negative cell, a
 * missing weight, an all-zero row and a zero weight. DIMENS=1 and the default
 * DIMENS=2 on a 3x3 table; WHERE= selection. Invented data. Expected listing:
 * SAS 9.4 (SAS/STAT 15.4) output.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data S;
input g nm $ a b c w;
datalines;
1 r1 10 20 30 1
1 r2 5 . 9 1
1 r3 8 4 -1 1
1 r4 2 9 6 2
1 r5 7 3 3 .
1 r6 0 0 0 1
1 r7 6 6 1 0.5
1 r8 1 2 3 0
2 r1 3 5 7 1
2 r2 4 1 2 1
2 r3 9 2 5 1
;
ods graphics off;
title "C";
proc corresp data=S out=R2 short dimens=1;
by g;
var a b c;
weight w;
run;
title "D";
proc corresp data=S(where=(g=2)) out=R3 short;
var a b c;
run;
