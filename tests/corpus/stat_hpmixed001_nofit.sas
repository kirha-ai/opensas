/* STAT-HPMIXED-001: NOFIT listings (p.4803) of invented rows: missing
 * response, missing CLASS value, zero and missing WEIGHT, BY groups, ID,
 * NOINT, NOCLPRINT, no RANDOM statement, NOFIT NOINFO (prints nothing) and
 * an empty WHERE selection (WARNING, no listing). Expected words: SAS 9.4
 * listing of this exact program (run 2026-11-28).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
ods graphics off;
data d;
input g $ a b y w tag $;
datalines;
x 1 1 2.5 1 r1
x 1 2 3.1 2 r2
x 2 1 4.0 1 r3
x 2 2 . 1 r4
x 3 1 5.2 0 r5
x 3 2 6.1 . r6
x . 1 6.3 1 r7
y 1 1 2.9 1 r8
y 1 2 3.3 2 r9
y 2 1 4.4 1 r10
y 2 2 4.9 3 r11
y 3 1 5.0 1 r12
y 3 2 6.6 1 r13
;
run;
proc hpmixed data=d nofit;
class a b;
model y = a b a*b;
random a;
run;
proc hpmixed data=d nofit;
by g;
class a b;
id tag;
weight w;
model y = a;
random b a*b;
run;
proc hpmixed data=d nofit;
class a;
model y = a;
run;
proc hpmixed data=d nofit noclprint;
class a b;
model y = a / noint;
random b;
run;
proc hpmixed data=d nofit maxclprint=2 noinfo;
class a b;
model y = a;
random b;
run;
proc hpmixed data=d(where=(y>100)) nofit;
class a;
model y = a;
random a;
run;
proc hpmixed data=d nofit;
class a b;
model y = a;
random b;
run;
