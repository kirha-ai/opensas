/* expect-rc: 1
 * STAT-VARCLUS-001: documented invalid input is a user error (rc 1):
 * MAXCLUSTERS= must be a positive integer, CENTROID cannot be combined with
 * MAXEIGEN= (p.10689), VAR variables must be numeric and exist. The valid
 * step at the end still runs: NOPRINT with OUTSTAT= creates the data set.
 * Invented data: x = 1..4, y = 2 1 4 3, so mean 2.5, StD sqrt(5/3) =
 * 1.2910 and r = 0.6. Hand mathematics for one cluster: eigenvalue 1.6
 * (proportion 0.8), eigenvector (1,1)/sqrt(2), standardized score
 * (1/sqrt(2))/sqrt(1.6) = 0.5590, structure sqrt(0.8) = 0.8944, R-squared
 * 0.8. Missing statistics are shown as -9 to keep the PUT layout simple.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
data t;
input name $ x y z @@;
datalines;
a 1 2 -2 b 2 1 -1 c 3 4 -4 d 4 3 -3
;
proc varclus data=t maxc=0;
run;
proc varclus data=t centroid maxeigen=1;
run;
proc varclus data=t;
var name x;
run;
proc varclus data=t;
var nosuch;
run;
proc varclus data=t maxc=1 noprint outstat=s;
var x y;
run;
data _null_;
set s;
if missing(y) then y = -9;
file print;
put _ncl_ 2. +1 _type_ $8. +1 _name_ $8. +1 x 7.4 +1 y 7.4;
run;
