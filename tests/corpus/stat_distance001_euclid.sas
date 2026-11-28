/* STAT-DISTANCE-001: PROC DISTANCE OUT= lower-triangular Euclidean distance
 * matrix of two STD-standardized interval variables (the chapter's sample
 * shape, invented data). Expected values are the SAS 9.4 reference listing of
 * this same step, written here with an explicit 8.5 format.
 */
options nodate nonumber nocenter linesize=160;
title; footnote;
data sample;
input x z y group $ weight freq;
datalines;
1 1 4 A 1 1
2 1 6 A 2 1
3 2 7 A 1 2
4 1 9 A 1 1
5 3 13 A 2 1
6 2 12 A 1 1
7 4 17 B 1 1
8 3 19 B 2 2
9 5 20 B 1 1
10 3 23 B 1 1
11 5 25 B 2 1
12 4 24 B 1 1
;
run;
proc distance data=sample method=euclid out=dist;
var interval(x z /std=std);
run;
data _null_;
set dist;
file print;
put (Dist1-Dist12) (8.5);
run;
