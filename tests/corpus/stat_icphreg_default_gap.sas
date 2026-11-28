/* expect-rc: 2
 * STAT-ICPHREG-001: PROC ICPHREG with no BASEHAZ= option places NINTERVAL=5
 * break points from the data ("Choosing Break Points"); that placement and
 * the lower-bound ("Fixed Parameters") estimates it can produce are not
 * implemented, so the step must fail visibly (D-009 gap) without printing a
 * partial analysis. ITHISTORY is a gap too. Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
data ic;
input lo hi grp;
if lo=0 then lo=.;
datalines;
0 4 1
2 6 0
3 . 1
1 5 0
5 . 0
0 3 1
;
proc icphreg data=ic;
class grp;
model (lo, hi) = grp;
run;
proc icphreg data=ic ithistory;
class grp;
model (lo, hi) = grp / basehaz=pch(intervals=(3));
run;
