/* expect-rc: 2
 * STAT-PSMATCH-001: valid PROC PSMATCH requests outside the implemented path
 * fail visibly (D-009 gap) and create no data set: ORDER=RANDOM (SAS
 * pseudo-random stream), the default METHOD=OPTIMAL, and the STRATA
 * statement. Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter;
title; footnote;
data s;
input t x;
datalines;
1 1
0 2
1 3
0 4
1 5
0 6
;
run;
proc psmatch data=s region=cs;
class t;
psmodel t(treated='1')=x;
match method=greedy(k=1 order=random(seed=1));
assess lps;
output out(obs=match)=o1;
run;
proc psmatch data=s region=cs;
class t;
psmodel t(treated='1')=x;
match caliper=0.25;
assess lps;
run;
proc psmatch data=s region=cs;
class t;
psmodel t(treated='1')=x;
strata nstrata=2;
assess lps;
run;
proc print data=o1; run;
