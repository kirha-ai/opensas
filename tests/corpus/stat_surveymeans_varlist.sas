/* STAT-SURVEYMEANS-001: VAR variable-list shorthand (y--z is y z in this
 * data set; the expansion is the shared SAS variable-list expander).
 * Invented data. Expected listing is the SAS 9.4 (SAS/STAT 15.4) output of
 * the same step written `var y z;` (reference run 2026-11-28).
 */
options nodate nonumber nocenter linesize=160;
data a;
input y z w s c;
datalines;
11 4 2 1 1
13 5 0 1 1
12 . 1 1 2
16 7 3 2 3
. 2 . 2 3
14 3 1 2 4
-9 1 1 . 4
15 6 2 2 5
;
title 'A excluded weight';
proc surveymeans data=a; var y--z; weight w; run;
