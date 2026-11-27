/* S154 p7247: pair-specific ranks, no continuity correction, actual r=3
   normal-range adjustment. A/B:S=7,E=9,V=2.85; A/C:S=6,E=9,V=2.85;
   B/C:S=3,E=5,V=5/3. Independent40-digit Gaussian-range integrals give
   p=.4623005198616521582,.1773048922144943277,.2680233283417646697. */
ods graphics off;
data sample;
input g $ x;
datalines;
A 1
A 1
A 3
B 2
B 4
C 50
C 60
;
run;
ods trace on;
ods select DSCF;
proc npar1way data=sample dscf;
class g;
var x;
run;
ods trace off;
