/* expect-rc: 2
   STAT-INBREED-001 boundary: the CLASS statement (nonoverlapping
   generations, p.5277) is valid SAS that opensas does not compute yet. The
   step must fail visibly (D-009 gap), never fall back to the overlapping
   analysis. Data: invented. */
options nocenter;
title;
data gen;
input id $ p1 $ p2 $ gen;
datalines;
A . . 1
B . . 1
C A B 2
;
proc inbreed data=gen covar matrix;
var id p1 p2;
class gen;
run;
