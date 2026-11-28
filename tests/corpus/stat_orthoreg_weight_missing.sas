/* STAT-ORTHOREG-001: WEIGHT (PDF pp.7297-7298, with the GLM rule that an
 * observation is used only when its weight is nonmissing and positive),
 * Missing Values (p.7298: a missing model variable drops the observation)
 * and BY boundaries; of two BY statements only the last is used (p.7289).
 * A final NOPRINT step (explicit SINGULAR=, NAMELEN=, ORDER=) prints nothing.
 * Invented data. Group 1 is the weighted line
 * x=0,1,2,3 / y=1,3,2,5 / w=1,2,1,1 plus five rows that must be dropped
 * (missing y, missing x, zero, negative and missing weight); group 2 is an
 * unweighted line. Expected values by hand (exact fractions):
 * group 1: slope 27/26, intercept 35/26, SSE 83/26 (DF 2), SSM 729/130,
 * Corrected Total 44/5 (DF 3); group 2 (x=0..4, y=2,1,5,3,7): slope 6/5,
 * intercept 6/5, SSE 8.8 (DF 3), SSM 14.4, Corrected Total 23.2 (DF 4).
 * Standard errors: sqrt(MSE * [(X'WX)^-1]_ii), e.g. group 2 slope
 * sqrt((8.8/3)/10).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data w;
input g x y w;
datalines;
1 0 1 1
1 1 3 2
1 . 7 1
1 2 2 1
1 3 . 1
1 3 5 1
1 4 9 0
1 5 9 -1
1 6 9 .
2 0 2 1
2 1 1 1
2 2 5 1
2 3 3 1
2 4 7 1
;
proc orthoreg data=w;
by x;
by g;
weight w;
model y = x;
run;
proc orthoreg data=w noprint singular=1e-10 namelen=40 order=data;
by g;
weight w;
model y = x;
run;
