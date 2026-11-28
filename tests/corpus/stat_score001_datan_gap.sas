/* expect-rc: 2
   STAT-SCORE-001 boundary: without OUT=, PROC SCORE creates a data set named
   by the DATAn convention (p.8908), which is not implemented
   (STAT-SCORE-004). The step must fail visibly (D-009 gap) and create no
   data set, never score into an unnamed or guessed member.
   Data: invented. */
options nocenter;
title;
data Raw; input x y; datalines;
1 2
3 4
;
data Coef; input _type_ $ _name_ $ x y; datalines;
SCORE S 1 1
;
proc score data=Raw score=Coef;
var x y;
run;
