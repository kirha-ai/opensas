/* expect-rc: 2
 * STAT-CAUSALTRT-001: valid PROC CAUSALTRT requests outside the implemented
 * IPW / IPWR path must fail visibly (D-009 gap) and print no estimates:
 * here METHOD=AIPW with an outcome model (owned by later CAUSALTRT tickets).
 * Invented data.
 */
options nodate nonumber nocenter;
title; footnote;
data s;
input t y x;
datalines;
1 1 1
0 0 2
1 0 3
0 1 4
1 1 2
0 0 5
;
run;
proc causaltrt data=s method=aipw; psmodel t(ref='0')=x; model y(ref='0')=x / dist=bin; run;
