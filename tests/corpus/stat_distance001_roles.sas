/* STAT-DISTANCE-001: PROC DISTANCE variable roles and options on invented
 * data with missing values: BY + ID (distance names from PREFIX= and the ID
 * values) + COPY + FREQ (a FREQ < 1 or missing observation is left out of
 * the standardization only) + WEIGHT; SHAPE=SQUARE CITYBLOCK with RANGE /
 * MIDRANGE scales and WEIGHTS=; CHEBYCHEV with MAXABS and UNDEF=. Expected
 * values are SAS 9.4 listings of these same steps, written with 8.5.
 */
options nodate nonumber nocenter linesize=160;
title; footnote;
data s;
input id $ g $ x z c $ f w;
datalines;
a A 1 1 p 1 1
b A 2 . q 2 2
c A 4 3 r 0 1
d A 7 2 s 1 0.5
a B 3 5 t 1 1
b B . . u 1 1
c B 6 1 v 1.7 2
d B 8 4 w . 1
;
run;
proc distance data=s method=euclid out=o1 prefix=D;
var interval(x z / std=std);
id id; by g; copy c; freq f; weight w;
run;
data _null_;
set o1;
file print;
put g $1. +1 c $1. +1 id $1. (Da Db Dc Dd) (8.5);
run;
proc distance data=s method=cityblock out=o2 shape=square;
var interval(x / std=range) interval(z / std=midrange weights=2);
run;
data _null_;
set o2;
file print;
put (Dist1-Dist8) (8.5);
run;
proc distance data=s method=chebychev out=o4 undef=-1;
var ratio(x z / std=maxabs);
run;
data _null_;
set o4;
file print;
put (Dist1-Dist8) (8.5);
run;
