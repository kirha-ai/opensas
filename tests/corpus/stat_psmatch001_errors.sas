/* expect-rc: 1
 * STAT-PSMATCH-001: documented invalid input is a user error (rc 1), no
 * data set: MATCH together with FREQ (p.8211), and a PSMODEL that precedes
 * CLASS (p.8202). Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter;
title; footnote;
data s;
input t x f;
datalines;
1 1 1
0 2 1
1 3 2
0 4 1
1 5 1
0 6 2
;
run;
proc psmatch data=s region=cs;
class t;
freq f;
psmodel t(treated='1')=x;
match method=greedy(k=1);
assess lps;
output out(obs=match)=o1;
run;
proc psmatch data=s region=cs;
psmodel t(treated='1')=x;
class t;
match method=greedy(k=1);
assess lps;
run;
