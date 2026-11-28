/* STAT-HPGENSELECT-001: PROC HPGENSELECT variable roles and observation
 * selection on invented count data: FREQ (truncation, values below 1 or
 * missing drop the row; Sum of Frequencies Read/Used), ID (recorded only),
 * WEIGHT (nonpositive or missing drops the row; weighted likelihood),
 * missing response, regressor and CLASS values, numeric CLASS levels in
 * value order and character levels in byte order, DIST= abbreviation and
 * the default Poisson log link. Expected listing: SAS 9.4, except Number of
 * Threads, reported truthfully as 1 by opensas (STAT-HP-002).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
ods graphics off;
data cnt;
input id $ g x y f w;
datalines;
a 1 0.5 2 1 1.0
b 1 1.2 3 2 0.5
c 1 2.0 5 1 2.0
d 2 0.3 0 3 1.0
e 2 1.1 1 1 1.5
f 2 1.9 4 2 1.0
g 3 0.4 1 1 0.8
h 3 1.4 2 1 1.2
i 3 2.2 6 2 1.0
j 1 0.9 2 1 1.0
k 2 1.6 3 1 0.7
l 3 1.0 3 1 1.3
m 1 . 2 1 1.0
n 2 1.0 . 1 1.0
o 3 1.0 2 0 1.0
p 1 1.0 2 1 0
q . 1.0 2 1 1.0
r 2 1.0 2 . .
;
proc hpgenselect data=cnt;
class g;
model y = g x / distribution=poisson link=log;
freq f;
id id;
run;
proc hpgenselect data=cnt;
class g;
model y = g x / dist=poisson;
weight w;
run;
data cntc; set cnt; length gc $8; if g=1 then gc='beta'; else if g=2 then gc='alpha'; else if g=3 then gc='Gamma'; run;
proc hpgenselect data=cntc;
class gc;
model y = x gc / distribution=poisson;
run;
