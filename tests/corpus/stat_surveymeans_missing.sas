/* STAT-SURVEYMEANS-001: Missing Values (physical pp.9934-9935). Invented
 * data. Expected listing and log NOTEs are the SAS 9.4 (SAS/STAT 15.4)
 * output of this exact program (reference run 2026-11-28):
 * - A: missing/zero weights drop 2 observations; the Data Summary shows
 *   read, used and nonpositive-weight counts; each analysis variable uses
 *   only its nonmissing observations (y 6, z 5).
 * - B: a missing STRATA value drops the observation silently (7 shown);
 *   z is missing in the only second cluster of stratum 1, so z's design
 *   has a single-cluster stratum, omitted from its variance (log NOTE),
 *   and z's df = 4 clusters - 2 strata = 2, y's df = 5 - 2 = 3.
 * - I: MISSING makes the missing stratum a level (3 strata, 8 obs).
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
proc surveymeans data=a; var y z; weight w; run;
title 'B missing analysis var with strata cluster';
proc surveymeans data=a; var y z; strata s; cluster c; run;
title 'I missing option';
proc surveymeans data=a missing; var z; strata s; run;
