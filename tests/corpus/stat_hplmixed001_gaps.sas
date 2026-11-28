/* expect-rc: 2
 * STAT-HPLMIXED-001: valid PROC HPLMIXED features outside this ticket fail
 * visibly without a partial listing: METHOD=ML, TECHNIQUE=, a RANDOM
 * statement without TYPE=UN, a non-UN TYPE=, an unbalanced design that
 * needs the iterative optimizer, and the REPEATED statement. Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
data g;
input id $ t y;
datalines;
a 1 1.2
a 2 2.3
a 3 2.9
b 1 0.8
b 2 2.0
c 1 1.9
c 2 3.1
c 3 4.4
;
run;
proc hplmixed data=g method=ml; class id; model y = t; random int t / sub=id type=un; run;
proc hplmixed data=g technique=newrap; class id; model y = t; random int t / sub=id type=un; run;
proc hplmixed data=g; class id; model y = t; random int t / sub=id; run;
proc hplmixed data=g; class id; model y = t; random int t / sub=id type=vc; run;
proc hplmixed data=g; class id; model y = t; random int t / sub=id type=un; run;
proc hplmixed data=g; class id; model y = t; repeated / sub=id; run;
