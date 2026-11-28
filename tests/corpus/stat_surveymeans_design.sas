/* STAT-SURVEYMEANS-001: Data Summary, single-unit strata, ALPHA= and
 * STRATA / LIST without TOTAL=. Invented data. Expected listing is the
 * SAS 9.4 (SAS/STAT 15.4) output of this exact program (reference run
 * 2026-11-28):
 * - J, J2: nonpositive weights with STRATA or CLUSTER: Observations is the
 *   count read, Used is after every exclusion (the missing stratum too).
 * - L: single-observation strata of two variables are omitted from each
 *   variance (log NOTE names "y, z").
 * - M, M2: ALPHA=0.1 and 0.025 headings (90%, 97.5%).
 * - N: STRATA / LIST without TOTAL=: no Pop. Total / Rate columns; N per
 *   stratum counts the nonmissing analysis values.
 */
options nodate nonumber nocenter linesize=160;
data a;
input y z w s c g $ k;
datalines;
11 4 2 1 1 a 1
13 5 0 1 1 b 2
12 . 1 1 2 . .
16 7 3 2 3 a 1
. 2 . 2 3 b 2
14 3 1 2 4 . 1
-9 1 1 . 4 a .
15 6 2 2 5 b 2
;
title 'J weight plus strata exclusion';
proc surveymeans data=a; var y z; weight w; strata s; run;
title 'J2 weight plus cluster';
proc surveymeans data=a; var y; weight w; cluster c; run;
title 'L single unit two vars';
proc surveymeans data=a; var y z; strata s c; run;
title 'M alpha 0.1';
proc surveymeans data=a alpha=0.1; var y; run;
title 'M2 alpha 0.025';
proc surveymeans data=a alpha=0.025; var y; run;
title 'N list without total';
proc surveymeans data=a; var y; strata s / list; run;
