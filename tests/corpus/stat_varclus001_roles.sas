/* expect-rc: 1
 * STAT-VARCLUS-001: variable roles and observation selection of PROC
 * VARCLUS: BY groups (one analysis each), FREQ (integer part; < 1 drops the
 * observation; N is the sum of frequencies), WEIGHT (<= 0 drops it) and
 * observations with a missing VAR value omitted (p.10709). Invented data.
 * Expected listing: SAS 9.4 / SAS/STAT 15.4 output of this exact program;
 * SAS ends with rc 1 because it warns about the omitted observations.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
ods graphics off;
data t;
input g a b c d f w @@;
label a='Alpha score' b='Beta score' c='Gamma score' d='Delta score';
datalines;
1 1 2 5 3 1 1   1 2 1 3 4 2 0.5   1 3 4 1 2 1 1   1 4 3 2 6 2.7 2
1 5 6 1 1 0.5 1 1 . 5 1 2 1 1     1 6 5 4 5 1 0   1 7 8 2 7 1 1
1 8 6 3 4 3 1.5 2 2 1 7 1 1 1     2 3 3 5 2 1 1   2 1 2 6 3 1 1
2 5 4 2 5 1 1   2 6 7 1 4 1 1     2 4 6 3 6 1 1   2 7 5 2 5 1 1
;
proc varclus data=t maxc=2;
var a b c d;
by g;
run;
proc varclus data=t maxc=2;
var a b c d;
freq f;
run;
proc varclus data=t maxc=2;
var a b c d;
weight w;
run;
