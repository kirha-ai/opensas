/* STAT-STDIZE-001: PROC STDIZE METHOD=STD PSTAT with BY and VAR (FREQ/WEIGHT
 * variables present but not used as roles). Invented data. The PSTAT
 * listing matches the SAS 9.4 reference listing for this program; the OUT=
 * values are (x - mean) / std of each BY group, checked by hand arithmetic
 * (group A x: mean 3.5, std sqrt(17.5/5) = 1.870829).
 */
options nodate nonumber nocenter linesize=160;
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
proc sort data=sample;
by group;
run;
proc stdize data=sample out=standardized method=std pstat;
by group;
var x z y;
run;
proc print data=standardized noobs;
format x z y 10.6;
run;
