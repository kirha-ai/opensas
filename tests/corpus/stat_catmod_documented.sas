/* STAT-CATMOD-001: PROC CATMOD weighted least squares (RESPONSE MEANS) and
 * maximum likelihood (generalized logits) analyses with WEIGHT, POPULATION,
 * MODEL / DESIGN, ORDER=DATA, the most recent data set and interactive RUN
 * groups. Data: published SAS/STAT 15.4 Chapter 36 cold-incidence and
 * school-program sample data. Every printed value was checked
 * token-for-token against the SAS listing of this program. */
options nodate nonumber nocenter linesize=160;
title;
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
model periods = sex residence sex*residence / design;
run;
model periods = sex residence / design;
run;
population sex residence;
model periods = sex;
run;
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
proc catmod order=data;
weight Count;
model Style=School Program School*Program;
run;
model Style=School Program;
run;
