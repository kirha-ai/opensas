/* expect-rc: 1
 * STAT-HPLMIXED-001: invalid declarations are user errors (rc 1) with no
 * listing: an invalid METHOD=, NAMELEN= below 20, a negative MAXCLPRINT=,
 * CLASS after MODEL, a missing MODEL statement, a character response, an
 * empty ID statement and an unknown ID variable. Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
data g;
input id $ t y;
datalines;
a 1 1.2
a 2 2.3
b 1 0.8
b 2 2.0
;
run;
proc hplmixed data=g method=bad; class id; model y = t; random int t / sub=id type=un; run;
proc hplmixed data=g namelen=19; class id; model y = t; random int t / sub=id type=un; run;
proc hplmixed data=g maxclprint=-1; class id; model y = t; random int t / sub=id type=un; run;
proc hplmixed data=g; model y = t; class id; random int t / sub=id type=un; run;
proc hplmixed data=g; class id; random int t / sub=id type=un; run;
proc hplmixed data=g; class id; model id = t; random int t / sub=id type=un; run;
proc hplmixed data=g; class id; id; model y = t; random int t / sub=id type=un; run;
proc hplmixed data=g; class id; id nothere; model y = t; random int t / sub=id type=un; run;
