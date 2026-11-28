/* STAT-DISTANCE-001: PROC DISTANCE output-shape rules on invented data:
 * unequal BY groups (width of the first group; a smaller group is padded
 * with an all-missing row carrying the first group's ID value), a repeated
 * ID value (suffix 2), a formatted ID (names use the unformatted values),
 * the DATAn default output name, and an empty input (0 observations and 0
 * variables). Expected values are SAS 9.4 listings of these same steps,
 * written with explicit formats.
 */
options nodate nonumber nocenter linesize=160;
title; footnote;
data s;
input id $ g $ x z;
datalines;
a A 1 1
b A 2 3
c A 4 3
a B 3 5
b B 5 2
;
run;
proc distance data=s out=q1; var interval(x z); by g; run;
data _null_; set q1; file print; put g $1. (Dist1-Dist3) (8.5); run;
proc distance data=s out=q2; var interval(x z); id id; run;
data _null_; set q2; file print; put id $1. (a b c a2 b2) (8.5); run;
proc distance data=s; var interval(x z); run;
proc distance data=s; var interval(x z); run;
data _null_; set data2; file print; put (Dist1-Dist5) (8.5); run;
data e; set s; stop; run;
proc distance data=e out=q4; var interval(x z); run;
proc format; value $idf 'a'='alpha' 'b'='beta' 'c'='gam'; run;
data f; set s; if g='A'; format id $idf.; run;
proc distance data=f out=q5; var interval(x z); id id; run;
data _null_; set q5; file print; put id $idf5. (a b c) (8.5); run;
proc distance data=s out=q6; var interval(x z); by g; id id; run;
data _null_; set q6; file print; put g $1. +1 id $1. (a b c) (8.5); run;
