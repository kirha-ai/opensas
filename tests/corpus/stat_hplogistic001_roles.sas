/* STAT-HPLOGISTIC-001: variable roles and observation rules on invented
 * data, checked against SAS 15.4 reference runs of the same programs:
 * a continuous-only model (ABSGCONV stop), CLASS + FREQ + WEIGHT (the
 * objective is normalized by the frequency sum; weights scale the
 * likelihood only), missing response / covariate / CLASS values excluded
 * (10 read, 7 used), an ID statement, and two identical BY groups whose
 * results repeat per group.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
data small;
input g $ y x w f;
datalines;
a 0 1 1 1
a 1 2 2 1
a 0 3 1 2
b 1 4 1 1
b 0 5 3 1
b 1 6 1 1
b 1 7 1 3
a 0 8 2 1
;
proc hplogistic data=small;
model y = x;
run;
proc hplogistic data=small;
class g;
model y = g x;
freq f;
weight w;
run;
data m;
input y x c $;
datalines;
1 1 a
0 2 b
. 3 a
1 . b
0 5 a
1 6 b
0 7 a
1 8 a
0 9 b
1 3 .
;
proc hplogistic data=m;
class c;
model y = x c;
id x;
run;
data twice;
set small;
do k = 1 to 2;
output;
end;
run;
proc sort data=twice;
by k;
run;
proc hplogistic data=twice;
by k;
model y = x;
run;
/* Generated invented data: FREQ sums in the thousands, a tiny estimate shown
 * in E notation and five-digit fit statistics (SAS 15.4 reference run). */
data big;
do i = 1 to 3000;
x = mod(i * 7, 13) * 100;
z = mod(i, 5) / 1000;
y = (mod(i * 11, 17) < 8 + mod(i, 3));
f = 1 + mod(i, 4);
output;
end;
run;
proc hplogistic data=big;
model y = x z;
freq f;
run;
proc hplogistic data=big(obs=400);
model y = x z;
run;
