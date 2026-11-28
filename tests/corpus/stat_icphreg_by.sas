/* STAT-ICPHREG-001: BY boundaries. Two BY groups hold identical copies of
 * the published chapter 70 sample, so each group must reproduce the
 * single-group reference fit; the BY line precedes the procedure title and
 * the Class Level Information table as in the SAS 9.4 reference listing.
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
data _oracle_input; set hiv; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc icphreg data=_oracle_input;
by _oracle_by;
class Stage / desc;
model (Left, Right) = Stage / basehaz=pch(intervals=(10));
run;
