/* expect-rc: 2
 * STAT-PSMATCH-001: valid REGION= forms whose SAS listing is not verified
 * fail visibly (D-009 gap, no listing): REGION=TREATED with zero extension,
 * REGION=ALLOBS with only PSMIN=, CS with LOWER=0 UPPER=0. Invented data.
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
proc psmatch data=s region=treated(extend=0);
class t;
psmodel t(treated='1')=x;
match method=greedy(k=1);
assess lps;
run;
proc psmatch data=s region=allobs(psmin=0.2);
class t;
psmodel t(treated='1')=x;
match method=greedy(k=1);
assess lps;
run;
proc psmatch data=s region=cs(extend=0.25(lower=0 upper=0));
class t;
psmodel t(treated='1')=x;
match method=greedy(k=1);
assess lps;
run;
