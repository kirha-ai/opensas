/* STAT-CATMOD-005 Generation of the Design Matrix (PDF pp. 2234-2244):
   nested effects A(B), nested-by-value effects A(B=v) with numeric values
   in BEST16 form (2.0, 1E0) and a quoted character value, the design for a
   nested effect under maximum likelihood, and MODEL / DESIGN under maximum
   likelihood with 1, 2 and 3 response functions per population (only the
   shared submatrix is shown, p. 2226). Expected listing: SAS 9.4 reference
   runs of this program (2026-11-28). Data: invented (t, f4), the guide's
   Getting Started cold and school data (colds, school; c2 is colds with
   periods 0 and 1 only). */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title;
data t;
input b a y w @@;
datalines;
1 1 0 5 1 1 1 7 1 1 2 9
1 2 0 8 1 2 1 4 1 2 2 6
1 3 0 3 1 3 1 9 1 3 2 5
2 1 0 6 2 1 1 6 2 1 2 2
2 2 0 4 2 2 1 8 2 2 2 7
2 3 0 9 2 3 1 3 2 3 2 4
;
proc catmod data=t;
weight w;
response means;
model y = b a(b) / design;
run;
model y = b a(b=1) a(b=2.0) / design;
run;
model y = b a(b=1E0) / design;
run;
quit;
data colds;
input sex $ residence $ periods count @@;
datalines;
female rural 0 45 female rural 1 64 female rural 2 71
female urban 0 80 female urban 1 104 female urban 2 116
male rural 0 84 male rural 1 124 male rural 2 82
male urban 0 106 male urban 1 117 male urban 2 87
;
proc catmod data=colds;
weight count;
response means;
model periods = sex residence(sex) / design;
run;
model periods = sex residence(sex='female') / design;
run;
quit;
data school;
length Program $ 9;
input School Program $ Style $ Count @@;
datalines;
1 regular self 10 1 regular team 17 1 regular class 26
1 afternoon self 5 1 afternoon team 12 1 afternoon class 50
2 regular self 21 2 regular team 17 2 regular class 26
2 afternoon self 16 2 afternoon team 12 2 afternoon class 36
3 regular self 15 3 regular team 15 3 regular class 16
3 afternoon self 12 3 afternoon team 12 3 afternoon class 20
;
proc catmod order=data data=school;
weight Count;
model Style=School Program / design;
run;
model Style=Program School(Program);
run;
quit;
data c2;
input sex $ residence $ periods count @@;
datalines;
female rural 0 45 female rural 1 64
female urban 0 80 female urban 1 104
male rural 0 84 male rural 1 124
male urban 0 106 male urban 1 117
;
proc catmod data=c2;
weight count;
model periods = sex residence / design;
run;
quit;
data f4;
input g y w @@;
datalines;
1 1 10 1 2 20 1 3 15 1 4 12
2 1 8 2 2 11 2 3 25 2 4 30
3 1 14 3 2 9 3 3 13 3 4 17
;
proc catmod data=f4;
weight w;
model y = g / design;
run;
quit;
/* Data Summary: the first value column is at least one wider than the
   number field (a 4-digit total with 1-character texts). */
data t;
input g y w @@;
datalines;
1 1 300 1 2 400 2 1 250 2 2 350
;
proc catmod data=t; weight w; response means; model y=g; run; quit;
