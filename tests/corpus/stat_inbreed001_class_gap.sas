/* expect-rc: 2
   STAT-INBREED-001 boundary: MATRIXL (coefficients for the last generation
   only, p.5276) is valid SAS that opensas does not implement yet. The step
   must fail visibly (D-009 gap), never print every generation instead.
   Data: invented. */
options nocenter;
title;
data gen;
input id $ p1 $ p2 $ gen;
datalines;
A . . 1
B . . 1
C A B 2
;
proc inbreed data=gen covar matrixl;
var id p1 p2;
class gen;
run;
