/* expect-rc: 1
 * STAT-HPMIXED-001: invalid declarations are user errors (rc 1) with no
 * listing: METHOD= other than REML (p.4802), NAMELEN= below 20 (p.4803),
 * a negative MAXCLPRINT=, CLASS after MODEL (p.4817), no MODEL statement,
 * a character response, a character WEIGHT variable, two WEIGHT
 * statements and an unknown variable. Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
data g;
input id $ t y w;
datalines;
a 1 1.2 1
a 2 2.3 1
b 1 0.8 2
b 2 2.0 1
;
run;
proc hpmixed data=g method=ml nofit; class id; model y = t; random id; run;
proc hpmixed data=g namelen=19 nofit; class id; model y = t; random id; run;
proc hpmixed data=g maxclprint=-1 nofit; class id; model y = t; random id; run;
proc hpmixed data=g nofit; model y = t; class id; random id; run;
proc hpmixed data=g nofit; class id; random id; run;
proc hpmixed data=g nofit; class t; model id = t; run;
proc hpmixed data=g nofit; class t; weight id; model y = t; run;
proc hpmixed data=g nofit; class t; weight w; weight w; model y = t; run;
proc hpmixed data=g nofit; class id; model y = t nothere; random id; run;
