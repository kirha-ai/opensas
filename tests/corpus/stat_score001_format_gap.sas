/* expect-rc: 2
   STAT-SCORE-001 boundary: a FORMAT or LABEL statement inside PROC SCORE is
   Base syntax outside the chapter's cited statements. SAS 9.4 applies it to
   the new score variable (verified), which opensas does not implement, so
   the step must fail visibly (D-009 gap) and create no data set.
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
proc score data=Raw score=Coef out=Scored;
var x y;
format S 8.3;
run;
