/* expect-rc: 2
 * STAT-COMMON-019: a TYPE=DISTANCE member from PROC DISTANCE OUT= must not be
 * read as coordinates by PROC MODECLUS, whose distance input is not
 * implemented (STAT-MODECLUS-001): a visible D-009 gap. Invented data.
 */
options nodate nonumber nocenter;
title; footnote;
data pts;
   input x y;
   datalines;
0 0
1 2
4 0
4 3
;
run;
proc distance data=pts method=cityblock out=cb;
   var interval(x y);
run;
proc modeclus data=cb r=2 method=1;
run;
