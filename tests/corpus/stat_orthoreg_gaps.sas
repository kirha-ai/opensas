/* expect-rc: 2
 * STAT-ORTHOREG-001: valid ORTHOREG features owned by later tickets fail
 * visibly (D-009 rc 2) with no listing: CLASS (STAT-ORTHOREG-003), OUTEST=
 * (STAT-ORTHOREG-007), MODEL / NOINT (STAT-ORTHOREG-003), ESTIMATE
 * (STAT-ORTHOREG-004) and a rank-deficient design (STAT-ORTHOREG-002).
 * Invented data.
 */
options nosyntaxcheck;
data v;
input g $ x z y;
datalines;
a 1 2 3
a 2 4 5
b 3 6 4
b 4 8 8
c 5 10 9
;
proc orthoreg data=v;
class g;
model y = g;
run;
proc orthoreg data=v outest=est;
model y = x;
run;
proc orthoreg data=v;
model y = x / noint;
run;
proc orthoreg data=v;
model y = x;
estimate 'slope' x 1;
run;
proc orthoreg data=v;
model y = x z;
run;
