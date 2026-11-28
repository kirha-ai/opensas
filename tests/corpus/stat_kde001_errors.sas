/* expect-rc: 1
 * STAT-KDE-001: invalid PROC KDE input is a user error (rc 1) and the step
 * prints nothing: no UNIVAR/BIVAR statement, unknown variable, NGRID= below 2,
 * BWM=0, BW=0, crossed grid limits, constant data and too few observations.
 * Later valid steps still run (NOSYNTAXCHECK). Invented data; the expected
 * listing is the SAS 9.4 listing of this program.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
ods graphics off;
data t;
input x y @@;
datalines;
0 0 1 1 2 3 3 2 4 4 5 5 6 7 7 6 8 8 9 9 100 100
;
data c;
x = 1; output; output;
run;
data one;
x = 3;
run;
proc kde data=t;
run;
proc kde data=t;
bivar x y z;
run;
proc kde data=t;
univar x / ngrid=1;
run;
proc kde data=t;
univar x / bwm=0;
run;
proc kde data=t;
univar x / bw=0;
run;
proc kde data=t;
univar x / gridl=50 gridu=40 bw=1;
run;
proc kde data=c;
univar x / gridl=0 gridu=2 bw=1;
run;
proc kde data=one;
univar x / bw=1;
run;
proc kde data=t;
univar y / bw=1;
run;
