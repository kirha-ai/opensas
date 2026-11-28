/* STAT-ICPHREG-001: PROC ICPHREG piecewise-constant proportional hazards
 * fit (BASEHAZ=PCH(INTERVALS=)), CLASS / DESC, the default listing and a
 * two-level HAZARDRATIO. Published sample data (SAS/STAT 15.4 chapter 70,
 * Getting Started); expected listing is the SAS 9.4 reference output.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
data hiv;
input Left Right Stage Dose CdLow CdHigh;
if (Left=0) then Left=.;
if (Right>=26) then Right=.;
datalines;
0 16 0 0 0 1
15 26 0 0 0 1
12 26 0 0 0 1
17 26 0 0 0 1
13 26 0 0 0 1
0 24 0 0 1 0
6 26 0 1 1 0
0 15 0 1 1 0
14 26 0 1 1 0
12 26 0 1 1 0
13 26 0 1 0 1
12 26 0 1 1 0
12 26 0 1 1 0
0 18 0 1 0 1
0 14 0 1 0 1
0 17 0 1 1 0
0 15 0 1 1 0
3 26 1 0 0 1
4 26 1 0 0 1
1 11 1 0 0 1
13 19 1 0 0 1
0 6 1 0 0 1
0 11 1 1 0 0
6 26 1 1 0 0
0 6 1 1 0 0
2 12 1 1 0 0
1 17 1 1 1 0
0 14 1 1 0 0
0 25 1 1 0 1
2 11 1 1 0 0
0 14 1 1 0 0
;
proc icphreg data=hiv;
class Stage / desc;
model (Left, Right) = Stage / basehaz=pch(intervals=(10));
hazardratio Stage;
run;
/* NOPRINT fits and validates but displays nothing. */
proc icphreg data=hiv noprint;
class Stage / desc;
model (Left, Right) = Stage / basehaz=pch(intervals=(10));
run;
