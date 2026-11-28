/* STAT-CANCORR-001: variable roles on invented data. (1) 2 VAR x 3 WITH
 * variables without labels (S=2: the Wilks exact note); one observation
 * with a missing VAR value is omitted (p.2134). (2) The sets swapped with
 * VP= / WP= / VN= / WN= aliases, FREQ (adds observations and degrees of
 * freedom) and WEIGHT (does not alter them), pp.2132-2133. (3) SHORT and no
 * VAR statement: every numeric variable not in WITH forms the VAR set
 * (p.2133). Expected output is the SAS 9.4 (SAS/STAT 15.4) listing.
 */
title; footnote;
ods graphics off;
data t;
input x1 x2 y1 y2 y3 f w;
datalines;
3 7 2 9 4 1 1.5
5 1 6 2 8 2 0.5
2 8 1 7 3 1 2
9 4 8 3 6 3 1
4 6 5 5 5 1 1
7 2 9 1 7 2 3
1 9 3 8 2 1 0.5
6 3 7 4 9 1 1
8 5 4 6 1 2 2
5 5 6 2 4 1 1
2 3 8 8 6 1 1
7 8 2 3 5 2 1
. 4 4 4 4 1 1
;
proc cancorr data=t;
var x1 x2;
with y1 y2 y3;
run;
proc cancorr data=t vp=A wp=B vn='Left' wn='Right';
var y1 y2 y3;
with x1 x2;
freq f;
weight w;
run;
proc cancorr data=t short;
with y1 y2;
run;
