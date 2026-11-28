/* expect-rc: 1
 * STAT-PSMATCH-001: invalid REGION= values are user errors (rc 1, no listing):
 * an unknown region, a negative EXTEND=, PSMIN= above 1, PSMIN= > PSMAX=,
 * a bad EXTEND DISTANCE=. Invented data.
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
proc psmatch data=s region=both;
class t;
psmodel t(treated='1')=x;
match method=greedy(k=1);
assess lps;
run;
proc psmatch data=s region=cs(extend=-1);
class t;
psmodel t(treated='1')=x;
match method=greedy(k=1);
assess lps;
run;
proc psmatch data=s region=allobs(psmin=1.5 psmax=1);
class t;
psmodel t(treated='1')=x;
match method=greedy(k=1);
assess lps;
run;
proc psmatch data=s region=allobs(psmin=0.6 psmax=0.4);
class t;
psmodel t(treated='1')=x;
match method=greedy(k=1);
assess lps;
run;
proc psmatch data=s region=treated(extend(distance=mah)=0.1);
class t;
psmodel t(treated='1')=x;
match method=greedy(k=1);
assess lps;
run;
