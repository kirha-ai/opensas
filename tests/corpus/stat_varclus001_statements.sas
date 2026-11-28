/* expect-rc: 1
 * STAT-VARCLUS-001: statement and data rules of PROC VARCLUS on invented
 * data: MAXEIGEN= stopping after one cluster, a formatted BY variable (the
 * BY line shows the formatted value; FORMAT statement in the step), several
 * VAR statements (their variables accumulate), several FREQ or WEIGHT
 * statements (the first is used), and an empty input (WHERE selects no
 * observation: nothing printed, a NOTE, no error). Expected listing: SAS
 * 9.4 / SAS/STAT 15.4 output of this exact program; SAS ends with rc 1
 * because it warns about the omitted observations.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
ods graphics off;
data t;
input g a b c d f w @@;
datalines;
1 1 2 5 3 1 1   1 2 1 3 4 2 0.5   1 3 4 1 2 1 1   1 4 3 2 6 2.7 2
1 5 6 1 1 0.5 1 1 . 5 1 2 1 1     1 6 5 4 5 1 0   1 7 8 2 7 1 1
1 8 6 3 4 3 1.5 2 2 1 7 1 1 1     2 3 3 5 2 1 1   2 1 2 6 3 1 1
2 5 4 2 5 1 1   2 6 7 1 4 1 1     2 4 6 3 6 1 1   2 7 5 2 5 1 1
;
proc format;
value gf 1='One' 2='Two';
run;
proc varclus data=t maxeigen=0.7;
var a b c d;
run;
proc varclus data=t maxc=2;
var a b c d;
by g;
format g gf.;
run;
proc varclus data=t maxc=2;
var a b;
var c d;
run;
proc varclus data=t maxc=2;
var a b c d;
freq f;
freq w;
run;
proc varclus data=t maxc=2;
var a b c d;
weight w;
weight f;
run;
proc varclus data=t(where=(g=9));
var a b c d;
run;
